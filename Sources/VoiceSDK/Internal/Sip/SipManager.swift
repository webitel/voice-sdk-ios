//
//  SipManager.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 20.06.2025.
//

import Foundation
import PJSIPKit


/// All methods must be called on `SDKQueues.sip`.
final class SipManager {
    private let logger = SDKLogger.make("voice.core.sip")
    private var currentAcc = pjsua_acc_id(PJSUA_INVALID_ID.rawValue)
    weak var eventListener: SipEventListener?

    private var settings: CallSettings = CallSettings()
    
    private var isDestroying = false
    private var isActivePjsip = false
    private let videoDevices = SipVideoDevices()

    /// Completions waiting for the result of an in-flight REGISTER.
    private var registrationWaiters: [(Result<Void, Error>) -> Void] = []
    
    init(listener: SipEventListener) {
        self.eventListener = listener
    }


    func makeCall(
        sipConfig: SipConfig,
        toNumber: String,
        toName: String? = nil,
        meetingId: String? = nil,
        type: CallType,
        orientation: VideoOrientation
    ) throws -> Int32 {
        let isVideo = type == .video
        return try performMakeCall(
            sipConfig: sipConfig,
            toNumber: toNumber,
            toName: toName,
            meetingId: meetingId,
            videoCount: isVideo ? 1 : 0,
            orientation: isVideo ? orientation : nil
        )
    }


    private func performMakeCall(
        sipConfig: SipConfig,
        toNumber: String,
        toName: String?,
        meetingId: String?,
        videoCount: UInt32,
        orientation: VideoOrientation?
    ) throws -> Int32 {
        registerSipThread()

        // Establish the correct orientation for *this* call before the capture
        // device is (re)opened, so the existing reapply points (initPjsuaConfigs'
        // cold-start push, syncActiveCaptureDevice's post-open push) act on a value
        // that reflects this call rather than whatever a previous, unrelated call
        // last left `currentOrientation` set to.
        if let orientation { try? setVideoOrientation(orientation) }

        try start(config: sipConfig)

        var owned = OwnedCStrings()
        defer { owned.free() }

        let url = buildUrl(config: sipConfig, toNumber: toNumber, toName: toName)
        var callId: Int32 = -1
        var uri = owned.pjString(url)

        var callSettings = pjsua_call_setting()
        pjsua_call_setting_default(&callSettings)
        callSettings.vid_cnt = videoCount
        callSettings.aud_cnt = 1

        guard let pool = pjsua_pool_create("webitel-invite-hdrs", 512, 512) else {
            throw CallError.sipError(message: "Failed to allocate header pool")
        }
        defer { pj_pool_release(pool) }

        let msgData = makeMsgData()
        defer { msgData.deallocate() }

        if let meetingId, !meetingId.isEmpty {
            addHeader(msgData, pool: pool, name: "X-Webitel-Meeting", value: meetingId)
        }
        addHeader(msgData, pool: pool, name: "X-FS-Support", value: "update_display,send_info")

        let status = pjsua_call_make_call(currentAcc, &uri, &callSettings, nil, msgData, &callId)

        if status != PJ_SUCCESS.rawValue {
            throw CallError.sipError(message: status.description)
        }

        logger.debug("makeCall: success, call id: \(callId)")
        return callId
    }


    /// `pjsua_msg_data_init` links `hdr_list`/`multipart_parts` to the struct's own
    /// address, so it must live at a fixed address — not in a Swift `var`, which the
    /// compiler is free to copy between `&` uses. Caller deallocates.
    private func makeMsgData() -> UnsafeMutablePointer<pjsua_msg_data> {
        let msgData = UnsafeMutablePointer<pjsua_msg_data>.allocate(capacity: 1)
        msgData.initialize(to: pjsua_msg_data())
        pjsua_msg_data_init(msgData)
        return msgData
    }


