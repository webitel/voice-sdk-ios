//
//  CallImpl.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//

import Foundation
import PJSIPKit


/// Threading: public methods validate against the current state synchronously (throwing
/// `invalidState`) and then perform the actual work on `SDKQueues.sip`, so they never block
/// the caller. State visible through `Call` lives in `store` and is readable from any thread;
/// it is written only on `SDKQueues.sip`. Everything else is confined to `SDKQueues.sip`.
class CallImpl: Call {
    /// State readable from any thread.
    private struct Snapshot {
        var state: CallState = .idle
        var sipId: Int32 = PJSUA_INVALID_ID.rawValue
        var holdTarget: Bool?
        var isMuted = false
        var isOnHold = false
        var hasVideo = false
        var answeredAt: Int64 = 0
        var isSpeakerphoneOn = false
        var isLocalVideoPaused = false
        var isRemoteMuted = false
        var isRemoteOnHold = false
        var isRemoteVideoPaused = false
        var isLocalVideoActive = false
        var isRemoteVideoActive = false
    }

    private let store = Protected(Snapshot())
    private let observers = CallObserverHub()
    private let apiConfigTask = Protected<Task<Void, Never>?>(nil)
    weak var delegate: (CallControlDelegate)?
    /// Takes over user actions in SDK-managed CallKit mode.
    weak var actionRouter: CallActionRouter?
    private let ratingProvider: CallRatingProvider
    let logger = SDKLogger.make("voice.core.call")

    /// Confined to `SDKQueues.sip`.
    private(set) lazy var video = CallVideoController(
        delegate: delegate,
        initialOrientation: initialOrientation,
        sipId: { [unowned self] in self.sipId }
    )

    let id: UUID
    let meetingId: String?
    let remoteName: String?
    let remoteNumber: String?
    let isOutgoing: Bool

    var sipId: Int32 {
        get { store.read { $0.sipId } }
        set { store.write { $0.sipId = newValue } }
    }
    /// The hold state a hold/unhold re-INVITE is in flight for; `nil` when none is.
    var holdTarget: Bool? {
        get { store.read { $0.holdTarget } }
        set { store.write { $0.holdTarget = newValue } }
    }
    var isHoldInProgress: Bool {
        holdTarget != nil
    }
    var state: CallState {
        get { store.read { $0.state } }
        set { store.write { $0.state = newValue } }
    }
    var isMuted: Bool {
        get { store.read { $0.isMuted } }
        set { store.write { $0.isMuted = newValue } }
    }
    var isOnHold: Bool {
        get { store.read { $0.isOnHold } }
        set { store.write { $0.isOnHold = newValue } }
    }
    var hasVideo: Bool {
        get { store.read { $0.hasVideo } }
        set { store.write { $0.hasVideo = newValue } }
    }
    var answeredAt: Int64 {
        get { store.read { $0.answeredAt } }
        set { store.write { $0.answeredAt = newValue } }
    }
    var isSpeakerphoneOn: Bool {
        get { store.read { $0.isSpeakerphoneOn } }
        set { store.write { $0.isSpeakerphoneOn = newValue } }
    }
    var isLocalVideoPaused: Bool {
        get { store.read { $0.isLocalVideoPaused } }
        set { store.write { $0.isLocalVideoPaused = newValue } }
    }
    var isRemoteMuted: Bool {
        get { store.read { $0.isRemoteMuted } }
        set { store.write { $0.isRemoteMuted = newValue } }
    }
    var isRemoteOnHold: Bool {
        get { store.read { $0.isRemoteOnHold } }
        set { store.write { $0.isRemoteOnHold = newValue } }
    }
    var isRemoteVideoPaused: Bool {
        get { store.read { $0.isRemoteVideoPaused } }
        set { store.write { $0.isRemoteVideoPaused = newValue } }
    }
    var isLocalVideoActive: Bool {
        get { store.read { $0.isLocalVideoActive } }
        set { store.write { $0.isLocalVideoActive = newValue } }
    }
    var isRemoteVideoActive: Bool {
        get { store.read { $0.isRemoteVideoActive } }
        set { store.write { $0.isRemoteVideoActive = newValue } }
    }

    /// `answer()` was called before the incoming INVITE arrived.
    var pendingAnswer = false
    var incomingTimeout: DispatchWorkItem?

    var videoState: VideoState {
        switch (isLocalVideoActive, isRemoteVideoActive) {
        case (false, false): return .inactive
        case (true, false): return .localOnly
        case (false, true): return .remoteOnly
        case (true, true): return .active
        }
    }

    var isAnswered: Bool {
        answeredAt > 0
    }


