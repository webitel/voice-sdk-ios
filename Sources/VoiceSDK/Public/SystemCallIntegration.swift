//
//  SystemCallIntegration.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 23.10.2026.
//

import Foundation


/// How calls are integrated with the system call UI (CallKit).
public enum SystemCallIntegration {
    /// No CallKit. The SDK activates the audio session itself and handles audio
    /// interruptions (e.g. a cellular call). Suitable for outgoing-only apps or
    /// regions where CallKit is unavailable. Incoming call pushes can't be used:
    /// iOS terminates apps that don't report a VoIP push to CallKit.
    case none

    /// The app owns `CXProvider`. It must report calls to CallKit, map provider
    /// actions to `Call` methods, and forward `provider(_:didActivate:)` /
    /// `provider(_:didDeactivate:)` to `VoiceClient.audioSessionDidActivate()` /
    /// `VoiceClient.audioSessionDidDeactivate()` — call audio starts only after activation.
    case hostManaged

    /// The SDK creates and manages `CXProvider`: reports incoming and outgoing calls,
    /// handles system UI actions and routes `Call` methods through CallKit, so the
    /// system UI always reflects the call state. Only one client per process can use it.
    case sdkManaged(SystemCallConfiguration)
}


extension SystemCallIntegration {
    var usesCallKit: Bool {
        if case .none = self { return false }
        return true
    }
}


/// Appearance of SDK-managed calls in the system call UI.
public struct SystemCallConfiguration {
    /// Name shown in the system call UI. Used only on iOS 13 — since iOS 14 the
    /// system shows the app's display name. Defaults to the bundle display name.
    public var displayName: String?

    /// PNG data of a 40×40 pt template image shown in the system call UI.
    public var iconTemplateImageData: Data?

    /// Name of a sound file in the main bundle used as the ringtone.
    /// Defaults to the system ringtone.
    public var ringtoneSound: String?

    /// Whether calls appear in the system Recents list.
    ///
    /// Default: `true`
    public var includesCallsInRecents: Bool

    /// Whether the system call UI treats calls as video-capable: shows the Video
    /// button (it only opens the app — CallKit never renders video) and marks video
    /// calls as such in the incoming call UI and Recents. Applies to all calls.
    ///
    /// Default: `false`
    public var supportsVideo: Bool


    public init(
        displayName: String? = nil,
        iconTemplateImageData: Data? = nil,
        ringtoneSound: String? = nil,
        includesCallsInRecents: Bool = true,
        supportsVideo: Bool = false
    ) {
        self.displayName = displayName
        self.iconTemplateImageData = iconTemplateImageData
        self.ringtoneSound = ringtoneSound
        self.includesCallsInRecents = includesCallsInRecents
        self.supportsVideo = supportsVideo
    }
}
