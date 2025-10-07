//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 26.09.2025.
//

import Foundation


/// Configuration options for call behavior, media, and networking.
public struct CallSettings: Codable {
    public init() {}
    
    // MARK: - NAT Traversal
    
    /// Enables Interactive Connectivity Establishment (ICE)
    /// for NAT traversal.
    public var iceEnabled: Bool = false
    
    /// Controls whether the IP address in SDP should be replaced
    /// with the IP address found in the `Via` header of the REGISTER
    /// response, but only when STUN and ICE are disabled.
    ///
    /// - If `false` (default PJSIP behavior), the local IP address
    ///   will be used in SDP.
    /// - If `true`, the address learned from registration response
    ///   will be used instead.
    public var sdpNatRewriteUse: Bool = false
    
    /// Updates the transport address and `Contact` header of the REGISTER
    /// request whenever the public IP changes.
    ///
    /// When enabled, the library:
    /// - Tracks the public IP address from REGISTER responses.
    /// - If the address changes, unregisters the old contact,
    ///   updates the contact with the new transport address,
    ///   and registers again.
    /// - Updates the UDP transport public name if STUN is configured.
    public var contactRewriteUse: Bool = true
    
    /// Overwrites the `sent-by` field of the `Via` header for outgoing
    /// messages with the same interface address as the one used in
    /// the REGISTER request (if the same transport instance is reused).
    public var viaRewriteUse: Bool = true
    
    /// When enabled, the default STUN servers will be used
    /// if no custom servers are provided.
    public var useDefaultStun: Bool = true
    
    // MARK: - Media
    
    /// Specify whether secure media transport should be used for this account.
    public var srtpUse: SrtpUse = .PJMEDIA_SRTP_DISABLED
    
    // MARK: - Other Options
    
    /// If enabled, incoming calls will return a
    /// "Busy Everywhere" response when the user is already busy.
    var busyEverywhereUse: Bool = false
    
    /// A list of STUN servers (e.g. `"stun.l.google.com:19302"`)
    /// for NAT traversal.
    public var stunServers: [String] = []
}


///  This enumeration specifies the behavior of the SRTP transport regarding
///  media security offer and answer.
public enum SrtpUse: Int, Codable {
    /// When this flag is specified, SRTP will be disabled, and the transport will reject RTP/SAVP offer.
    case PJMEDIA_SRTP_DISABLED = 0
    
    /// When this flag is specified, SRTP will be advertised as optional
    /// and incoming SRTP offer will be accepted.
    case PJMEDIA_SRTP_OPTIONAL = 1
    
    /// When this flag is specified, the transport will require that RTP/SAVP media shall be used.
    case PJMEDIA_SRTP_MANDATORY = 2
}
