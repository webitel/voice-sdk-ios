//
//  MeetingAPI.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2026.
//

import Foundation


/// `/api/meetings` — meeting metadata and satisfaction rating.
struct MeetingAPI {
    private let http: HTTPClient

    init(http: HTTPClient) {
        self.http = http
    }


    /// Fetches meeting metadata, including whether it currently allows a
    /// satisfaction rating.
    func getMeeting(id: String) async throws -> MeetingResponse {
        let request = try http.makeRequest(path: "/api/meetings/\(id)", method: "GET")

        return try await http.send(request, label: "getMeeting")
    }


    /// Submits a satisfaction rating for a meeting. The response body is
    /// empty — only the HTTP status is meaningful.
    func submitSatisfaction(meetingId: String, satisfaction: String) async throws {
        var request = try http.makeRequest(path: "/api/meetings/\(meetingId)/satisfaction", method: "POST")
        request.httpBody = http.encodeBody(SatisfactionRequest(satisfaction: satisfaction))

        try await http.sendNoContent(request, label: "submitSatisfaction")
    }
}
