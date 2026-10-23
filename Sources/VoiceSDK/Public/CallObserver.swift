//
//  CallObserver.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.06.2026.
//

import Foundation


/// An observer protocol for receiving call-related events.
///
/// Implementations receive a single unified `CallEvent` and can switch
/// on its nested cases (`connection`, `localMedia`, `video`, `remoteMedia`)
/// to react to the parts they care about.
public protocol CallObserver: AnyObject {
    /// Called whenever a call event occurs.
    ///
    /// - Parameter event: The event describing what changed.
    func onEvent(_ event: CallEvent)
}
