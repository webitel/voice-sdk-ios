//
//  VideoState.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.06.2026.
//

import Foundation


/// Represents the current video activity of a call.
public enum VideoState {
    /// Neither local nor remote video is active.
    case inactive

    /// Only the local camera is being transmitted.
    case localOnly

    /// Only the remote party's video is being received.
    case remoteOnly

    /// Both local and remote video are active.
    case active
}