    /// Adds one custom header to the outgoing INVITE. Allocated from `pool` (not the
    /// stack) because `msgData.hdr_list` is a self-referential circular list — PJSIP
    /// only needs it valid for the duration of the synchronous `pjsua_call_make_call`
    /// call, but a stack-allocated header risks the linkage pointing at memory that's
    /// no longer valid the moment this helper returns.
    private func addHeader(_ msgData: UnsafeMutablePointer<pjsua_msg_data>, pool: UnsafeMutablePointer<pj_pool_t>, name: String, value: String) {
        var owned = OwnedCStrings()
        defer { owned.free() }
        // The header copies both strings into `pool`.
        var hname = owned.pjString(name)
        var hvalue = owned.pjString(value)
        guard let header = pjsip_generic_string_hdr_create(pool, &hname, &hvalue) else { return }
        pj_list_push_back(&msgData.pointee.hdr_list, header)
    }


    /// Starts pjsua if needed and registers the SIP account. `completion` is called
    /// on `SDKQueues.sip` once the registrar answers, or when the SIP stack is destroyed.
    func register(sipConfig: SipConfig, completion: @escaping (Result<Void, Error>) -> Void) {
        // Queued before anything can throw, so the `catch` below always completes it.
        registrationWaiters.append(completion)
        do {
            registerSipThread()
            try start(config: sipConfig)

            let status = pjsua_acc_set_registration(currentAcc, pj_bool_t(PJ_TRUE.rawValue))
            guard status == PJ_SUCCESS.rawValue else {
                throw CallError.sipError(message: "Failed to start SIP registration: \(status.description)")
            }
            logger.debug("register: REGISTER sent for account \(currentAcc)")
        } catch {
            logger.error("register: \(error)")
            completeRegistration(.failure(error))
        }
    }


    /// Called from `on_reg_state2` with the final registrar response code.
    func onRegistrationState(code: Int, reason: String?) {
        SDKQueues.assertOnSip()
        if (200..<300).contains(code) {
            logger.debug("onRegistrationState: registered (\(code))")
            completeRegistration(.success(()))
        } else {
            let message = ["SIP registration failed: \(code)", reason].compactMap { $0 }.joined(separator: " ")
            logger.error("onRegistrationState: \(message)")
            completeRegistration(.failure(CallError.registrationFailed(code: code, message: message)))
        }
    }


    private func completeRegistration(_ result: Result<Void, Error>) {
        let waiters = registrationWaiters
        registrationWaiters.removeAll()
        waiters.forEach { $0(result) }
    }


