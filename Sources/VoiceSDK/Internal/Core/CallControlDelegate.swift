//
//  File 2.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 01.07.2025.
//

import Foundation


protocol CallControlDelegate: AnyObject {
    func disconnectCall(_ target: DisconnectTarget) throws
    func muteCall(withID id: Int32, muted: Bool) throws
    func holdCall(withID id: Int32, onHold: Bool) throws
    func sendDTMF(withID id: Int32, digits: String) throws
}
