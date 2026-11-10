//
//  CallKitCoordinator.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 23.10.2026.
//

import Foundation
import CallKit
import AVFAudio


/// SDK-managed CallKit integration (`SystemCallIntegration.sdkManaged`).
///
/// Built on the same seams the app gets with `.hostManaged` (`Call` methods, `CallObserver`
/// events, audio session activation), plus two internal ones, marked `// internal:` —
/// routing `Call` actions through `CXCallController` and starting SIP only once CallKit
/// performs `CXStartCallAction`.
///
/// `CXProvider` and `CXCallController` deliver on `SDKQueues.sip`, so delegate methods run
/// where `CallImpl.performAction(_:)` must be called. `entries` is readable from any thread.
final class CallKitCoordinator: NSObject {

    private struct Entry {
        let isOutgoing: Bool
        /// `reportNewIncomingCall` hasn't completed yet.
        var isReporting = false
        /// CallKit knows about the call: its report or start request succeeded.
        var isKnown = false
        var reportedConnecting = false
        /// Ended through `CXEndCallAction`, so CallKit already knows it ended.
        var isEndedByAction = false
        /// SIP setup of an outgoing call, run once CallKit performs `CXStartCallAction`.
        var start: (() -> Void)?
    }

    /// Apple expects a single `CXProvider` per app, and `VoiceManager` is shared anyway.
    private static let isProviderCreated = Protected(false)

    private let logger = SDKLogger.make("voice.core.callkit")
    private let provider: CXProvider
    private let callController = CXCallController(queue: SDKQueues.sip)
    private let voiceManager: VoiceManager
    private let entries = Protected([UUID: Entry]())


    /// Returns `nil` if another client already manages CallKit in this process.
    static func make(configuration: SystemCallConfiguration, voiceManager: VoiceManager) -> CallKitCoordinator? {
        let isFirst = isProviderCreated.write { created -> Bool in
            defer { created = true }
            return !created
        }
        guard isFirst else { return nil }
        return CallKitCoordinator(configuration: configuration, voiceManager: voiceManager)
    }


    private init(configuration: SystemCallConfiguration, voiceManager: VoiceManager) {
        self.provider = CXProvider(configuration: Self.makeProviderConfiguration(configuration))
        self.voiceManager = voiceManager
        super.init()
        provider.setDelegate(self, queue: SDKQueues.sip)
    }


    deinit {
        provider.invalidate()
        Self.isProviderCreated.write { $0 = false }
    }


    // MARK: - Calls

    /// Must be called before `handleIncomingPush` returns: PushKit requires every VoIP
    /// push to be reported to CallKit right away. A call the SDK already rejected is
    /// reported too, and ended as soon as CallKit has registered it.
    func reportIncoming(_ call: CallImpl) {
        call.addObserver(self)
        entries.write { $0[call.id] = Entry(isOutgoing: false, isReporting: true) }
        configureAudioSession(video: call.hasVideo)

        provider.reportNewIncomingCall(with: call.id, update: makeUpdate(for: call)) { [weak self] error in
            SDKQueues.sip.async { self?.didReportIncoming(call, error: error) }
        }
    }


    private func didReportIncoming(_ call: CallImpl, error: Error?) {
        if let error {
            // E.g. Do Not Disturb or a blocked number: the call must not ring on its own.
            logger.error("Incoming call \(call.id): \(Self.describe(error))")
            entries.write { $0.removeValue(forKey: call.id) }
            do {
                try call.performAction(.end)
            } catch {
                logger.debug("didReportIncoming: \(call.id) already ended")
            }
            return
        }

        entries.write {
            $0[call.id]?.isReporting = false
            $0[call.id]?.isKnown = true
        }
        // Ended while CallKit was still registering it; see `onStateChanged`.
        if case .disconnected(let reason) = call.state {
            onEnded(call.id, reason: reason)
        }
    }


    // internal: SIP setup starts only once CallKit allows the call — it may refuse it,
    // e.g. during a cellular call — so `makeCall` hands it over instead of running it.
    func startOutgoing(_ call: CallImpl, options: CallOptions, start: @escaping () -> Void) {
        call.addObserver(self)
        entries.write { $0[call.id] = Entry(isOutgoing: true, start: start) }

        let action = CXStartCallAction(call: call.id, handle: CXHandle(type: .generic, value: options.toNumber))
        action.isVideo = options.type == .video
        action.contactIdentifier = options.toName

        callController.request(CXTransaction(action: action)) { [weak self] error in
            guard let self, let error else { return }
            let message = Self.describe(error)
            self.logger.error("Outgoing call \(call.id): \(message)")
            self.entries.write { $0.removeValue(forKey: call.id) }
            call.disconnectWithReason(callEndReason: .from(code: -1, message))
        }
    }


