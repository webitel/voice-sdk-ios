//
//  IncomingCallPush.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// Incoming call data carried by a VoIP push notification.
///
/// Expected payload format:
/// ```json
/// { "aps": { "call_id": "<uuid>", "from_number": "...", "from_name": "..." } }
/// ```
public struct IncomingCallPush {
    /// Server-side call identifier. Becomes the `Call.id` of the incoming call
    /// and is matched against the `X-Webitel-Uuid` header of the SIP INVITE.
    public let callId: UUID

    /// Caller phone number.
    public let fromNumber: String

    /// Caller display name. Falls back to `fromNumber` when absent.
    public let fromName: String


    public init(callId: UUID, fromNumber: String, fromName: String) {
        self.callId = callId
        self.fromNumber = fromNumber
        self.fromName = fromName
    }


    /// Parses a PushKit payload (`PKPushPayload.dictionaryPayload`).
    ///
    /// Returns `nil` if the payload has no `aps` dictionary or `aps.call_id`
    /// is not a valid UUID.
    public init?(payload: [AnyHashable: Any]) {
        guard let aps = payload["aps"] as? [String: Any],
              let rawCallId = aps["call_id"] as? String,
              let callId = UUID(uuidString: rawCallId) else {
            return nil
        }

        let number = (aps["from_number"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
        let name = (aps["from_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? number

        self.init(callId: callId, fromNumber: number, fromName: name)
    }
}
