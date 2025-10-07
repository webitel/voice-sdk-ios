//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2025.
//

import Foundation


final class Api {
    
    private let loginPath = "/api/portal/token"
    private(set) var networkConfiguration: NetworkConfiguration
    
    init(networkConfiguration: NetworkConfiguration) {
        self.networkConfiguration = networkConfiguration
    }
    
    
    func getSipConfig(jwt: String) async throws -> AccessTokenResponse {
        let url = try buildURL(for: loginPath)
        var request = makeRequest(url: url, method: "GET")
        request.addValue(jwt, forHTTPHeaderField: "X-Webitel-Access")
        
        return try await send(request, label: "getSipConfig")
    }
    
    
    func login(_ body: TokenRequest) async throws -> AccessTokenResponse {
        let url = try buildURL(for: loginPath)
        var request = makeRequest(url: url, method: "POST")
        request.httpBody = encodeBody(body)
        
        return try await send(request, label: "login")
    }
    
    
    private func buildURL(for path: String) throws -> URL {
        let host = normalizeBaseUrl(networkConfiguration.baseUrl)
        guard let url = URL(string: host + path) else {
            throw CallError.invalidURL(message: "Invalid URL: \(host + path)")
        }
        return url
    }

    
    private func makeRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(networkConfiguration.deviceId, forHTTPHeaderField: "x-portal-device")
        request.addValue(networkConfiguration.clientToken, forHTTPHeaderField: "x-portal-client")
        request.addValue(networkConfiguration.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
    
    
    private func send(_ request: URLRequest, label: String) async throws -> AccessTokenResponse {
        WLog.shared.debug("\(label): request - \(request)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
            try handleResponseError(httpResponse, data)
        }
        
        WLog.shared.debug("\(label): response - \(String(data: data, encoding: .utf8) ?? "")")
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(AccessTokenResponse.self, from: data)
        } catch {
            throw handleError(error)
        }
    }
    
    
    private func encodeBody(_ body: Encodable) -> Data? {
        try? JSONEncoder().encode(body)
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
    
    
    private func handleError(_ error: Error) -> CallError {
        return CallError.unknown(message: error.localizedDescription, code: -1)
    }
    
    
    private func normalizeBaseUrl(_ baseUrl: String) -> String {
        if baseUrl.lowercased().hasPrefix("http://") || baseUrl.lowercased().hasPrefix("https://") {
            return baseUrl
        } else {
            return "https://\(baseUrl)"
        }
    }
}
