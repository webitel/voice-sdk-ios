//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// Represents the general category of how a call ended.
public enum CallEndCategory: String {
    /// The call ended normally (e.g., the other side hung up).
    case normal
    
    /// The call could not be completed because the line was busy.
    case busy
    
    /// The call could not be completed because the user or service was unavailable.
    case unavailable
    
    /// The call ended due to an error (e.g., network or signaling failure).
    case error
    
    /// The call was canceled before it was established.
    case canceled
    
    /// The reason for ending the call is unknown.
    case unknown
}
