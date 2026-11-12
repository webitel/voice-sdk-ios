//
//  CallMetadataEncoder.swift
//  VoiceSDK
//

import Foundation


/// Names of custom SIP headers sent by the SDK.
enum SipHeaders {
    static let metadata = "X-Webitel-Metadata"
}


/// Encodes `CallOptions.metadata` into the value of the `SipHeaders.metadata` header.
///
/// One header with JSON (rather than a header per key) because arbitrary keys are not
/// necessarily valid SIP header tokens, and `JSONEncoder` escapes CR/LF and other
/// control characters, so a value can never break out of the header line.
enum CallMetadataEncoder {

    enum Failure: Error {
        /// Encoded JSON is larger than `CallOptions.maxMetadataBytes`.
        case tooLarge(bytes: Int)
        case encodingFailed(Error)
    }

    /// Returns `nil` when there is nothing to send (empty metadata).
    static func encode(_ metadata: [String: String]) -> Result<String?, Failure> {
        let filtered = metadata.filter { !$0.key.isEmpty }
        guard !filtered.isEmpty else { return .success(nil) }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]

        let data: Data
        do {
            data = try encoder.encode(filtered)
        } catch {
            return .failure(.encodingFailed(error))
        }

        guard data.count <= CallOptions.maxMetadataBytes else {
            return .failure(.tooLarge(bytes: data.count))
        }
        return .success(String(decoding: data, as: UTF8.self))
    }
}
