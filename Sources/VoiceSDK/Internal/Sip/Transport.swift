//
//  Transport.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


enum Transport: Int, Codable, CaseIterable {
    case UDP = 0
    case TCP = 1
    case TCP_UDP = 2
    case TLS = 3
}
