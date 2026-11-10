//
//  AudioSessionController.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 23.10.2026.
//

import Foundation
import AVFAudio


/// Decides when PJSIP may use the sound device: only while a call needs audio
/// *and* the audio session is active.
///
/// - `.automatic` (no CallKit): the session counts as active, except during an
///   `AVAudioSession` interruption (e.g. a cellular call), after which it is reactivated.
/// - `.external` (CallKit): the session is active only between CallKit's
///   `didActivate` and `didDeactivate` — opening the device earlier yields no audio.
///
/// Confined to `SDKQueues.sip`, except `init`.
final class AudioSessionController {

    enum Mode {
        case automatic
        case external
    }

    private let logger = SDKLogger.make("voice.core.audioSession")
    private let openDevice: () -> Void
    private let closeDevice: () -> Void

    private var mode: Mode = .automatic
    private var needsAudio = false
    private var isSessionActive = true
    private var isDeviceOpen = false
    private var interruptionObserver: NSObjectProtocol?
    /// Warns when the session isn't activated for a call that needs audio, e.g. the
    /// host didn't report the call to CallKit or didn't forward `didActivate`.
    private var activationWatchdog: DispatchWorkItem?


    init(openDevice: @escaping () -> Void, closeDevice: @escaping () -> Void) {
        self.openDevice = openDevice
        self.closeDevice = closeDevice
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: nil
        ) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            SDKQueues.sip.async { self?.onInterruption(type) }
        }
    }


    deinit {
        interruptionObserver.map(NotificationCenter.default.removeObserver)
    }


    func setMode(_ mode: Mode) {
        SDKQueues.assertOnSip()
        guard self.mode != mode else { return }
        self.mode = mode
        isSessionActive = mode == .automatic
        update()
    }


    /// A call started connecting or was answered. Opening the device again while
    /// it is already open would interrupt the audio of a call in progress.
    func requestAudio() {
        SDKQueues.assertOnSip()
        needsAudio = true
        update()
    }


    /// pjsua was destroyed, together with its sound device.
    func reset() {
        SDKQueues.assertOnSip()
        needsAudio = false
        isDeviceOpen = false
        // iOS doesn't always post `.ended`; a missing one must not leave the next call silent.
        if mode == .automatic { isSessionActive = true }
        updateActivationWatchdog()
    }


    func sessionDidActivate() {
        SDKQueues.assertOnSip()
        guard mode == .external else { return }
        logger.debug("audio session activated")
        isSessionActive = true
        update()
    }


    func sessionDidDeactivate() {
        SDKQueues.assertOnSip()
        guard mode == .external else { return }
        logger.debug("audio session deactivated")
        isSessionActive = false
        update()
    }


    private func onInterruption(_ type: AVAudioSession.InterruptionType) {
        // With CallKit the system resolves interruptions through hold actions and
        // `didDeactivate`/`didActivate`.
        guard mode == .automatic else { return }

        switch type {
            case .began:
                logger.debug("audio session interrupted")
                isSessionActive = false

            case .ended:
                guard needsAudio else {
                    isSessionActive = true
                    return
                }
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    logger.debug("audio session reactivated after interruption")
                    isSessionActive = true
                } catch {
                    logger.error("failed to reactivate audio session after interruption: \(error)")
                }

            @unknown default:
                return
        }
        update()
    }


    private func update() {
        updateActivationWatchdog()
        let shouldOpen = needsAudio && isSessionActive
        guard shouldOpen != isDeviceOpen else { return }
        isDeviceOpen = shouldOpen
        shouldOpen ? openDevice() : closeDevice()
    }


    private func updateActivationWatchdog() {
        guard mode == .external, needsAudio, !isSessionActive else {
            activationWatchdog?.cancel()
            activationWatchdog = nil
            return
        }
        guard activationWatchdog == nil else { return }
        let workItem = DispatchWorkItem { [logger] in
            logger.warning("""
                A call needs audio, but the audio session isn't active: report the call to CallKit \
                and forward provider(_:didActivate:) to VoiceClient.audioSessionDidActivate()
                """)
        }
        activationWatchdog = workItem
        SDKQueues.sip.asyncAfter(deadline: .now() + 3, execute: workItem)
    }
}
