//
//  VoiceClientFactory.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 09.07.2026.
//

import Foundation


public enum VoiceClientFactory {
    
    public static func create(
        baseURL: URL,
        authMethod: AuthMethod,
        configure: (inout VoiceClientConfiguration) -> Void = { _ in }
    ) -> any VoiceClient {

        var config = VoiceClientConfiguration()
        configure(&config)
        let systemDetails = SystemDetails()
        let deviceStorage: DeviceStorage = DeviceStorage()
        let normalizedBaseURL = normalizingScheme(of: baseURL)

        SDKLogger.configure(
            level: config.logLevel, handlerFactory: config.logHandler
        )

        var systemCallIntegration = config.systemCallIntegration
        var callKit: CallKitCoordinator?
        if case .sdkManaged(let callKitConfiguration) = systemCallIntegration {
            callKit = CallKitCoordinator.make(configuration: callKitConfiguration, voiceManager: .shared)
            if callKit == nil {
                SDKLogger.make("VoiceSDK")
                    .error("CallKit is already managed by another VoiceClient, falling back to SystemCallIntegration.none")
                systemCallIntegration = .none
            }
        }
        if systemCallIntegration.usesCallKit && !CallKitCoordinator.hasVoIPBackgroundMode {
            SDKLogger.make("VoiceSDK")
                .error("""
                    CallKit requires the "voip" background mode: enable Background Modes → Voice over IP \
                    (and Audio) in Signing & Capabilities. Calls will be refused by the system.
                    """)
        }

        let context = ClientContext(
            baseURL: normalizedBaseURL,
            clientToken: config.clientToken ?? "",
            authMethod: authMethod,
            callSettings: config.callSettings,
            deviceId: config.deviceId ?? deviceStorage.getDeviceId(),
            agent: systemDetails.userAgent,
            pinnedHashes: config.pinnedPublicKeys,
            incomingCallTimeout: config.incomingCallTimeout,
            systemCallIntegration: systemCallIntegration
        )

        if baseURL.scheme == nil {
            SDKLogger.make("VoiceSDK")
                .debug("baseURL has no scheme, defaulted to https: \(normalizedBaseURL.absoluteString)")
        }

        SDKLogger.make("VoiceSDK")
            .debug("created VoiceSDK with context: \(context)")

        let http = HTTPClient(context: context)
        let authManager = AuthManager(context: context, api: TokenAPI(http: http))

        let client = DefaultVoiceClient(
            context: context,
            authManager: authManager,
            pushService: PushService(authManager: authManager, api: PushAPI(http: http)),
            ratingService: RatingService(api: MeetingAPI(http: http)),
            callKit: callKit
        )
        return client as any VoiceClient
    }

    private static func normalizingScheme(of url: URL) -> URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }
}

