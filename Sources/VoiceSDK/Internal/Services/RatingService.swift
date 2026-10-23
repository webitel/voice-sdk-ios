//
//  RatingService.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


struct RatingService: CallRatingProvider {
    private let api: MeetingAPI

    init(api: MeetingAPI) {
        self.api = api
    }


    func checkRatable(meetingId: String) async throws -> Bool {
        try await api.getMeeting(id: meetingId).allowSatisfaction
    }


    func submitRating(meetingId: String, satisfaction: String) async throws {
        try await api.submitSatisfaction(meetingId: meetingId, satisfaction: satisfaction)
    }
}
