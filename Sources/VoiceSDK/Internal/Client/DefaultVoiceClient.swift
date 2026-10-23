//
//  DefaultVoiceClient.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 20.06.2025.
//
import Foundation


final class DefaultVoiceClient: VoiceClient {

    private let authManager: AuthManager
    private let pushService: PushService
    private let ratingService: RatingService
    private let context: ClientContext
    private let voiceManager: VoiceManager = VoiceManager.shared
    
    private let logger = SDKLogger.make("voice.core.client")

    var activeCall: Call? {
        voiceManager.activeCall
    }

    var calls: [Call] {
        voiceManager.calls
    }
    

    init(
        context: ClientContext,
        authManager: AuthManager,
        pushService: PushService,
        ratingService: RatingService
    ) {
        self.authManager = authManager
        self.pushService = pushService
        self.ratingService = ratingService
        self.context = context

        configure(context.callSettings)
    }


    func configure(_ settings: CallSettings) {
        voiceManager.updateCallSettings(settings)
    }

    
    // MARK: - Call

    func makeCall(options: CallOptions, observer: any CallObserver) -> any Call {
        let hasVideo = options.type == .video
        let (call, outcome) = voiceManager.insertCall(
            // A repeated `makeCall` (e.g. double tap) returns the call already being placed.
            existing: { $0.callsByUUID.values.first { $0.isOutgoing } },
            // Only incoming calls can wait: no outgoing call while another call exists.
            reject: { !$0.callsByUUID.isEmpty }
        ) {
            CallImpl(
                delegate: voiceManager,
                ratingProvider: ratingService,
                remoteName: options.toName,
                remoteNumber: options.toNumber,
                meetingId: options.meetingId,
                hasVideo: hasVideo,
                initialOrientation: options.videoOrientation
            )
        }
        call.addObserver(observer)

        switch outcome {
            case .inserted: break
            case .existing:
                logger.warning("Outgoing call already exists in state: \(call.state)")
                return call
            case .rejected:
                logger.warning("Can't make a call while another call is in progress")
                call.disconnectWithReason(callEndReason: .from(code: -1, "Another call is in progress"))
                return call
        }

        logger.debug("Making new \(hasVideo ? "video" : "audio") call")

        call.apiTask {
            do {
                var config = try await self.authManager.getSipConfig(meetingId: options.meetingId)
                if hasVideo {
                    config.enableVideoCall()
                }
                self.logger.debug("Calling service...")
                try await self.voiceManager.makeCallFor(call.id, config, options: options)
            } catch {
                self.handleCallFailure(call, error)
            }
        }

        return call
    }


    // MARK: - Incoming Call

    func handleIncomingPush(_ push: IncomingCallPush, observer: any CallObserver) -> any Call {
        let (call, outcome) = voiceManager.insertCall(
            existing: { $0.callsByUUID[push.callId] },
            reject: { $0.callsByUUID.count >= VoiceManager.maxCalls }
        ) {
            // Created already `.ringing`, so `answer()` is valid as soon as this returns.
            CallImpl(
                delegate: voiceManager,
                ratingProvider: ratingService,
                id: push.callId,
                isOutgoing: false,
                remoteName: push.fromName,
                remoteNumber: push.fromNumber,
                initialState: .ringing
            )
        }
        call.addObserver(observer)

        switch outcome {
            case .inserted: break
            case .existing:
                logger.warning("Incoming call \(push.callId) already exists in state: \(call.state)")
                return call
            case .rejected:
                // Still returned so the app can report it to CallKit, as PushKit requires.
                // The push isn't confirmed, so the server stops ringing on its own timeout.
                logger.warning("Incoming call \(push.callId) rejected: too many calls in progress")
                call.disconnectWithReason(callEndReason: .from(code: 486, "Too many calls in progress"))
                return call
        }

        logger.debug("Incoming call push: \(push.callId) from \(push.fromNumber)")
        call.updateState(.ringing)
        call.startIncomingTimeout(context.incomingCallTimeout)

        call.apiTask(setConnecting: false) {
            do {
                let config = try await self.authManager.getSipConfig(meetingId: nil)
                try Task.checkCancellation()
                try await self.voiceManager.registerForIncoming(config)
                try Task.checkCancellation()
                self.logger.debug("SIP registered, confirming push for call \(call.id)")
                try await self.pushService.confirmPush(callId: call.id)
            } catch is CancellationError {
                self.logger.debug("Incoming call \(call.id) setup cancelled")
            } catch {
                self.handleCallFailure(call, error)
            }
        }

        return call
    }


    func registerPushToken(_ token: Data) async throws {
        try await pushService.registerPushToken(token)
    }


    // MARK: - Shutdown

    func shutdown(onComplete: @escaping () -> Void) {
        voiceManager.shutdown(onComplete)
    }

    
    private func handleCallFailure(_ call: CallImpl, _ error: Error) {
        logger.error("Call setup failed: \(error)")

        let reason: CallEndReason

        if let err = error as? CallError {
            switch err {
            case .unauthorized(let message):
                reason = .from(code: 401, message)
            case .invalidResponse(let message),
                 .invalidState(let message),
                 .invalidURL(let message),
                 .sipError(let message):
                reason = .from(code: -1, message)
            case .registrationFailed(let code, let message):
                reason = .from(code: code, message)
            case .unknown(let message, let code):
                reason = .from(code: code, message)
            }
        } else {
            reason = .from(code: -1, error.localizedDescription)
        }

        call.disconnectWithReason(callEndReason: reason)
    }
}
