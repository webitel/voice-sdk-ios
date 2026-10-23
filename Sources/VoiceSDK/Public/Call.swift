//
//  Call.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 24.06.2025.
//

import Foundation


/// A voice/video call.
///
/// All methods can be called from any thread and never block: they validate the current
/// state synchronously (throwing `CallError.invalidState`) and perform the actual work
/// asynchronously on the SDK's internal queue. The resulting change is reported through
/// `CallObserver.onEvent`, which is delivered on an internal serial SDK queue.
public protocol Call {
    var id: UUID { get }

    /// Current state of the call (e.g. ringing, active, ended).
    var state: CallState { get }

    /// Indicates whether the local microphone is muted.
    var isMuted: Bool { get }

    /// Indicates whether the call is currently on hold.
    var isOnHold: Bool { get }

    /// Timestamp in milliseconds when the call was answered.
    var answeredAt: Int64 { get }

    /// True if the call was initiated by the local user (outgoing).
    var isOutgoing: Bool { get }

    /// Display name of the remote party: the caller name from the push for incoming
    /// calls, or `CallOptions.toName` for outgoing calls.
    var remoteName: String? { get }

    /// Number of the remote party: the caller number from the push for incoming
    /// calls, or `CallOptions.toNumber` for outgoing calls.
    var remoteNumber: String? { get }

    var hasVideo: Bool { get }

    /// Indicates whether audio is currently routed to the loudspeaker.
    var isSpeakerphoneOn: Bool { get }

    /// Indicates whether local video transmission is paused
    /// (camera capture keeps running, but no frames are sent).
    var isLocalVideoPaused: Bool { get }

    /// True if the remote party's microphone is muted, as last reported via a SIP INFO packet.
    var isRemoteMuted: Bool { get }

    /// True if the remote party has placed the call on hold, as last reported via a SIP INFO packet.
    var isRemoteOnHold: Bool { get }

    /// True if the remote party paused sending video without renegotiating the call, as last
    /// reported via a SIP INFO packet. Independent of `videoState` — mirrors `isLocalVideoPaused`
    /// for the remote side.
    var isRemoteVideoPaused: Bool { get }

    /// Current local/remote video activity of the call.
    var videoState: VideoState { get }

    /// Mute or unmute the microphone. Can be called as soon as the call exists —
    /// including while it's still `.connecting`/`.ringing`, before any media
    /// session is negotiated — not only once it's `.ongoing`.
    func mute(_ mute: Bool) throws

    /// Put the call on hold or resume it.
    func hold(_ hold: Bool) throws

    /// Send DTMF digits during the call.
    func sendDTMF(_ digits: String) throws

    /// Answer an incoming call. Allowed only for incoming calls in `.ringing` state.
    /// If the SIP INVITE has not arrived yet, the call is answered as soon as it does.
    func answer() throws

    /// Disconnect or hang up the call. For an unanswered incoming call this declines it.
    func disconnect() throws


    func setVideoOrientation(_ orientation: VideoOrientation) throws

    /// Route call audio to the loudspeaker or back to the earpiece.
    func setSpeakerphoneOn(_ enabled: Bool) throws

    /// Switch between the available cameras (e.g. front/back).
    func switchCamera() throws

    /// Add a video stream to an ongoing audio call.
    func enableVideo() throws

    /// Remove the video stream from an ongoing call.
    func disableVideo() throws

    /// Pause or resume local video transmission without renegotiating the call.
    /// Can be called as soon as the call exists — including while it's still
    /// `.connecting`/`.ringing`, before any media session is negotiated — not
    /// only once it's `.ongoing`.
    func setLocalVideoPaused(_ paused: Bool) throws

    /// Add an observer for call events.
    func addObserver(_ observer: CallObserver)

    /// Remove a specific observer.
    func removeObserver(_ observer: CallObserver)

    /// Remove all observers.
    func removeAllObservers()

    /// Checks whether this call is currently eligible for a post-call
    /// satisfaction rating.
    ///
    /// Calls placed without a `meetingId` (see `CallOptions.meetingId`)
    /// are never ratable — this returns `false` immediately, without any
    /// network request. Otherwise this performs a network request to the
    /// backend to check whether a rating is currently allowed.
    func isRatable() async throws -> Bool

    /// Submits a satisfaction rating for this call.
    ///
    /// - Parameter satisfaction: An opaque, backend-defined rating value
    ///   (e.g. a numeric scale encoded as a string, or a sentiment keyword).
    ///   The SDK performs no client-side validation of its format or range.
    /// - Throws: `CallError.invalidState` if the call has no associated
    ///   `meetingId`, or the underlying network error otherwise.
    func rate(_ satisfaction: String) async throws
}


public extension Call {
    /// Callback-based variant of `isRatable()`.
    func isRatable(completion: @escaping (Result<Bool, CallError>) -> Void) {
        Task {
            do {
                completion(.success(try await isRatable()))
            } catch {
                completion(.failure(CallError.from(error)))
            }
        }
    }

    /// Callback-based variant of `rate(_:)`.
    func rate(_ satisfaction: String, completion: @escaping (Result<Void, CallError>) -> Void) {
        Task {
            do {
                try await rate(satisfaction)
                completion(.success(()))
            } catch {
                completion(.failure(CallError.from(error)))
            }
        }
    }
}
