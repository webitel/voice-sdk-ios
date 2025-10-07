//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//

import Foundation


struct SipConfig {
    private let auth: String
    private let domain: String
    private let `extension`: String
    private let password: String
    private let proxy: String
    
    
    init(auth: String, domain: String, `extension`: String, password: String, proxy: String) {
        self.auth = auth
        self.domain = domain
        self.password = password
        self.`extension` = `extension`
        self.proxy = proxy
        
    }
    
    
    func getProxy() -> String {
        return proxy.hasPrefix("sip:")
            ? proxy : "sip:\(proxy)"
    }
    
    
    func getServerUri() -> String {
        return proxy.hasPrefix("sip:")
            ? String(proxy.dropFirst(4)) : proxy
    }
    
    
    func getPassword() -> String {
        return password
    }
    
    
    func getExtension() -> String {
        return `extension`
    }
    
    
    func getDomain() -> String {
        return domain
    }
    
    
    func getAuth() -> String {
        return auth
    }
}
