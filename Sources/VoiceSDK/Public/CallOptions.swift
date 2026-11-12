//
//  CallOptions.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.06.2025.
//

import Foundation


/// Media type used when placing a call.
public enum CallType: Equatable, Sendable {
    case audio
    case video
}


/// Options controlling how a call is placed.
public struct CallOptions {

    /// Media type of the call. Defaults to `.audio`.
    public var type: CallType

    /// SIP destination (extension/user part of the request URI).
    public var toNumber: String

    /// Optional display name for the destination.
    public var toName: String?

    /// Identifier of the meeting/conversation this call belongs to.
    ///
    /// When set, the call becomes eligible for a post-call satisfaction
    /// rating via `Call.isRatable()` / `Call.rate(_:)`. When `nil` (default),
    /// the call is never ratable and no rating-related network request is
    /// ever made for it.
    public var meetingId: String?

    /// Physical orientation of the device at the moment the call is placed, used to
    /// orient the very first outgoing video frame — before any mid-call rotation
    /// notification could otherwise reach `Call.setVideoOrientation(_:)`. Maps
    /// `UIDevice.current.orientation` the same way `Call.setVideoOrientation` does.
    /// Ignored for audio-only calls.
    public var videoOrientation: VideoOrientation

    /// Arbitrary key-value data attached to the outgoing call and delivered to the
    /// server in the SIP INVITE (a single `X-Webitel-Metadata` header with compact JSON,
    /// e.g. `{"lang":"uk","orderId":"12345"}`).
    ///
    /// Intended for small identifiers (order id, language, source screen) — NOT for
    /// payloads: the whole INVITE (including SDP) must fit the transport, and on UDP a
    /// large INVITE gets fragmented or dropped. The encoded JSON is limited to
    /// `CallOptions.maxMetadataBytes`; if the limit is exceeded the metadata is NOT
    /// sent (the call still proceeds) and a warning is logged. Empty keys are ignored.
    /// Defaults to empty (no header is sent).
    public var metadata: [String: String]

    /// Maximum size, in bytes, of `metadata` encoded as JSON.
    public static let maxMetadataBytes = 1024

    public init(
        type: CallType = .audio,
        toNumber: String = "service",
        toName: String? = nil,
        meetingId: String? = nil,
        videoOrientation: VideoOrientation = .portrait,
        metadata: [String: String] = [:]
    ) {
        self.type = type
        self.toNumber = toNumber
        self.toName = toName
        self.meetingId = meetingId
        self.videoOrientation = videoOrientation
        self.metadata = metadata
    }
}
