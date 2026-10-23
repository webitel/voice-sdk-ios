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

        let context = ClientContext(
            baseURL: normalizedBaseURL,
            clientToken: config.clientToken ?? "",
            authMethod: authMethod,
            callSettings: CallSettings(),
            deviceId: config.deviceId ?? deviceStorage.getDeviceId(),
            agent: systemDetails.userAgent,
            pinnedHashes: config.pinnedPublicKeys,
            incomingCallTimeout: config.incomingCallTimeout
        )

        SDKLogger.configure(
            level: config.logLevel, handlerFactory: config.logHandler
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
            ratingService: RatingService(api: MeetingAPI(http: http))
        )
        return client as any VoiceClient
    }

    private static func normalizingScheme(of url: URL) -> URL {
        guard url.scheme == nil else { return url }
        return URL(string: "https://\(url.absoluteString)") ?? url
    }
}

