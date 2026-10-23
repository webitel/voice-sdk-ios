//
//  VoiceClient.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// A high-level interface for managing voice calls.
///
/// `VoiceClient` handles user identity, authentication tokens,
/// call setup, configuration, and lifecycle management.
public protocol VoiceClient {
    
    /// The currently active call, if any.
    var activeCall: Call? { get }

    /// All calls that haven't ended yet, in no particular order. Holds more than one
    /// call only while an incoming call is waiting: answering it puts the other call
    /// on hold, and `Call.hold(false)` on the held call swaps them back.
    var calls: [Call] { get }

    
    /// Creates and starts a new call using the configured authentication method.
    ///
    /// - Parameters:
    ///   - options: Call configuration, including its media type.
    ///   - observer: A `CallObserver` that receives call events
    ///     (e.g. ringing, connected, ended).
    /// - Returns: A `Call` instance representing the ongoing call.
    func makeCall(options: CallOptions, observer: CallObserver) -> Call


    /// Handles an incoming call VoIP push and returns the incoming call immediately.
    ///
    /// The returned call starts in `.ringing` state with `id == push.callId`.
    /// In the background the SDK fetches the SIP configuration, registers the SIP
    /// account and notifies the server that the client is ready to receive the call.
    /// Once the SIP INVITE arrives the call can be answered with `Call.answer()`;
    /// `answer()` may also be called earlier — the call is answered as soon as the
    /// INVITE is received. Use `Call.disconnect()` to decline.
    ///
    /// Calling this again with the same `callId` (duplicate push) returns the existing call.
    ///
    /// - Parameters:
    ///   - push: Parsed push data (see `IncomingCallPush.init(payload:)`).
    ///   - observer: A `CallObserver` that receives call events.
    /// - Returns: A `Call` instance representing the incoming call.
    func handleIncomingPush(_ push: IncomingCallPush, observer: CallObserver) -> Call


    /// Registers the VoIP push token (`PKPushCredentials.token`) on the server,
    /// so the server can deliver incoming call pushes to this device.
    func registerPushToken(_ token: Data) async throws


    /// Configures the client with general call-related settings.
    ///
    /// - Parameter settings: A `CallSettings` object that controls
    ///   audio, networking, and other call options.
    func configure(_ settings: CallSettings)

    
    /// Shuts down the client and releases its resources.
    ///
    /// - Parameter onComplete: A closure that is called once shutdown
    ///   is fully complete.
    func shutdown(onComplete: @escaping () -> Void)
}


public extension VoiceClient {
    /// Creates and starts an audio call with default `CallOptions()`.
    func makeCall(observer: CallObserver) -> Call {
        makeCall(options: CallOptions(), observer: observer)
    }


    /// Parses a raw PushKit payload (`PKPushPayload.dictionaryPayload`) and handles
    /// the incoming call. See `handleIncomingPush(_:observer:)`.
    ///
    /// - Throws: `CallError.invalidResponse` if the payload is not a valid incoming call push.
    func handleIncomingPush(_ payload: [AnyHashable: Any], observer: CallObserver) throws -> Call {
        guard let push = IncomingCallPush(payload: payload) else {
            throw CallError.invalidResponse(message: "Invalid incoming call push payload")
        }
        return handleIncomingPush(push, observer: observer)
    }


    /// Callback-based variant of `registerPushToken(_:)`.
    func registerPushToken(_ token: Data, completion: @escaping (Result<Void, CallError>) -> Void) {
        Task {
            do {
                try await registerPushToken(token)
                completion(.success(()))
            } catch {
                completion(.failure(CallError.from(error)))
            }
        }
    }
}
