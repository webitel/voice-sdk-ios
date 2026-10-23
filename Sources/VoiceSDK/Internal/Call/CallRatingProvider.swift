//
//  CallRatingProvider.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import Foundation


/// Internal abstraction used by `CallImpl` to check rating eligibility and
/// submit a satisfaction rating for a finished call, without depending
/// directly on `AuthManager`/`Api`.
protocol CallRatingProvider {
    /// Checks whether the given meeting currently allows a satisfaction rating.
    func checkRatable(meetingId: String) async throws -> Bool

    /// Submits a satisfaction rating for the given meeting.
    func submitRating(meetingId: String, satisfaction: String) async throws
}
