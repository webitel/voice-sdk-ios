//
//  File.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 12.09.2025.
//

import Foundation


enum CancelCallCode: UInt32 {
    case NORMAL_CLEARING = 200
    case USER_BUSY_HERE = 486
    case ORIGINATOR_CANCEL = 487
    case USER_BUSY_EVERYWHERE = 600
}
