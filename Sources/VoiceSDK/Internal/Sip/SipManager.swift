//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 20.06.2025.
//

import Foundation
import PJSIPKit


final class SipManager {
    private var currentAcc = pjsua_acc_get_default()
    weak var eventListener: SipEventListener?
    
    private let dispatchQueue = DispatchQueue(label: "com.webitel.sip.SipManager")
    private var settings: CallSettings = CallSettings()
    
    private var isDestroying = false
    private var isActivePjsip = false
    
    private let defaultGoogleStunServer = "stun.l.google.com:19302"
    private let PJ_MAX_STUN_SERVERS = 8

    init(listener: SipEventListener) {
        self.eventListener = listener
    }


    func makeCall(sipConfig: SipConfig, toNumber: String, toName: String? = nil) throws -> Int32 {
        var result: Result<Int32, Error>!
        
        dispatchQueue.sync {
            do {
                registerThread()
                try start(config: sipConfig)
                
                let url = buildUrl(config: sipConfig, toNumber: toNumber, toName: toName)
                var callId: Int32 = -1
                var uri = pj_str(strdup(url))
                
                var callSettings = pjsua_call_setting()
                pjsua_call_setting_default(&callSettings)
                callSettings.vid_cnt = 0
                callSettings.aud_cnt = 1
                
                let status = pjsua_call_make_call(currentAcc, &uri, &callSettings, nil, nil, &callId)
                
                if status != PJ_SUCCESS.rawValue {
                    throw CallError.sipError(message: status.description)
                }
                
                WLog.shared.debug("makeCall: success, call id: \(callId)")
                result = .success(callId)
                
            } catch {
                result = .failure(error)
            }
        }
        return try result.get()
    }
    