    /// See `CallVideoController.initialOrientation`.
    private let initialOrientation: VideoOrientation

    init(
        delegate: CallControlDelegate,
        ratingProvider: CallRatingProvider,
        id: UUID = UUID(),
        isOutgoing: Bool = true,
        remoteName: String? = nil,
        remoteNumber: String? = nil,
        meetingId: String? = nil,
        hasVideo: Bool = false,
        initialState: CallState = .idle,
        initialOrientation: VideoOrientation = .portrait
    ) {
        self.delegate = delegate
        self.ratingProvider = ratingProvider
        self.id = id
        self.isOutgoing = isOutgoing
        self.remoteName = remoteName
        self.remoteNumber = remoteNumber
        self.meetingId = meetingId
        self.initialOrientation = initialOrientation
        store.write {
            $0.hasVideo = hasVideo
            $0.state = initialState
        }
    }


    /// Validates synchronously so the caller gets `invalidState` right away, then runs
    /// `action` on `SDKQueues.sip`, re-validating first since the state may have changed
    /// in between. Errors there can no longer reach the caller and are logged.
    private func enqueue(
        _ name: String,
        validate: @escaping () throws -> Void,
        action: @escaping () throws -> Void
    ) throws {
        try validate()
        SDKQueues.sip.async { [self] in
            do {
                try validate()
                try action()
            } catch {
                logger.error("\(name): \(error)")
            }
        }
    }


    func mute(_ mute: Bool) throws {
        logger.debug("mute \(mute)")
        try submit(.mute(mute))
    }


    func hold(_ hold: Bool) throws {
        logger.debug("hold \(hold)")
        if case .ongoing = state, isHoldSatisfied(hold) {
            logger.debug("hold \(hold) - no action needed")
            return
        }
        try submit(.hold(hold))
    }


    func sendDTMF(_ digits: String) throws {
        logger.debug("sendDTMF \(digits)")
        try submit(.dtmf(digits))
    }


    func answer() throws {
        logger.debug("answer call")
        try submit(.answer)
    }


    func disconnect() throws {
        logger.debug("disconnect call")
        // Stop an in-flight SIP config/registration right away, not only once the queue gets here.
        if case .disconnected = state {} else if sipId < 0 { cancelTask() }
        try submit(.end)
    }


    // MARK: - Actions

    /// Like `enqueue`, but lets `actionRouter` take the action over first (CallKit),
    /// in which case it comes back through `performAction(_:)`.
    private func submit(_ action: CallAction) throws {
        try validate(action)
        if actionRouter?.route(action, for: self) == true { return }
        SDKQueues.sip.async { [self] in
            do {
                try performAction(action)
            } catch {
                logger.error("\(action): \(error)")
            }
        }
    }


    /// Performs a validated action without routing it. Re-validates first, since the
    /// state may have changed since it was submitted. Must be called on `SDKQueues.sip`.
    func performAction(_ action: CallAction) throws {
        SDKQueues.assertOnSip()
        try validate(action)
        switch action {
            case .answer: try performAnswer()
            case .end: try internalDisconnect(CallEndReason.from(code: 0), cancelTask: true)
            case .mute(let muted): performMute(muted)
            case .hold(let onHold): try performHold(onHold)
            case .dtmf(let digits): try delegate?.sendDTMF(withID: sipId, digits: digits)
        }
    }


    private func validate(_ action: CallAction) throws {
        switch action {
            case .answer:
                guard !isOutgoing else {
                    let message = "Only incoming calls can be answered"
                    logger.error("\(message)")
                    throw CallError.invalidState(message: message)
                }
                guard case .ringing = state else {
                    let message = "Call is not ringing. Current state: \(state)"
                    logger.error("\(message)")
                    throw CallError.invalidState(message: message)
                }

            case .end:
                if case .disconnected = state {
                    logger.error("Call already disconnected — ignoring")
                    throw CallError.invalidState(message: state.description)
                }

            case .mute:
                try ensureMediaControlAllowed()
                try ensureSipIdValid()

            case .hold(let onHold):
                if case .ongoing = state, isHoldSatisfied(onHold) { return }
                try ensureHoldAllowed()

            case .dtmf:
                try ensureCallOngoing()
                try ensureSipIdValid()
        }
    }


    private func performAnswer() throws {
        if sipId < 0 {
            // INVITE not received yet — answered in `onIncomingInviteReceived`.
            logger.debug("answer: INVITE not received yet, answer is pending")
            pendingAnswer = true
        } else {
            do {
                try delegate?.answerCall(withID: sipId)
            } catch {
                disconnectWithReason(callEndReason: .from(code: -1, "\(error)"))
                throw error
            }
        }
        updateState(.connecting)
    }