    func answerCall(withID id: Int32) throws {
        try ensurePjsuaRunning()
        startAudio()

        var opt = pjsua_call_setting()
        pjsua_call_setting_default(&opt)
        opt.aud_cnt = 1
        opt.vid_cnt = 0

        let status = pjsua_call_answer2(pjsua_call_id(id), &opt, 200, nil, nil)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("answerCall: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }


    func sendRinging(withID id: Int32) {
        guard isPjsuaRunning else { return }
        registerSipThread()
        let status = pjsua_call_answer(pjsua_call_id(id), 180, nil, nil)
        if status != PJ_SUCCESS.rawValue {
            logger.warning("sendRinging: \(status.description)")
        }
    }


    func disconnectCall(withID id: Int32, code: UInt32) throws {
        try ensurePjsuaRunning()
        let status = pjsua_call_hangup(pjsua_call_id(id), code, nil, nil)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("disconnectCall: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }

    
    func sendDTMF(_ digits: String, id: Int32) throws {
        try ensurePjsuaRunning()
        var owned = OwnedCStrings()
        defer { owned.free() }
        var f = owned.pjString(digits)
        let status = pjsua_call_dial_dtmf(pjsua_call_id(id), &f)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("sendDTMF: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }
    

    func setHold(_ onHold: Bool, id: Int32) throws {
        try ensurePjsuaRunning()
        let status: pj_status_t = onHold ? pjsua_call_set_hold(pjsua_call_id(id), nil)
                                         : pjsua_call_reinvite(pjsua_call_id(id), 1, nil)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("setHold: \(onHold), \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }
    

    func setMute(_ mute: Bool, id: Int32) throws {
        try ensurePjsuaRunning()
        var ci = pjsua_call_info()
        guard pjsua_call_get_info(id, &ci) == PJ_SUCCESS.rawValue else {
            let message = "Failed to get call info"
            logger.error("setMute: \(message)")
            throw CallError.invalidState(message: message)
        }

        let medias: [pjsua_call_media_info] = tupleToArray(ci.media)
        var processed = false

        for media in medias where media.type == PJMEDIA_TYPE_AUDIO {
            let slot = media.stream.aud.conf_slot
            guard media.status == PJSUA_CALL_MEDIA_ACTIVE, slot != PJSUA_INVALID_ID.rawValue else { continue }
            if mute { pjsua_conf_disconnect(0, slot) } else { pjsua_conf_connect(0, slot) }
            processed = true
        }

        if !processed {
            let message = "No active audio media to mute/unmute"
            logger.error("setMute: \(message)")
            throw CallError.invalidState(message: message)
        }
    }
    
    
    @discardableResult
    func switchCamera(id: Int32) throws -> Int32 {
        try videoDevices.switchCamera(id: id)
    }


    /// See `SipVideoDevices.syncActiveCaptureDevice`.
    func syncActiveCaptureDevice(_ deviceId: Int32, callId: Int32) {
        guard isPjsuaRunning else { return }
        registerSipThread()
        videoDevices.syncActiveCaptureDevice(deviceId, callId: callId)
    }


    func setVideoEnabled(_ enabled: Bool, id: Int32) throws {
        try ensurePjsuaRunning()
        var param = pjsua_call_vid_strm_op_param()
        pjsua_call_vid_strm_op_param_default(&param)
        param.med_idx = -1

        let op = enabled ? PJSUA_CALL_VID_STRM_ADD : PJSUA_CALL_VID_STRM_REMOVE
        let status = pjsua_call_set_vid_strm(pjsua_call_id(id), op, &param)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("setVideoEnabled: \(enabled), \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }


    func setLocalVideoPaused(_ paused: Bool, id: Int32) throws {
        try ensurePjsuaRunning()
        var param = pjsua_call_vid_strm_op_param()
        pjsua_call_vid_strm_op_param_default(&param)
        param.med_idx = -1

        let op = paused ? PJSUA_CALL_VID_STRM_STOP_TRANSMIT : PJSUA_CALL_VID_STRM_START_TRANSMIT
        let status = pjsua_call_set_vid_strm(pjsua_call_id(id), op, &param)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("setLocalVideoPaused: \(paused), \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }


    /// Sends an arbitrary in-dialog request (used for SIP INFO — see `MediaStateInfo`).
    func sendInfo(contentType: String, body: String, id: Int32) throws {
        try ensurePjsuaRunning()
        var owned = OwnedCStrings()
        defer { owned.free() }
        var method = owned.pjString("INFO")
        let msgData = makeMsgData()
        defer { msgData.deallocate() }
        msgData.pointee.content_type = owned.pjString(contentType)
        msgData.pointee.msg_body = owned.pjString(body)

        let status = pjsua_call_send_request(pjsua_call_id(id), &method, msgData)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("sendInfo: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }


    /// See `SipVideoDevices.defaultCaptureDeviceId`.
    func defaultCaptureDeviceId() -> Int32? {
        guard isPjsuaRunning else { return nil }
        registerSipThread()
        return videoDevices.defaultCaptureDeviceId()
    }


    /// See `SipVideoDevices.setVideoOrientation`.
    func setVideoOrientation(_ orientation: VideoOrientation) throws {
        try videoDevices.setVideoOrientation(orientation)
    }


    func startAudio() {
        guard !isDestroying, isActivePjsip else { return }
        registerSipThread()
        
        var dev = pjsua_snd_dev_param()
        pjsua_snd_dev_param_default(&dev)
        dev.capture_dev = 0
        dev.playback_dev = 0
        dev.mode = PJSUA_SND_DEV_NO_IMMEDIATE_OPEN.rawValue
        
        let status = pjsua_set_snd_dev2(&dev)
        if status != PJ_SUCCESS.rawValue {
            logger.error("startAudio: Error set sound dev, status: \(status.description)")
        }
    }

    
    func updateCallSetting(_ settings: CallSettings) {
        self.settings = settings
    }
    

    func destroy(_ onComplete: @escaping () -> Void) {
        registerSipThread()
        logger.debug("Destroy the VoIP service...")

        guard isActivePjsip else {
            onComplete()
            return
        }

        isDestroying = true
        completeRegistration(.failure(CancellationError()))
        pjsua_call_hangup_all()
        pjsua_destroy()
        isActivePjsip = false
        currentAcc = pjsua_acc_id(PJSUA_INVALID_ID.rawValue)
        isDestroying = false

        logger.debug("VoIP service destroyed.")
        onComplete()
    }
    

    private func start(config: SipConfig) throws {
        logger.debug("Open a connection to \(config.getExtension()) with the domain \(config.getDomain()) and proxy \(config.getProxy())...")
        guard !isActivePjsip else {
            logger.debug("pjsip already running")
            return
        }

        try initPjsuaConfigs(config: config)
        isActivePjsip = true
    }


    private func initPjsuaConfigs(config: SipConfig) throws {
        registerSipThread()
        guard pjsua_create() == PJ_SUCCESS.rawValue else {
            let message = "Failed to create pjsua"
            logger.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        // A half-initialised pjsua must be torn down: the next `start()` calls
        // `pjsua_create()` again, which wipes `pjsua_var` under any threads still running.
        var started = false
        defer { if !started { pjsua_destroy() } }

        // PJSIP copies every string it keeps (`pjsua_init`, `pjsua_acc_add`).
        var owned = OwnedCStrings()
        defer { owned.free() }

        let configurator = SipEndpointConfigurator(settings: settings)
        let isVideoEnabled = config.isVideoCallEnabled()

        // Init configs
        var (cfg, logCfg, mediaCfg) = configurator.makeInitConfigs(isVideoEnabled: isVideoEnabled, owned: &owned)

        // Init pjsua
        guard pjsua_init(&cfg, &logCfg, &mediaCfg) == PJ_SUCCESS.rawValue else {
            let message = "Failed to init pjsua"
            logger.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        // Transport
        configurator.createTransport(forProxy: config.getProxy())
        
        // Account configuration
        let renderDevice = isVideoEnabled ? videoDevices.nonMetalRenderDevice() : nil
        // `pjsua_acc_config_default` links `reg_hdr_list`/`sub_hdr_list` to the struct's
        // own address, so it must live at a fixed address (see `makeMsgData`).
        let accCfg = UnsafeMutablePointer<pjsua_acc_config>.allocate(capacity: 1)
        accCfg.initialize(to: pjsua_acc_config())
        defer { accCfg.deallocate() }
        pjsua_acc_config_default(accCfg)
        configurator.configureAccount(accCfg, config: config, renderDevice: renderDevice, owned: &owned)

        // Add account
        var accId = pjsua_acc_id(PJSUA_INVALID_ID.rawValue)
        guard pjsua_acc_add(accCfg, pj_bool_t(PJ_TRUE.rawValue), &accId) == PJ_SUCCESS.rawValue else {
            let message = "Failed to add SIP account"
            logger.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        currentAcc = accId

        // Start pjsua
        guard pjsua_start() == PJ_SUCCESS.rawValue else {
            let message = "Failed to start pjsua"
            logger.error("initPjsuaConfigs: \(message)")
            currentAcc = pjsua_acc_id(PJSUA_INVALID_ID.rawValue)
            throw CallError.sipError(message: message)
        }
        started = true

        if isVideoEnabled {
            configurator.setupVideoCodec(w: 1280, h: 720)
            videoDevices.reapplyOrientation()
        }

        configurator.setCodecPriority()
        pjsua_set_no_snd_dev()
        isActivePjsip = true
    }


    private func buildUrl(config: SipConfig, toNumber: String, toName: String? = nil) -> String {
        return "\"\(toName ?? "")\"<sip:\(toNumber)@\(config.getServerUri())>"
    }
}
