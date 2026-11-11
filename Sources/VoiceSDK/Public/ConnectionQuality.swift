//
//  ConnectionQuality.swift
//  VoiceSDK
//

import Foundation


/// How well media is delivered between this device and the Webitel media server during an
/// ongoing call, estimated every few seconds from RTCP statistics of the audio stream
/// (packet loss in both directions and round-trip time).
///
/// It describes **your** connection to the server only. Media is relayed by the server, so
/// the other party's network is measured on their own leg and is mostly invisible here: when
/// they have a weak connection you may hear gaps while this still reports `.good`. The one
/// exception is a complete loss of incoming media, which is reported as `.bad`.
///
/// Read it from `Call.connectionQuality`; changes are reported with
/// `ConnectionEvent.qualityChanged`. Use it to warn the user about a weak connection or to
/// suggest turning video off — the SDK does not change the video quality by itself.
///
/// Levels from best to worst: `.good`, `.medium`, `.bad`.
public enum ConnectionQuality: Equatable {

    /// Not measured yet, the call is on hold, or the call is not ongoing.
    case unknown

    /// Packet loss below 3% and round-trip time below 300 ms.
    case good

    /// Noticeable loss or delay: audio may stutter, video may freeze briefly.
    case medium

    /// Packet loss above 10%, round-trip time above 700 ms, or no media received from the
    /// server: the call is barely usable.
    case bad
}
