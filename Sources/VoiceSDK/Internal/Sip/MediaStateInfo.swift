//
//  MediaStateInfo.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 28.07.2026.
//

import Foundation


/// Wire format for the local mute/local-video-pause/hold state exchanged over a SIP INFO
/// packet — kept byte-compatible with the Android SDK so an Android↔iOS call can read
/// each other's state: `Content-Type: application/json`, body
/// `{"audioMuted":Bool,"videoMuted":Bool,"hold":Bool}`. Each field is optional on receive —
/// a field absent from the JSON means "unchanged", not "false".
enum MediaStateInfo {
    static let contentType = "application/json"

    private enum Field {
        static let audioMuted = "audioMuted"
        static let videoMuted = "videoMuted"
        static let hold = "hold"
    }


    static func encode(audioMuted: Bool, videoMuted: Bool, hold: Bool) -> String {
        let json: [String: Bool] = [
            Field.audioMuted: audioMuted,
            Field.videoMuted: videoMuted,
            Field.hold: hold
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }


    /// Parses a raw SIP message ("wholeMsg" — the full request/response, headers and body
    /// together) the same way the Android SDK's `PJCall.parseMediaStateInfo` does:
    /// distinguishes a genuine incoming INFO request from the 200 OK response to our own
    /// outgoing INFO (a response's first line starts with "SIP/2.0", a request's doesn't),
    /// checks the raw message contains "application/json" (case-insensitive), splits at the
    /// first "\r\n\r\n" (fallback "\n\n"), and JSON-decodes the body. Returns `nil` if this
    /// isn't an incoming INFO request with a JSON body.
    static func parse(fromWholeMessage wholeMsg: String) -> (audioMuted: Bool?, videoMuted: Bool?, hold: Bool?)? {
        // `\r\n` is a single Character (grapheme cluster) in Swift — not two — so
        // `firstIndex(of: "\n")` never matches a CRLF-terminated line and must not be used here.
        guard let firstLineEnd = (wholeMsg.range(of: "\r\n") ?? wholeMsg.range(of: "\n"))?.lowerBound else { return nil }
        let firstLine = wholeMsg[wholeMsg.startIndex..<firstLineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !firstLine.hasPrefix("SIP/2.0") else { return nil }

        guard wholeMsg.range(of: contentType, options: .caseInsensitive) != nil else { return nil }

        // `range.upperBound` already points right after the matched separator, regardless
        // of how many Characters/bytes it spans — no manual length bookkeeping needed (see
        // the `\r\n` note above for why byte-counted `dropFirst` is unsafe here).
        guard let separatorRange = wholeMsg.range(of: "\r\n\r\n") ?? wholeMsg.range(of: "\n\n") else { return nil }
        let body = wholeMsg[separatorRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let data = body.data(using: .utf8) else { return nil }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        return (
            audioMuted: json[Field.audioMuted] as? Bool,
            videoMuted: json[Field.videoMuted] as? Bool,
            hold: json[Field.hold] as? Bool
        )
    }
}