    private func performMute(_ mute: Bool) {
        if isMuted == mute {
            logger.debug("mute \(mute) - no action needed")
            return
        }

        do {
            try delegate?.muteCall(withID: sipId, muted: mute)
        } catch {
            // No active audio media yet (still connecting/ringing) — record the
            // desired state; onCallMediaState's mute-restore logic (VoiceManager)
            // applies it for real as soon as audio media actually activates.
            logger.debug("mute \(mute) (pending): no active audio media yet – \(error)")
        }
        isMuted = mute
        notify(.localMedia(.muteChanged(callId: id, isMuted: mute)))
        sendMediaStateInfo()
    }


    /// Also used by `VoiceManager` to hold this call when another one becomes active.
    /// Idempotent: CallKit may request a hold the SDK already started, and vice versa.
    /// Must be called on `SDKQueues.sip`.
    func performHold(_ hold: Bool) throws {
        SDKQueues.assertOnSip()
        if case .ongoing = state, isHoldSatisfied(hold) {
            logger.debug("hold \(hold) - no action needed")
            return
        }
        try ensureHoldAllowed()

        try delegate?.holdCall(withID: sipId, onHold: hold)
        holdTarget = hold
    }


    /// The call is in, or already on its way to, the requested hold state.
    private func isHoldSatisfied(_ hold: Bool) -> Bool {
        (holdTarget ?? isOnHold) == hold
    }


    /// Can be called from any thread; the disconnect itself runs on `SDKQueues.sip`.
    func disconnectWithReason(callEndReason: CallEndReason) {
        SDKQueues.sip.async { [self] in
            do {
                try internalDisconnect(callEndReason)
            } catch {
                logger.error("disconnectWithReason: error – \(error)")
            }
        }
    }


    // MARK: - Media Controls

    func setSpeakerphoneOn(_ enabled: Bool) throws {
        try enqueue("setSpeakerphoneOn", validate: { [self] in
            try ensureCallOngoing()
        }) { [self] in
            try applySpeakerphone(enabled)
        }
    }


    /// Compares against the actual route rather than `isSpeakerphoneOn`: the route
    /// may have been changed outside the SDK (e.g. the CallKit speaker button).
    private func applySpeakerphone(_ enabled: Bool) throws {
        if delegate?.isSpeakerActive == enabled {
            syncSpeakerphone(enabled)
            return
        }

        try delegate?.setSpeakerphoneOn(enabled)
        syncSpeakerphone(enabled)
    }


    /// Reflects the actual audio route; called on `SDKQueues.sip` on every route change.
    func syncSpeakerphone(_ isOn: Bool) {
        guard isSpeakerphoneOn != isOn else { return }
        isSpeakerphoneOn = isOn
        notify(.localMedia(.speakerphoneChanged(callId: id, isSpeakerphoneOn: isOn)))
    }


    /// Video calls are expected to default to loudspeaker output rather than the
    /// quiet earpiece — this applies that default once, the first time the call
    /// becomes video, without overriding a user's subsequent manual choice.
    func autoEnableSpeakerForVideo() {
        guard hasVideo else { return }
        do {
            try applySpeakerphone(true)
        } catch {
            logger.error("autoEnableSpeakerForVideo: \(error)")
        }
    }


    func switchCamera() throws {
        try enqueue("switchCamera", validate: { [self] in
            try ensureCallOngoing()
            try ensureSipIdValid()
            try ensureHasVideo()
        }) { [self] in
            if let newDeviceId = try delegate?.switchCamera(withID: sipId),
               let preview = video.refreshPreviewAfterCameraSwitch(newDeviceId) {
                notify(.video(.localViewReady(callId: id, view: preview)))
            }
        }
    }


    func enableVideo() throws {
        try enqueue("enableVideo", validate: { [self] in
            try ensureCallOngoing()
            try ensureSipIdValid()
        }) { [self] in
            guard !hasVideo else { return }

            try delegate?.setVideoEnabled(withID: sipId, enabled: true)
            hasVideo = true
            autoEnableSpeakerForVideo()
        }
    }


    func disableVideo() throws {
        try enqueue("disableVideo", validate: { [self] in
            try ensureCallOngoing()
            try ensureSipIdValid()
        }) { [self] in
            guard hasVideo else { return }

            try delegate?.setVideoEnabled(withID: sipId, enabled: false)
            hasVideo = false
            isLocalVideoActive = false
            video.stopLocalPreview()
            notify(.video(.stateChanged(callId: id, state: videoState)))
        }
    }


