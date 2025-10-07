//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 25.06.2025.
//

import Foundation


struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let call: CallInfo?
}


struct CallInfo: Decodable {
    let userId: String
    let proxy: String
    let realm: String
    let secret: String?
}