    func disconnectCall(withID id: Int32, code: UInt32) throws {
        registerThread()
        let status = pjsua_call_hangup(pjsua_call_id(id), code, nil, nil)
        guard status == PJ_SUCCESS.rawValue else {
            WLog.shared.error("disconnectCall: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }

    
    func sendDTMF(_ digits: String, id: Int32) throws {
        registerThread()
        var f = pj_str(strdup(digits))
        let status = pjsua_call_dial_dtmf(pjsua_call_id(id), &f)
        guard status == PJ_SUCCESS.rawValue else {
            WLog.shared.error("sendDTMF: \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }
    

    func setHold(_ onHold: Bool, id: Int32) throws {
        registerThread()
        let status: pj_status_t = onHold ? pjsua_call_set_hold(pjsua_call_id(id), nil)
                                         : pjsua_call_reinvite(pjsua_call_id(id), 1, nil)
        guard status == PJ_SUCCESS.rawValue else {
            WLog.shared.error("setHold: \(onHold), \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }
    

    func setMute(_ mute: Bool, id: Int32) throws {
        registerThread()
        var ci = pjsua_call_info()
        guard pjsua_call_get_info(id, &ci) == PJ_SUCCESS.rawValue else {
            let message = "Failed to get call info"
            WLog.shared.error("setMute: \(message)")
            throw CallError.invalidState(message: message)
        }

        let medias: [pjsua_call_media_info] = tupleToArray(ci.media, as: pjsua_call_media_info.self)
        var processed = false

        for media in medias where media.type == PJMEDIA_TYPE_AUDIO {
            let slot = media.stream.aud.conf_slot
            guard media.status == PJSUA_CALL_MEDIA_ACTIVE, slot != PJSUA_INVALID_ID.rawValue else { continue }
            if mute { pjsua_conf_disconnect(0, slot) } else { pjsua_conf_connect(0, slot) }
            processed = true
        }

        if !processed {
            let message = "No active audio media to mute/unmute"
            WLog.shared.error("setMute: \(message)")
            throw CallError.invalidState(message: message)
        }
    }
    
    
    func startAudio() {
        guard !isDestroying, isActivePjsip else { return }
        registerThread()
        
        var dev = pjsua_snd_dev_param()
        pjsua_snd_dev_param_default(&dev)
        dev.capture_dev = 0
        dev.playback_dev = 0
        dev.mode = PJSUA_SND_DEV_NO_IMMEDIATE_OPEN.rawValue
        
        let status = pjsua_set_snd_dev2(&dev)
        if status != PJ_SUCCESS.rawValue {
            WLog.shared.error("startAudio: Error set sound dev, status: \(status.description)")
        }
    }

    
    func updateCallSetting(_ settings: CallSettings) {
        self.settings = settings
    }
    

    func destroy(_ onComplete: @escaping () -> Void) {
        dispatchQueue.async(flags: .barrier) {
            self.registerThread()
            WLog.shared.debug("Destroy the VoIP service...")
            
            guard self.isActivePjsip else {
                onComplete()
                return
            }
            
            self.isDestroying = true
            pjsua_call_hangup_all()
            pjsua_destroy()
            self.isActivePjsip = false
            self.isDestroying = false
            
            WLog.shared.debug("VoIP service destroyed.")
            onComplete()
        }
    }
    

    private func start(config: SipConfig) throws {
        WLog.shared.debug("Open a connection to \(config.getExtension()) with the domain \(config.getDomain()) and password \(config.getPassword()) and proxy \(config.getProxy())...")
        guard !isActivePjsip else {
            WLog.shared.debug("pjsip already running")
            return
        }
        
        try initPjsuaConfigs(config: config)
        isActivePjsip = true
    }

    
    private func initPjsuaConfigs(config: SipConfig) throws {
        registerThread()
        guard pjsua_create() == PJ_SUCCESS.rawValue else {
            let message = "Failed to create pjsua"
            WLog.shared.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        // 2. Init configs
        var cfg = pjsua_config()
        var logCfg = pjsua_logging_config()
        var mediaCfg = pjsua_media_config()
        pjsua_config_default(&cfg)
        pjsua_logging_config_default(&logCfg)
        pjsua_media_config_default(&mediaCfg)

        // Logging
    #if DEBUG
        logCfg.msg_logging = pj_bool_t(PJ_TRUE.rawValue)
        logCfg.console_level = 5
        logCfg.level = 5
    #else
        logCfg.msg_logging = pj_bool_t(PJ_FALSE.rawValue)
        logCfg.console_level = 0
        logCfg.level = 0
    #endif

        // Media configuration
        mediaCfg.has_ioqueue = pj_bool_t(PJ_FALSE.rawValue)
        mediaCfg.quality = 5
        mediaCfg.thread_cnt = 1
        mediaCfg.clock_rate = 48000
        mediaCfg.channel_count = 2
        mediaCfg.ec_options = 0
        mediaCfg.ec_tail_len = 0
        mediaCfg.no_vad = pj_bool_t(PJ_TRUE.rawValue)
        mediaCfg.enable_ice = settings.iceEnabled ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)

        // STUN servers
        var stunServers = settings.useDefaultStun ? [defaultGoogleStunServer] : []
        stunServers.append(contentsOf: settings.stunServers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let count = min(stunServers.count, PJ_MAX_STUN_SERVERS)
        cfg.stun_srv_cnt = UInt32(count)
        if count > 0 {
            withUnsafeMutablePointer(to: &cfg.stun_srv) { ptr in
                let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: pj_str_t.self)
                for i in 0..<count {
                    stunServers[i].withCString { cString in
                        base[i] = pj_str(strdup(cString))
                    }
                }
            }
        }

        // Callbacks
        cfg.cb.on_call_state = on_call_state
        cfg.cb.on_call_media_state = on_call_media_state

        // User agent
        cfg.user_agent = pj_str(strdup("webitel for ios"))

        // Init pjsua
        guard pjsua_init(&cfg, &logCfg, &mediaCfg) == PJ_SUCCESS.rawValue else {
            let message = "Failed to init pjsua"
            WLog.shared.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        // Transport
        let transport = transportFrom(sipUri: config.getProxy()) ?? .TCP_UDP
        createTransport(transport)
        
        /* Init account config */
        let id = strdup("sip:\(config.getExtension())@\(config.getDomain())")
        let username = strdup(config.getAuth())
        let passwd = strdup(config.getPassword())
        let realm = strdup("*")
        let scheme = strdup("digest")

        // Account configuration
        var accCfg = pjsua_acc_config()
        pjsua_acc_config_default(&accCfg)
        accCfg.id = pj_str(id)
        
        accCfg.cred_count = 1
        accCfg.cred_info.0.username = pj_str(username)
        accCfg.cred_info.0.realm = pj_str(realm)
        accCfg.cred_info.0.data = pj_str(passwd)
        accCfg.cred_info.0.scheme = pj_str(scheme)
        accCfg.cred_info.0.data_type = 0
        
        accCfg.allow_contact_rewrite = settings.contactRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.allow_via_rewrite = settings.viaRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.allow_sdp_nat_rewrite = settings.sdpNatRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.use_srtp = getPjsipCode(code: settings.srtpUse)

        // ICE config
        if settings.iceEnabled {
            accCfg.ice_cfg_use = PJSUA_ICE_CONFIG_USE_CUSTOM
            accCfg.ice_cfg.enable_ice = pj_bool_t(PJ_TRUE.rawValue)
            accCfg.ice_cfg.ice_always_update = pj_bool_t(PJ_TRUE.rawValue)
        }

        // Add account
        guard pjsua_acc_add(&accCfg, pj_bool_t(PJ_TRUE.rawValue), nil) == PJ_SUCCESS.rawValue else {
            let message = "Failed to add SIP account"
            WLog.shared.error("initPjsuaConfigs: \(message)")
            pjsua_destroy()
            throw CallError.sipError(message: message)
        }

        /* Free strings */
        free(id); free(username); free(passwd)
        free(scheme); free(realm)

        // Start pjsua
        guard pjsua_start() == PJ_SUCCESS.rawValue else {
            let message = "Failed to start pjsua"
            WLog.shared.error("initPjsuaConfigs: \(message)")
            throw CallError.sipError(message: message)
        }

        setCodecPriority()
        pjsua_set_no_snd_dev()
        isActivePjsip = true
    }

    
    private func registerThread() {
        if pj_thread_is_registered() == 0 {
            var thread: OpaquePointer?
            var desc = Array(repeating: 0, count: Int(PJ_THREAD_DESC_SIZE))
            pj_thread_register(nil, &desc[0], &thread)
        }
    }
    

    private func buildUrl(config: SipConfig, toNumber: String, toName: String? = nil) -> String {
        return "\"\(toName ?? "")\"<sip:\(toNumber)@\(config.getServerUri())>"
    }

    
    private func tupleToArray<T>(_ tuple: Any, as type: T.Type) -> [T] {
        Mirror(reflecting: tuple).children.compactMap { $0.value as? T }
    }
    

    private func setCodecPriority() {
        let codecs = [
            "opus/48000/2": PJMEDIA_CODEC_PRIO_HIGHEST.rawValue,
            "G722/16000/1": 135,
            "PCMU/8000/1": 133,
            "PCMA/8000/1": PJMEDIA_CODEC_PRIO_NORMAL.rawValue,
            "speex/16000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "speex/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "speex/32000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "iLBC/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "GSM/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue
        ]
        var codec = pj_str_t()
        for (name, prio) in codecs {
            pjsua_codec_set_priority(pj_cstr(&codec, name), pj_uint8_t(prio))
        }
    }

    
    private func createTransport(_ transport: Transport) {
        WLog.shared.debug("Create transport: \(transport)")
        switch transport {
            case .UDP: initTransport(type: PJSIP_TRANSPORT_UDP)
            case .TCP: initTransport(type: PJSIP_TRANSPORT_TCP)
            case .TLS: initTransport(type: PJSIP_TRANSPORT_TLS)
            case .TCP_UDP: initTransport(type: PJSIP_TRANSPORT_TCP); initTransport(type: PJSIP_TRANSPORT_UDP)
        }
    }
    

    private func initTransport(type: pjsip_transport_type_e) {
        pj_activesock_enable_iphone_os_bg(pj_bool_t(PJ_FALSE.rawValue))
        var transportId = pjsua_transport_id()
        var cfg = pjsua_transport_config()
        pjsua_transport_config_default(&cfg)
        cfg.qos_type = PJ_QOS_TYPE_VOICE
        let status = pjsua_transport_create(type, &cfg, &transportId)
        if status != PJ_SUCCESS.rawValue {
            WLog.shared.warning("Transport \(type) not created")
        }
    }
    

    private func transportFrom(sipUri: String) -> Transport? {
        let components = sipUri.split(separator: ";")
        for comp in components {
            let pair = comp.split(separator: "=")
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "transport" {
                switch pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "tcp": return .TCP
                    case "udp": return .UDP
                    case "tls": return .TLS
                    default: return nil
                }
            }
        }
        return nil
    }


    private func getPjsipCode(code: SrtpUse) -> pjmedia_srtp_use {
        switch code {
            case .PJMEDIA_SRTP_OPTIONAL: return PJMEDIA_SRTP_OPTIONAL
            case .PJMEDIA_SRTP_MANDATORY: return PJMEDIA_SRTP_MANDATORY
            default: return PJMEDIA_SRTP_DISABLED
        }
    }
}


enum Transport: Int, Codable, CaseIterable {
    case UDP = 0
    case TCP = 1
    case TCP_UDP = 2
    case TLS = 3
}
