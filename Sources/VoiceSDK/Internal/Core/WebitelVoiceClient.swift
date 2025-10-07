//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 20.06.2025.
//
import Foundation


final class WebitelVoiceClient: VoiceClient {

    private let authManager: AuthManager
    private let deviceStorage: DeviceStorage = DeviceStorage()
    private let systemDetails: SystemDetails = SystemDetails()
    private let voiceManager: VoiceManager = VoiceManager.shared

    var activeCall: Call? {
        voiceManager.activeCall
    }
    

    init(builder: VoiceClientBuilder) {
        let deviceId = !builder.deviceId.isEmpty
            ? builder.deviceId
            : deviceStorage.getDeviceId()

        WLog.shared.logLevel = builder.logLevel
        let userAgent = systemDetails.getUserAgent()

        self.authManager = AuthManager(
            networkConfiguration: NetworkConfiguration(
                baseUrl: builder.address,
                deviceId: deviceId,
                userAgent: userAgent,
                clientToken: builder.token
            )
        )

        configure(builder.settings ?? CallSettings())

        if let user = builder.user {
            setUser(user)
        }
    }

    
    // MARK: - User / JWT

    func setUser(_ user: User) {
        authManager.setUser(user)
    }

    func setJWT(_ token: String) {
        authManager.setJWT(token)
    }
    

    // MARK: - Call Settings

    func configure(_ settings: CallSettings) {
        voiceManager.updateCallSettings(settings)
    }

    
    // MARK: - Audio Call

    func makeAudioCall(listener: any CallListener) -> any Call {
        return makeCallInternal(jwt: nil, listener: listener)
    }
    

    func makeAudioCall(jwt: String, listener: any CallListener) -> any Call {
        return makeCallInternal(jwt: jwt, listener: listener)
    }
    

    // MARK: - Shutdown

    func shutdown(onComplete: @escaping () -> Void) {
        voiceManager.shutdown(onComplete)
    }

    
    // MARK: - Private
    
    private func makeCallInternal(jwt: String?, listener: any CallListener) -> any Call {
        if let existingCall = activeCall {
            WLog.shared.warning("Active call already exists in state: \(existingCall.state)")
            existingCall.addListener(listener)
            return existingCall
        }

        WLog.shared.debug("Making new call" + (jwt != nil ? " with JWT" : ""))

        let call = WebitelCall(delegate: voiceManager)
        voiceManager.newCall(call)
        call.addListener(listener)

        if let jwt = jwt {
            authManager.setJWT(jwt)
        }

        call.apiTask {
            do {
                let config = try await self.authManager.getSipConfig()
                WLog.shared.debug("Calling service...")
                try self.voiceManager.makeAudioCallFor(call.id, config)
            } catch {
                self.handleCallFailure(call, error)
            }
        }

        return call
    }
    

    private func handleCallFailure(_ call: WebitelCall, _ error: Error) {
        WLog.shared.error("Failed to make call: \(error)")

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
            case .unknown(let message, let code):
                reason = .from(code: code, message)
            }
        } else {
            reason = .from(code: -1, error.localizedDescription)
        }

        call.disconnectWithReason(callEndReason: reason)
    }
}
