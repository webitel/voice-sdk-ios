//
//  CallEvent.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.06.2026.
//

import Foundation
import UIKit


/// Call-related events emitted by the SDK.
public enum CallEvent {

    case connection(ConnectionEvent)
    case localMedia(LocalMediaEvent)
    case remoteMedia(RemoteMediaEvent)
    case video(VideoEvent)
    

    /// Call identifier associated with the event.
    public var callId: UUID {

        switch self {
        case .connection(let event):
            return event.callId

        case .localMedia(let event):
            return event.callId

        case .video(let event):
            return event.callId

        case .remoteMedia(let event):
            return event.callId
        }
    }
}


// MARK: - Connection Events
public enum ConnectionEvent {

    case stateChanged(
        callId: UUID,
        state: CallState
    )

    var callId: UUID {
        switch self {
        case .stateChanged(let id, _):
            return id
        }
    }
}


// MARK: - Local Media Events
public enum LocalMediaEvent {

    case muteChanged(
        callId: UUID,
        isMuted: Bool
    )

    case holdChanged(
        callId: UUID,
        isOnHold: Bool
    )

    case speakerphoneChanged(
        callId: UUID,
        isSpeakerphoneOn: Bool
    )

    case videoPausedChanged(
        callId: UUID,
        isPaused: Bool
    )

    var callId: UUID {
        switch self {
        case .muteChanged(let id, _),
             .holdChanged(let id, _),
             .speakerphoneChanged(let id, _),
             .videoPausedChanged(let id, _):
            return id
        }
    }
}


// MARK: - Video Events
public enum VideoEvent {

    case stateChanged(
        callId: UUID,
        state: VideoState
    )

    case localViewReady(
        callId: UUID,
        view: UIView
    )

    case remoteViewReady(
        callId: UUID,
        view: UIView
    )

    case sizeChanged(
        callId: UUID,
        isLocal: Bool,
        width: Int,
        height: Int
    )

    var callId: UUID {
        switch self {
        case .stateChanged(let id, _),
             .localViewReady(let id, _),
             .remoteViewReady(let id, _),
             .sizeChanged(let id, _, _, _):
            return id
        }
    }
}


// MARK: - Remote Media Events
public enum RemoteMediaEvent {

    case muteChanged(
        callId: UUID,
        isMuted: Bool
    )

    case holdChanged(
        callId: UUID,
        isOnHold: Bool
    )

    case videoPausedChanged(
        callId: UUID,
        isPaused: Bool
    )

    var callId: UUID {
        switch self {
        case .muteChanged(let id, _),
             .holdChanged(let id, _),
             .videoPausedChanged(let id, _):
            return id
        }
    }
}
