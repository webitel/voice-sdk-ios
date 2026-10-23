//
//  Protected.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation


/// A value guarded by a lock, for state that is written on `SDKQueues.sip`
/// but read from arbitrary client threads.
final class Protected<Value> {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self.value = value
    }


    func read<T>(_ body: (Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(value)
    }


    @discardableResult
    func write<T>(_ body: (inout Value) throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}
