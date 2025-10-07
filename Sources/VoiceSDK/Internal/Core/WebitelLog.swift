//
//  WebitelLog.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 27.06.2025.
//
import Foundation


final class WLog {
    private let queue = DispatchQueue(label: "com.webitel.wlog.queue")
    private var _logLevel: LogLevel = .debug
    private let labelText = "com.webitel"
    private let formatter: DateFormatter
    
    static let shared = WLog()
    private init() {
        formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    }

    
    var logLevel: LogLevel {
        get {
            queue.sync { _logLevel }
        }
        set {
            queue.sync { _logLevel = newValue }
        }
    }

    
    func debug(_ message: String) {
        log(message, level: .debug)
    }
    

    func info(_ message: String) {
        log(message, level: .info)
    }
    

    func warning(_ message: String) {
        log(message, level: .warning)
    }

    
    func error(_ message: String) {
        log(message, level: .error)
    }

    
    private func log(_ message: String, level: LogLevel) {
        queue.async {
            if level.rawValue >= self._logLevel.rawValue {
                let timeStamp = self.formatter.string(from: Date())
                print("\(timeStamp) [\(level.rawValue)] \(self.labelText) - \(message)")
            }
        }
    }
}


