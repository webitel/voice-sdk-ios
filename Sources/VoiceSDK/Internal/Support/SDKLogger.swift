//
//  SDKLogger.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 09.07.2026.
//

import Foundation
import Logging


internal enum SDKLogger {

    private static var level: Logger.Level = .error
    private static var handlerFactory: ((String) -> LogHandler)?

    
    static func configure(
        level: Logger.Level,
        handlerFactory: ((String) -> LogHandler)?
    ) {
        self.level = level
        self.handlerFactory = handlerFactory
    }
    

    static func make(_ label: String) -> Logger {
        var logger = if let factory = handlerFactory {
            Logger(label: label, factory: factory)
        } else {
            Logger(label: label)
        }
        
        logger.logLevel = level
        return logger
    }
}