    /// Ends every call CallKit still shows; SIP is being torn down without per-call events.
    func endAllCalls() {
        let known = entries.write { entries -> [UUID] in
            defer { entries.removeAll() }
            return entries.filter { $0.value.isKnown }.map(\.key)
        }
        for id in known {
            provider.reportCall(with: id, endedAt: nil, reason: .failed)
        }
    }


    // MARK: - Reports

    private func onStateChanged(_ id: UUID, state: CallState) {
        SDKQueues.assertOnSip()
        switch state {
            case .connecting:
                let shouldReport = entries.write { entries -> Bool in
                    guard let entry = entries[id], entry.isOutgoing, entry.isKnown, !entry.reportedConnecting else { return false }
                    entries[id]?.reportedConnecting = true
                    return true
                }
                if shouldReport { provider.reportOutgoingCall(with: id, startedConnectingAt: nil) }

            case .ongoing:
                let isOutgoing = entries.read { $0[id]?.isOutgoing == true && $0[id]?.isKnown == true }
                if isOutgoing { provider.reportOutgoingCall(with: id, connectedAt: nil) }

            case .disconnected(let reason):
                // Still being reported: `didReportIncoming` ends it once CallKit knows it.
                guard entries.read({ $0[id]?.isReporting }) != true else { return }
                onEnded(id, reason: reason)

            case .idle, .ringing:
                break
        }
    }


    private func onEnded(_ id: UUID, reason: CallEndReason) {
        guard let entry = entries.write({ $0.removeValue(forKey: id) }),
              entry.isKnown, !entry.isEndedByAction else { return }
        provider.reportCall(with: id, endedAt: nil, reason: Self.endedReason(for: reason))
    }


    // MARK: - Helpers

    private func call(_ id: UUID) -> CallImpl? {
        voiceManager.registry.find(byUUID: id)
    }


    private func makeUpdate(for call: CallImpl) -> CXCallUpdate {
        let update = CXCallUpdate()
        if let number = call.remoteNumber {
            update.remoteHandle = CXHandle(type: .generic, value: number)
        }
        update.localizedCallerName = call.remoteName
        update.hasVideo = call.hasVideo
        update.supportsHolding = true
        update.supportsDTMF = true
        update.supportsGrouping = false
        update.supportsUngrouping = false
        return update
    }


    /// CallKit activates the session itself, but its category must be set beforehand.
    /// Skipped when already configured: `setCategory` resets the output route, which would
    /// turn off the speaker of an ongoing call when a second call starts or is answered.
    private func configureAudioSession(video: Bool) {
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode = video ? .videoChat : .voiceChat
        let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP]
        guard session.category != .playAndRecord || session.mode != mode || session.categoryOptions != options else {
            return
        }
        do {
            try session.setCategory(.playAndRecord, mode: mode, options: options)
        } catch {
            logger.error("configureAudioSession: \(error)")
        }
    }


    /// Runs a CallKit-requested action on its call, fulfilling or failing it.
    private func perform(_ action: CallAction, for cxAction: CXCallAction) {
        guard let call = call(cxAction.callUUID) else {
            logger.warning("\(action): call \(cxAction.callUUID) not found")
            cxAction.fail()
            return
        }
        do {
            try call.performAction(action)
            cxAction.fulfill()
        } catch {
            logger.error("\(action): \(error)")
            cxAction.fail()
        }
    }


    /// The app can't use CallKit without it: every request fails with `.unentitled`.
    static var hasVoIPBackgroundMode: Bool {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String]
        return modes?.contains("voip") == true
    }


    /// Readable reason for a CallKit refusal — its own messages are bare error codes.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.domain {
            case CXErrorCodeRequestTransactionError.errorDomain:
                switch CXErrorCodeRequestTransactionError.Code(rawValue: nsError.code) {
                    case .unentitled:
                        return "CallKit refused the call: the app lacks the \"voip\" background mode, or CallKit is unavailable in this region"
                    case .maximumCallGroupsReached:
                        return "CallKit refused the call: too many calls in progress"
                    case .callUUIDAlreadyExists:
                        return "CallKit refused the call: a call with this id already exists"
                    case .unknownCallUUID:
                        return "CallKit refused the action: the call is unknown to CallKit"
                    default:
                        break
                }

            case CXErrorCodeIncomingCallError.errorDomain:
                switch CXErrorCodeIncomingCallError.Code(rawValue: nsError.code) {
                    case .unentitled:
                        return "CallKit refused the call: the app lacks the \"voip\" background mode, or CallKit is unavailable in this region"
                    case .filteredByDoNotDisturb:
                        return "CallKit refused the call: filtered by Do Not Disturb"
                    case .filteredByBlockList:
                        return "CallKit refused the call: the caller is blocked"
                    case .callUUIDAlreadyExists:
                        return "CallKit refused the call: a call with this id already exists"
                    default:
                        break
                }

            default:
                break
        }
        return "CallKit refused the request: \(error.localizedDescription)"
    }


    static func endedReason(for reason: CallEndReason) -> CXCallEndedReason {
        switch reason.category {
            case .error, .unknown: return .failed
            case .canceled where reason.type == .requestTimeout: return .unanswered
            case .normal, .busy, .unavailable, .canceled: return .remoteEnded
        }
    }


    private static func makeProviderConfiguration(_ configuration: SystemCallConfiguration) -> CXProviderConfiguration {
        let providerConfiguration: CXProviderConfiguration
        if #available(iOS 14.0, *) {
            providerConfiguration = CXProviderConfiguration()
        } else {
            let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? ""
            providerConfiguration = CXProviderConfiguration(localizedName: configuration.displayName ?? bundleName)
        }
        providerConfiguration.iconTemplateImageData = configuration.iconTemplateImageData
        providerConfiguration.ringtoneSound = configuration.ringtoneSound
        providerConfiguration.includesCallsInRecents = configuration.includesCallsInRecents
        providerConfiguration.supportsVideo = configuration.supportsVideo
        providerConfiguration.maximumCallGroups = VoiceManager.maxCalls
        providerConfiguration.maximumCallsPerCallGroup = 1
        providerConfiguration.supportedHandleTypes = [.generic]
        return providerConfiguration
    }
}