    func setLocalVideoPaused(_ paused: Bool) throws {
        try enqueue("setLocalVideoPaused", validate: { [self] in
            try ensureMediaControlAllowed()
            try ensureSipIdValid()
            try ensureHasVideo()
        }) { [self] in
            performSetLocalVideoPaused(paused)
        }
    }


    private func performSetLocalVideoPaused(_ paused: Bool) {
        if isLocalVideoPaused == paused {
            return
        }

        do {
            try delegate?.setLocalVideoPaused(withID: sipId, paused: paused)
        } catch {
            // No active local video media yet (still connecting/ringing) — record
            // the desired state; onShowLocalVideo re-applies it for real as soon
            // as local video actually activates.
            logger.debug("setLocalVideoPaused \(paused) (pending): no active local video media yet – \(error)")
        }
        isLocalVideoPaused = paused
        notify(.localMedia(.videoPausedChanged(callId: id, isPaused: paused)))
        sendMediaStateInfo()
    }


    func setVideoOrientation(_ orientation: VideoOrientation) throws {
        try enqueue("setVideoOrientation", validate: { [self] in
            try ensureCallOngoing()
            try ensureSipIdValid()
            try ensureHasVideo()
        }) { [self] in
            video.setOrientation(orientation)
        }
    }


    // MARK: - Rating
    //
    // Deliberately independent of `apiTask(_:)`: rating happens after the
    // call has already ended, so it must not touch `state` or trigger
    // `disconnect()` on failure the way `apiTask` does for call setup.

    func isRatable() async throws -> Bool {
        guard let meetingId else {
            logger.debug("isRatable: no meetingId associated with this call")
            return false
        }
        return try await ratingProvider.checkRatable(meetingId: meetingId)
    }


    func rate(_ satisfaction: String) async throws {
        guard let meetingId else {
            let message = "Call has no associated meetingId and cannot be rated."
            logger.error("\(message)")
            throw CallError.invalidState(message: message)
        }
        try await ratingProvider.submitRating(meetingId: meetingId, satisfaction: satisfaction)
    }


    // MARK: - State & Observers

    /// Thread-safe; normally called on `SDKQueues.sip`.
    func updateState(_ state: CallState) {
        logger.debug("onCallState: from - \(self.state), to - \(state)")
        self.state = state
        notify(.connection(.stateChanged(callId: id, state: state)))
    }


    func addObserver(_ observer: CallObserver) {
        observers.add(observer)
    }


    func removeObserver(_ observer: CallObserver) {
        observers.remove(observer)
    }


    func removeAllObservers() {
        observers.removeAll()
    }


    /// Events are delivered in order on `SDKQueues.events`.
    func notify(_ event: CallEvent) {
        observers.notify(event)
    }


    // MARK: - Async API Task

    func apiTask(setConnecting: Bool = true, _ operation: @escaping @Sendable () async throws -> Void) {
        if setConnecting { updateState(.connecting) }
        let task = Task {
            do {
                try await operation()
            } catch {
                logger.error("apiTask: error – \(error)")
                try? self.disconnect()
            }
        }
        apiConfigTask.write { $0 = task }
    }


    // MARK: - Helpers

    /// Reports the current local mute/local-video-pause/hold state to the remote party via
    /// SIP INFO. Best-effort and non-throwing — a failure here must not affect the call.
    func sendMediaStateInfo() {
        guard case .ongoing = state, sipId >= 0 else { return }
        do {
            try delegate?.sendMediaStateInfo(withID: sipId, audioMuted: isMuted, videoMuted: isLocalVideoPaused, hold: isOnHold)
        } catch {
            logger.error("sendMediaStateInfo: \(error)")
        }
    }


    func cancelTask() {
        let task = apiConfigTask.write { task -> Task<Void, Never>? in
            defer { task = nil }
            return task
        }
        task?.cancel()
    }


    private func internalDisconnect(_ callEndReason: CallEndReason, cancelTask: Bool = false) throws {
        SDKQueues.assertOnSip()
        if case .disconnected = state {
            let message = "already disconnected"
            logger.warning("unavailable, \(message)")
            throw CallError.invalidState(message: message)
        }

        incomingTimeout?.cancel()
        incomingTimeout = nil

        if sipId < 0 {
            if cancelTask {
                self.cancelTask()
            }
            try delegate?.disconnectCall(.local(uuid: id))
            updateState(CallState.disconnected(callEndReason))

        } else {
            try delegate?.disconnectCall(.sip(id: sipId))
        }
    }
}
