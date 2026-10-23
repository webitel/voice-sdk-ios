//
//  CallVideoController.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 21.10.2026.
//

import AVFoundation
import Foundation
import PJSIPKit
import UIKit


/// PJSIP video windows of one call: local preview, remote view and capture
/// orientation. Owned by `CallImpl`, which keeps the `Call`-visible video flags and
/// notifies observers. Confined to `SDKQueues.sip`.
final class CallVideoController {
    private weak var delegate: CallControlDelegate?
    private let sipId: () -> Int32
    private let logger = SDKLogger.make("voice.core.call")

    /// Orientation the call starts in (see `CallOptions.videoOrientation`), applied to the
    /// local preview layer as soon as it exists — see `attachLocalPreview`. The encoder-side
    /// equivalent is pushed independently by `SipManager.performMakeCall`, before this call
    /// is even placed, so this only needs to cover the local-preview half.
    private let initialOrientation: VideoOrientation

    private var currentCameraId: Int32 = 0
    private var previewStarted: Bool = false
    private weak var previewView: UIView?

    // PJSIP can reuse a numeric window id after recreating a native renderer. Keep
    // the actual view identity so a new renderer is never hidden by stale dedupe.
    private weak var remoteView: UIView?
    private var lastRemoteVideoSize: CGSize?
    private var lastAppliedOrientation: VideoOrientation?
    private var lastOrientationApplyTime: Date?
    private var pendingOrientationWorkItem: DispatchWorkItem?

    // PJSIP's native video-port renegotiation triggered by an orientation change (Metal
    // stream restart, encoder/decoder reconfiguration, keyframe request) takes on the order
    // of seconds. Applying another orientation change before it settles overlaps two
    // renegotiations on PJSIP's Metal render thread, which has been observed to leave
    // unpresented CAMetalLayer drawables behind, backing up the GPU command queue
    // (IOGPUCommandBufferCallbackErrorTimeout) and causing runaway memory growth. Throttle
    // to one native call per this interval and coalesce rapid rotations into the latest value.
    private let orientationApplyInterval: TimeInterval = 1.0

    var hasRemoteView: Bool {
        remoteView != nil
    }


    /// `sipId` is read when work runs, since a throttled orientation change is applied later.
    init(delegate: CallControlDelegate?, initialOrientation: VideoOrientation, sipId: @escaping () -> Int32) {
        self.delegate = delegate
        self.initialOrientation = initialOrientation
        self.sipId = sipId
    }


    // MARK: - Local preview

