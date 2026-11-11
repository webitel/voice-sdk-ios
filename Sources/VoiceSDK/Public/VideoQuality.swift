//
//  VideoQuality.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 10.11.2026.
//

import Foundation


/// Video encoding preset, set for all calls of a client via `CallSettings.videoQuality`.
///
/// The codec parameters are shared by every call of the process, so the quality is a
/// client setting, not a per-call one. A change made through `VoiceClient.configure(_:)`
/// applies to video calls started afterwards.
///
/// Video is encoded at 9:16 in portrait and 16:9 in landscape (see `VideoOrientation`,
/// taken from `CallOptions.videoOrientation` when the call is placed). The SDK does not
/// adapt the quality to network conditions during a call.
public enum VideoQuality: String, Codable, Sendable, CaseIterable {

    /// 360p at 15 fps, ~250 kbps — for weak mobile networks.
    case low

    /// 360p at 24 fps, ~500 kbps — the default; fits most mobile networks.
    case medium

    /// 720p at 30 fps, ~1.5 Mbps — for Wi-Fi or a strong network. The maximum supported.
    case high


    /// The default preset: `.medium`.
    public static let `default`: VideoQuality = .medium


    /// Short side of the frame in pixels: the "p" in 360p / 720p.
    var shortSide: UInt32 {
        switch self {
        case .low, .medium: return 360
        case .high: return 720
        }
    }

    /// Long side of the frame in pixels (16:9).
    var longSide: UInt32 { shortSide * 16 / 9 }

    var fps: Int32 {
        switch self {
        case .low: return 15
        case .medium: return 24
        case .high: return 30
        }
    }

    /// Average bitrate, bits per second.
    var avgBitrate: UInt32 {
        switch self {
        case .low: return 250_000
        case .medium: return 500_000
        case .high: return 1_500_000
        }
    }

    /// Maximum bitrate, bits per second.
    var maxBitrate: UInt32 {
        switch self {
        case .low: return 400_000
        case .medium: return 800_000
        case .high: return 2_000_000
        }
    }


    /// Side of the square decoder buffer. Must fit any remote resolution in either
    /// orientation, independent of the local preset — H.264 level 3.1 (`42e01f`, which
    /// the SDK advertises) allows at most 1280×720.
    static let maxDecodeDimension: UInt32 = 1280
}
