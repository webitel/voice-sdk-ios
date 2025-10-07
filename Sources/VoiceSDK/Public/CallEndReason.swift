//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// Represents the reason why a call ended, including
/// the SIP response code, its type, and a message.
public struct CallEndReason: Equatable {
    /// The SIP response code (e.g., 200, 486, 403).
    public let code: Int
    
    /// The mapped reason type, derived from the SIP response code.
    public let type: ReasonType
    
    /// A descriptive message explaining the end reason.
    public let message: String

    /// Enumerates the possible standardized reasons for call termination.
    public enum ReasonType: String {
        /// The call ended normally (200 OK).
        case ok
        /// The callee is busy (486/600).
        case busy
        /// The callee is temporarily unavailable (480).
        case unavailable
        /// The callee declined the call (603).
        case declined
        /// The call was rejected (608).
        case rejected
        /// The call was marked as unwanted or spam (607).
        case unwanted
        /// Access was forbidden (403).
        case forbidden
        /// Proxy authentication is required (407).
        case proxyAuthRequired
        /// The requested user could not be found (404).
        case notFound
        /// The method used is not allowed (405).
        case methodNotAllowed
        /// The call parameters are not acceptable here (488).
        case notAcceptableHere
        /// The request timed out (408).
        case requestTimeout
        /// The request was terminated (487).
        case requestTerminated
        /// The call transaction does not exist (481).
        case callDoesNotExist
        /// A request is already pending (491).
        case requestPending
        /// The service is temporarily unavailable (503).
        case serviceUnavailable
        /// An internal server error occurred (500).
        case internalServerError
        /// The request was malformed (400).
        case badRequest
        /// The requested feature is not implemented (501).
        case notImplemented
        /// The server did not respond in time (504).
        case serverTimeout
        /// A bad gateway response was received (502).
        case badGateway
        /// The request was canceled before completion (0).
        case requestCancelled
        /// The request was unauthorized (401).
        case unauthorized
        /// The reason for ending the call is unknown.
        case unknown
    }
}

extension CallEndReason {
    /// Creates a `CallEndReason` from a SIP response code.
    ///
    /// - Parameters:
    ///   - code: The SIP response code.
    ///   - messageOverride: An optional custom message to replace the default.
    /// - Returns: A `CallEndReason` with type and message mapped from the code.
    static func from(code: Int, _ messageOverride: String? = nil) -> CallEndReason {
        let (type, defaultMessage): (ReasonType, String) = {
            switch code {
            case 200: return (.ok, "Call completed successfully")
            case 486: return (.busy, "User is busy")
            case 600: return (.busy, "Busy everywhere")
            case 480: return (.unavailable, "User is temporarily unavailable")
            case 603: return (.declined, "Call was declined")
            case 608: return (.rejected, "Call was rejected")
            case 607: return (.unwanted, "Call was marked as unwanted")
            case 403: return (.forbidden, "Forbidden")
            case 407: return (.proxyAuthRequired, "Proxy authentication required")
            case 404: return (.notFound, "User not found")
            case 405: return (.methodNotAllowed, "Method not allowed")
            case 488: return (.notAcceptableHere, "Not acceptable here")
            case 408: return (.requestTimeout, "Request timeout")
            case 487: return (.requestTerminated, "Request was terminated")
            case 481: return (.callDoesNotExist, "Call transaction does not exist")
            case 491: return (.requestPending, "Request pending")
            case 503: return (.serviceUnavailable, "Service unavailable")
            case 500: return (.internalServerError, "Internal server error")
            case 400: return (.badRequest, "Bad request")
            case 501: return (.notImplemented, "Not implemented")
            case 504: return (.serverTimeout, "Server timeout")
            case 502: return (.badGateway, "Bad gateway")
            case 0:   return (.requestCancelled, "Call cancelled before response")
            case 401: return (.unauthorized, "Unauthorized")
            default:  return (.unknown, "Unmapped SIP status: \(code)")
            }
        }()
        
        return CallEndReason(
            code: code,
            type: type,
            message: messageOverride?.isEmpty == false ? messageOverride! : defaultMessage
        )
    }
}

extension CallEndReason.ReasonType {
    /// Maps the reason type into a broader `CallEndCategory`.
    var category: CallEndCategory {
        switch self {
        case .ok: return .normal
        case .busy: return .busy
        case .unavailable: return .unavailable
        case .declined, .rejected, .unwanted: return .normal
        case .unauthorized, .forbidden, .proxyAuthRequired,
             .methodNotAllowed, .notAcceptableHere, .requestPending,
             .serviceUnavailable, .internalServerError, .badRequest,
             .notImplemented, .serverTimeout, .badGateway:
            return .error
        case .notFound: return .canceled
        case .requestTimeout, .requestTerminated,
             .callDoesNotExist, .requestCancelled:
            return .canceled
        case .unknown: return .unknown
        }
    }
}

extension CallEndReason {
    /// Convenience accessor for the broader `CallEndCategory`
    /// derived from the specific reason type.
    var category: CallEndCategory { type.category }
}