    /// Starts PJSIP's native preview on the default camera. Returns `false` if it was
    /// already started or failed to start.
    func startLocalPreview() -> Bool {
        if previewStarted { return false }
        previewStarted = true
        registerSipThread()

        var captureDevId: Int32 = 0
        if let deviceId = delegate?.defaultCaptureDeviceId() {
            captureDevId = deviceId
        } else {
            logger.warning("onShowLocalVideo: no camera found, falling back to default")
        }

        currentCameraId = captureDevId
        delegate?.syncActiveCaptureDevice(captureDevId, callId: sipId())

        var param = pjsua_vid_preview_param()
        pj_bzero(&param, MemoryLayout.size(ofValue: param))
        param.show = pj_bool_t(PJ_TRUE.rawValue)
        param.rend_id = PJMEDIA_VID_DEFAULT_RENDER_DEV.rawValue

        let status = pjsua_vid_preview_start(captureDevId, &param)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("onShowLocalVideo: failed to start video preview, status = \(status)")
            return false
        }
        return true
    }


    /// Fetches the preview view after `startLocalPreview` and applies the initial orientation.
    func attachLocalPreview() -> UIView? {
        guard let preview = getPreviewView() else {
            logger.warning("onShowLocalVideo: preview view not found")
            return nil
        }
        previewView = preview

        // The encoder side already got `initialOrientation` via SipManager before this
        // call was placed (see performMakeCall) — apply the same value here so the local
        // preview isn't left at AVFoundation's default orientation for the freshly opened
        // capture session. Recording it as already-applied keeps later reactive
        // `setVideoOrientation` calls (dedup/throttle) consistent with this baseline.
        lastAppliedOrientation = initialOrientation
        lastOrientationApplyTime = Date()
        applyPreviewOrientation(initialOrientation)

        return preview
    }


    /// `switchCamera()` changes the call's capture device without renegotiating
    /// media, so `onCallMediaState`/`onShowLocalVideo` never fires again — PJSIP
    /// recreates its native preview window internally as a side effect of the
    /// device change, but the Swift layer must re-fetch it and hand the new view
    /// to observers, or the UI keeps showing the old (dead) camera view.
    func refreshPreviewAfterCameraSwitch(_ newDeviceId: Int32) -> UIView? {
        currentCameraId = newDeviceId

        guard let preview = getPreviewView() else {
            logger.warning("switchCamera: preview view not found after switch")
            return nil
        }
        previewView = preview
        return preview
    }


    /// Resets only the local-preview half of the video state: `previewStarted`
    /// (so the next `onCallMediaState` → `onShowLocalVideo` isn't silently
    /// swallowed by the `if previewStarted { return }` guard) and stops PJSIP's
    /// native capture/preview window. Deliberately does NOT touch remote-video
    /// state — that's owned by `stop()`.
    func stopLocalPreview() {
        guard previewStarted else { return }
        previewStarted = false
        previewView = nil
        // May run after the SIP stack was destroyed (e.g. shutdown during a call).
        guard isPjsuaRunning else { return }
        registerSipThread()

        let status = pjsua_vid_preview_stop(currentCameraId)
        if status != PJ_SUCCESS.rawValue {
            logger.warning("stopLocalPreview: failed to stop preview, status = \(status)")
        }
    }


    /// Stops the local preview and forgets the remote view.
    func stop() {
        remoteView = nil
        lastRemoteVideoSize = nil
        stopLocalPreview()
    }


    private func getPreviewView() -> UIView? {
        registerSipThread()
        let capDevId = pjmedia_vid_dev_index(currentCameraId)
        let winId = pjsua_vid_preview_get_win(capDevId)

        guard winId != PJSUA_INVALID_ID.rawValue else {
            logger.warning("getPreviewView: no preview window available")
            return nil
        }

        return videoView(forWindow: winId, context: "getPreviewView")
    }


    // MARK: - Remote video

    /// Returns the remote view if it is new — PJSIP may hand back the same view
    /// for repeated media-state callbacks.
    func showRemoteVideo(_ cmi: pjsua_call_media_info) -> UIView? {
        logger.debug("onShowRemoteVideo() called")

        let winId = cmi.stream.vid.win_in
        guard winId != PJSUA_INVALID_ID.rawValue else {
            logger.warning("onShowRemoteVideo: no remote video window yet")
            return nil
        }

        guard let view = videoView(forWindow: winId, context: "onShowRemoteVideo") else { return nil }
        guard view !== remoteView else { return nil }
        remoteView = view
        return view
    }


    /// See `CallImpl.onRemoteVideoHoldChanged`.
    func clearRemoteView() {
        remoteView = nil
    }


    /// Returns `false` if the size didn't change.
    func updateRemoteVideoSize(width: Int, height: Int) -> Bool {
        let size = CGSize(width: width, height: height)
        guard size != lastRemoteVideoSize else { return false }
        lastRemoteVideoSize = size
        return true
    }


    private func videoView(forWindow winId: pjsua_vid_win_id, context: String) -> UIView? {
        var winInfo = pjsua_vid_win_info()
        let status = pjsua_vid_win_get_info(winId, &winInfo)
        guard status == PJ_SUCCESS.rawValue else {
            logger.warning("\(context): failed to get window info, status = \(status)")
            return nil
        }

        let ptr = winInfo.hwnd.info.ios.window ?? winInfo.hwnd.info.window
        guard let windowPtr = ptr else {
            logger.warning("\(context): hwnd pointer is nil")
            return nil
        }

        return Unmanaged<UIView>.fromOpaque(windowPtr).takeUnretainedValue()
    }


    // MARK: - Orientation

    func setOrientation(_ orientation: VideoOrientation) {
        // Rapid device-rotation notifications can deliver the same orientation several
        // times in a row; skip the redundant SIP-thread/render work when nothing changed.
        guard lastAppliedOrientation != orientation else {
            pendingOrientationWorkItem?.cancel()
            pendingOrientationWorkItem = nil
            return
        }

        let now = Date()
        if let lastApplyTime = lastOrientationApplyTime,
           now.timeIntervalSince(lastApplyTime) < orientationApplyInterval {
            let delay = orientationApplyInterval - now.timeIntervalSince(lastApplyTime)
            let workItem = DispatchWorkItem { [weak self] in
                self?.applyOrientationNow(orientation)
            }
            pendingOrientationWorkItem?.cancel()
            pendingOrientationWorkItem = workItem
            SDKQueues.sip.asyncAfter(deadline: .now() + delay, execute: workItem)
            return
        }

        applyOrientationNow(orientation)
    }

    private func applyOrientationNow(_ orientation: VideoOrientation) {
        SDKQueues.assertOnSip()
        pendingOrientationWorkItem = nil
        lastAppliedOrientation = orientation
        lastOrientationApplyTime = Date()

        applyPreviewOrientation(orientation)
        do {
            try delegate?.setVideoOrientation(withID: sipId(), orientation: orientation)
        } catch {
            logger.error("setVideoOrientation: error – \(error)")
        }
    }


    // TEMP: calibration logging — remove once the mapping is confirmed on-device.
    // The local preview is PJSIP's "built-in preview" (native AVFoundation preview
    // layer), which bypasses pjmedia's software orientation converter entirely —
    // so it must be rotated directly via AVCaptureVideoPreviewLayer, independent
    // of the pjmedia_orient capture-device setting (which only affects the
    // encoded/outgoing stream).
    private func applyPreviewOrientation(_ orientation: VideoOrientation) {
        // `previewView` is owned by `SDKQueues.sip`; UIKit work happens on main.
        guard let previewView else { return }
        DispatchQueue.main.async { [weak self, weak previewView] in
            guard let self, let previewView else { return }
            guard let previewLayer = previewView.layer as? AVCaptureVideoPreviewLayer else {
                self.logger.debug("applyPreviewOrientation: preview layer is not AVCaptureVideoPreviewLayer, falling back to view transform")
                previewView.transform = self.fallbackTransform(for: orientation)
                return
            }
            previewLayer.connection?.videoOrientation = self.avOrientation(for: orientation)
            self.logger.debug("applyPreviewOrientation: orientation=\(orientation), avOrientation=\(self.avOrientation(for: orientation).rawValue)")
        }
    }


    private func avOrientation(for orientation: VideoOrientation) -> AVCaptureVideoOrientation {
        switch orientation {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        }
    }


    private func fallbackTransform(for orientation: VideoOrientation) -> CGAffineTransform {
        switch orientation {
        case .portrait: return .identity
        case .portraitUpsideDown: return CGAffineTransform(rotationAngle: .pi)
        case .landscapeLeft: return CGAffineTransform(rotationAngle: -.pi / 2)
        case .landscapeRight: return CGAffineTransform(rotationAngle: .pi / 2)
        }
    }
}