// MARK: - CallActionRouter

extension CallKitCoordinator: CallActionRouter {

    // internal: `Call` methods called by the app go through CallKit, so the system UI
    // always matches the call; CallKit then hands them back via `CXProviderDelegate`.
    func route(_ action: CallAction, for call: CallImpl) -> Bool {
        guard entries.read({ $0[call.id]?.isKnown }) == true else { return false }

        let cxAction: CXCallAction
        switch action {
            case .answer: cxAction = CXAnswerCallAction(call: call.id)
            case .end: cxAction = CXEndCallAction(call: call.id)
            case .mute(let muted): cxAction = CXSetMutedCallAction(call: call.id, muted: muted)
            case .hold(let onHold): cxAction = CXSetHeldCallAction(call: call.id, onHold: onHold)
            case .dtmf(let digits): cxAction = CXPlayDTMFCallAction(call: call.id, digits: digits, type: .singleTone)
        }

        callController.request(CXTransaction(action: cxAction)) { [weak self] error in
            guard let error else { return }
            // CallKit may have lost the call (e.g. after a reset): the action must still work.
            self?.logger.error("\(action) for \(call.id): \(Self.describe(error)), performing directly")
            do {
                try call.performAction(action)
            } catch {
                self?.logger.error("\(action): \(error)")
            }
        }
        return true
    }
}


// MARK: - CallObserver

extension CallKitCoordinator: CallObserver {

    func onEvent(_ event: CallEvent) {
        guard case .connection(.stateChanged(let id, let state)) = event else { return }
        SDKQueues.sip.async { self.onStateChanged(id, state: state) }
    }
}


// MARK: - CXProviderDelegate (on `SDKQueues.sip`)

extension CallKitCoordinator: CXProviderDelegate {

    func providerDidReset(_ provider: CXProvider) {
        logger.warning("CallKit provider reset, ending all calls")
        entries.write { $0.removeAll() }
        for call in voiceManager.calls {
            do {
                try call.performAction(.end)
            } catch {
                logger.error("providerDidReset: \(call.id): \(error)")
            }
        }
    }


    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let call = call(action.callUUID)
        let start = entries.write { entries -> (() -> Void)? in
            guard call != nil, let start = entries[action.callUUID]?.start else {
                entries.removeValue(forKey: action.callUUID)
                return nil
            }
            entries[action.callUUID]?.start = nil
            entries[action.callUUID]?.isKnown = true
            return start
        }
        guard let start, let call else {
            // Disconnected while CallKit was deciding.
            action.fail()
            return
        }

        configureAudioSession(video: action.isVideo)
        start()
        action.fulfill()
        provider.reportCall(with: call.id, updated: makeUpdate(for: call))
    }


    func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        if let call = call(action.callUUID) {
            configureAudioSession(video: call.hasVideo)
        }
        perform(.answer, for: action)
    }


    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        entries.write { $0[action.callUUID]?.isEndedByAction = true }
        guard let call = call(action.callUUID) else {
            action.fulfill()
            return
        }
        do {
            try call.performAction(.end)
        } catch {
            // Already ending — CallKit's goal is reached either way.
            logger.debug("end: \(error)")
        }
        action.fulfill()
    }


    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        perform(.mute(action.isMuted), for: action)
    }


    func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        perform(.hold(action.isOnHold), for: action)
    }


    func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        perform(.dtmf(action.digits), for: action)
    }


    func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        logger.warning("CallKit action timed out: \(action)")
        action.fail()
    }


    func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {
        voiceManager.audioSessionDidActivate()
    }


    func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        voiceManager.audioSessionDidDeactivate()
    }
}
