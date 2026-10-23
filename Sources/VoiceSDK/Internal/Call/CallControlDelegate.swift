//
//  CallControlDelegate.swift
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
    func answerCall(withID id: Int32) throws
    func setSpeakerphoneOn(_ enabled: Bool) throws
    func switchCamera(withID id: Int32) throws -> Int32
    func defaultCaptureDeviceId() -> Int32?
    func syncActiveCaptureDevice(_ deviceId: Int32, callId: Int32)
    func setVideoEnabled(withID id: Int32, enabled: Bool) throws
    func setLocalVideoPaused(withID id: Int32, paused: Bool) throws
    func setVideoOrientation(withID id: Int32, orientation: VideoOrientation) throws
    func sendMediaStateInfo(withID id: Int32, audioMuted: Bool, videoMuted: Bool, hold: Bool) throws
}
