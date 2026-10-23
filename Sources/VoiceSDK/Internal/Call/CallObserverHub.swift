//
//  CallObserverHub.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import Foundation
import UIKit


/// Weakly held `CallObserver`s of one call. Thread-safe.
final class CallObserverHub {
    private let observers = Protected(NSHashTable<AnyObject>.weakObjects())

    func add(_ observer: CallObserver) {
        observers.write { $0.add(observer) }
    }


    func remove(_ observer: CallObserver) {
        observers.write { $0.remove(observer) }
    }


    func removeAll() {
        observers.write { $0.removeAllObjects() }
    }


    /// Events are delivered in order on `SDKQueues.events`.
    func notify(_ event: CallEvent) {
        let targets = observers.read { $0.allObjects }.compactMap { $0 as? CallObserver }
        guard !targets.isEmpty else { return }
        // Video events carry a PJSIP-owned `UIView`, and the SDK's reference may be the last
        // one — UIKit requires a view to be deallocated on main, so drop it there.
        let box = EventBox(event)
        SDKQueues.events.async {
            // Scoped so this local reference is gone before the main-thread release below.
            if let event = box.event {
                for observer in targets {
                    observer.onEvent(event)
                }
            }
            DispatchQueue.main.async { box.event = nil }
        }
    }
}


/// Lets `notify` choose the thread that releases an event's payload.
private final class EventBox: @unchecked Sendable {
    var event: CallEvent?

    init(_ event: CallEvent) {
        self.event = event
    }
}
