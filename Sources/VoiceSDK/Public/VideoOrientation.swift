//
//  VideoOrientation.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 11.11.2025.
//

import Foundation


/// Physical orientation of the device holding the camera, reported to the SDK so the
/// outgoing video can be rotated upright before it is sent to the remote party.
///
/// These cases mirror `UIDeviceOrientation`'s physical semantics (i.e. where the
/// device's home button / bottom edge points), not `UIInterfaceOrientation`'s —
/// the two use opposite `landscapeLeft`/`landscapeRight` meanings for the same
/// physical rotation, so callers should map `UIDevice.current.orientation`
/// directly, case for case, without inverting left/right.
///
/// The SDK does not track device orientation on its own — the host app owns two
/// touch points: `CallOptions.videoOrientation` for the orientation the call
/// *starts* in, and `Call.setVideoOrientation(_:)` for rotation that happens
/// *during* an ongoing call. Both matter: the SDK has no other way to learn the
/// current physical orientation when a call begins, so relying on rotation
/// notifications alone leaves a new call showing whatever orientation the
/// previous, unrelated call last ended with.
public enum VideoOrientation: Equatable {
    /// Device held upright, home button / bottom edge down.
    case portrait
    /// Device upside down, home button / bottom edge up.
    case portraitUpsideDown
    /// Device on its side, home button / bottom edge on the right.
    case landscapeLeft
    /// Device on its side, home button / bottom edge on the left.
    case landscapeRight
}
