//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 12.09.2025.
//

import Foundation


enum DisconnectTarget {
    case sip(id: Int32)
    case local(uuid: UUID)
}
