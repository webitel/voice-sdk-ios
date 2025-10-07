//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 30.06.2025.
//

import Foundation


class DeviceStorage {
    private let deviceIdKey = "device_id_key"
    private let preferences = UserDefaults.standard
    
    
    func getDeviceId() -> String {
        let deviceId = preferences.string(forKey: deviceIdKey)
        
        if let id = deviceId, !id.isEmpty  {
            return id
        }
        
        let newDeviceId = UUID().uuidString
        saveDeviceId(id: newDeviceId)
        return newDeviceId
        
    }

    
    private func saveDeviceId(id: String) {
        preferences.setValue(id, forKey: deviceIdKey)
        preferences.synchronize()
    }
}
