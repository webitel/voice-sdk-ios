//
//  HTTPClient.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2025.
//

import Foundation


/// Shared HTTP plumbing for the portal API: common headers, JSON coding and
/// error mapping. Endpoints live in `Network/Endpoints`.
final class HTTPClient {
    private let logger = SDKLogger.make("voice.network")
    private let context: ClientContext

    init(context: ClientContext) {
        self.context = context
    }


    func makeRequest(path: String, method: String) throws -> URLRequest {
        let url = try buildURL(for: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(context.deviceId, forHTTPHeaderField: "x-portal-device")
        request.addValue(context.clientToken, forHTTPHeaderField: "x-portal-client")
        request.addValue(context.agent, forHTTPHeaderField: "User-Agent")
        return request
    }


    func encodeBody(_ body: Encodable) -> Data? {
        try? JSONEncoder().encode(body)
    }


    func send<T: Decodable>(_ request: URLRequest, label: String) async throws -> T {
        let (data, _) = try await performRequest(request, label: label)

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CallError.from(error)
        }
    }


    func sendNoContent(_ request: URLRequest, label: String) async throws {
        _ = try await performRequest(request, label: label)
    }


    private func buildURL(for path: String) throws -> URL {
        URLComponents(
            url: context.baseURL
                .appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!.url!
    }


    private func performRequest(_ request: URLRequest, label: String) async throws -> (Data, URLResponse) {
        logger.debug("""
            \(label):
            Method: \(request.httpMethod ?? "GET")
            URL: \(request.url?.absoluteString ?? "")
            Headers: \(request.allHTTPHeaderFields ?? [:])
            """)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"
        logger.debug("response: \(message) ")
        
        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            try handleResponseError(httpResponse, data)
        }

        logger.debug("\(label): response received, \(data.count) bytes")
        return (data, response)
    }


    private func handleResponseError(_ response: HTTPURLResponse, _ data: Data) throws {
        let message = String(data: data, encoding: .utf8) ?? "Unknown error"

        let err = if response.statusCode == 401 {
            CallError.unauthorized(message: message)
        } else {
            CallError.unknown(message: message, code: response.statusCode)
        }
        throw err
    }
}
