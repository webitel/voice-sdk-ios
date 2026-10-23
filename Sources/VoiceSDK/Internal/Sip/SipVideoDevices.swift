//
//  SipVideoDevices.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation
import PJSIPKit


/// Video capture/render device selection and capture orientation. Owned by
/// `SipManager`; all methods must be called on `SDKQueues.sip`.
final class SipVideoDevices {
    private let logger = SDKLogger.make("voice.core.sip")
    private var currentCaptureDeviceIndex = 0


    @discardableResult
    func switchCamera(id: Int32) throws -> Int32 {
        try ensurePjsuaRunning()
        let devices = captureDeviceIds()
        guard devices.count > 1 else {
            let message = "No alternate camera available"
            logger.warning("switchCamera: \(message)")
            throw CallError.invalidState(message: message)
        }

        currentCaptureDeviceIndex = (currentCaptureDeviceIndex + 1) % devices.count
        let newDeviceId = devices[currentCaptureDeviceIndex]

        var param = pjsua_call_vid_strm_op_param()
        pjsua_call_vid_strm_op_param_default(&param)
        param.med_idx = -1
        param.cap_dev = newDeviceId

        let status = pjsua_call_set_vid_strm(pjsua_call_id(id), PJSUA_CALL_VID_STRM_CHANGE_CAP_DEV, &param)
        guard status == PJ_SUCCESS.rawValue else {
            logger.error("switchCamera: \(status.description)")
            throw CallError.sipError(message: status.description)
        }

        // The orientation setting is bound to a specific capture device id,
        // so it must be re-applied whenever the active device changes.
        reapplyOrientation()

        return newDeviceId
    }


    /// Keeps `currentCaptureDeviceIndex` (used by `setVideoOrientation`/`switchCamera`)
    /// in sync with the capture device a new call actually starts on. Needed because
    /// `SipManager` is a long-lived singleton shared across calls, while the active
    /// capture device is picked independently per call by `CallImpl.onShowLocalVideo`
    /// — without this, orientation continues to target whatever camera the *previous*
    /// call last switched to.
    func syncActiveCaptureDevice(_ deviceId: Int32, callId: Int32) {
        let devices = captureDeviceIds()
        guard let index = devices.firstIndex(of: deviceId) else {
            logger.warning("syncActiveCaptureDevice: device \(deviceId) not found among capture devices")
            return
        }
        currentCaptureDeviceIndex = index

        // PJSIP defaults a freshly opened capture device to NATURAL orientation.
        // Re-push the last known device orientation so a new call doesn't start
        // with a mis-rotated outgoing stream even if the host app never calls
        // `setVideoOrientation` again for this call (it may only react to actual
        // device-orientation-change events, not to new calls starting).
        try? setVideoOrientation(currentOrientation)

        // The device already sent at least one frame with the stale (NATURAL)
        // orientation before this correction ran, so force an immediate keyframe
        // rather than waiting for the natural keyframe interval — this bounds
        // the visible glitch on the remote side to a single frame instead of
        // however long that interval is.
        var keyframeParam = pjsua_call_vid_strm_op_param()
        pjsua_call_vid_strm_op_param_default(&keyframeParam)
        keyframeParam.med_idx = -1
        _ = pjsua_call_set_vid_strm(pjsua_call_id(callId), PJSUA_CALL_VID_STRM_SEND_KEYFRAME, &keyframeParam)
    }


    /// Only devices whose name identifies them as a real AVFoundation camera
    /// (e.g. "Front Camera" / "Back Camera") are considered switch candidates.
    /// PJSIP also registers built-in test/dummy capture devices (e.g. the
    /// "Colorbar generator" / "Colorbar-active" test-pattern source) with the
    /// same capture direction bit — without this filter, `switchCamera()`'s
    /// round-robin walks through those too, briefly sending color bars to the
    /// remote party and requiring several presses to reach the next real camera.
    private func captureDeviceIds() -> [pjmedia_vid_dev_index] {
        (0..<Int(pjsua_vid_dev_count())).compactMap { i in
            var info = pjmedia_vid_dev_info()
            let index = pjmedia_vid_dev_index(i)
            guard pjmedia_vid_dev_get_info(index, &info) == PJ_SUCCESS.rawValue,
                  (info.dir.rawValue & PJMEDIA_DIR_CAPTURE.rawValue) != 0 else { return nil }
            logDeviceNameOnce(index, info: info)
            guard deviceName(from: info).localizedCaseInsensitiveContains("camera") else { return nil }
            return index
        }
    }


    /// The camera a new call's local preview starts on — the first real camera, using
    /// the same filter as `switchCamera()` so the two never disagree on device ids.
    func defaultCaptureDeviceId() -> Int32? {
        return captureDeviceIds().first
    }


    private func deviceName(from info: pjmedia_vid_dev_info) -> String {
        withUnsafeBytes(of: info.name) { raw -> String in
            String(cString: raw.bindMemory(to: CChar.self).baseAddress!)
        }
    }


    // TEMP: calibration logging — log each capture device's id/name once so real
    // device names (front/back) can be correlated with rotation test results.
    private var loggedDeviceIds: Set<Int32> = []
    private func logDeviceNameOnce(_ index: pjmedia_vid_dev_index, info: pjmedia_vid_dev_info) {
        guard !loggedDeviceIds.contains(index) else { return }
        loggedDeviceIds.insert(index)
        logger.debug("captureDeviceIds: device id=\(index), name=\"\(deviceName(from: info))\"")
    }


    /// Last orientation applied via `setVideoOrientation`, re-applied to the active
    /// capture device after `switchCamera()` since the setting is per-device.
    private var currentOrientation: VideoOrientation = .portrait


    /// Applies the given physical device orientation to the currently active video
    /// capture device, rotating both the local preview and the outgoing encoded
    /// video so it appears upright to the remote party. Can be called at any time,
    /// including mid-call, since PJSIP forwards the setting to the live device.
    func setVideoOrientation(_ orientation: VideoOrientation) throws {
        currentOrientation = orientation
        try ensurePjsuaRunning()

        let devices = captureDeviceIds()
        guard currentCaptureDeviceIndex < devices.count else {
            logger.warning("setVideoOrientation: no active capture device")
            return
        }
        let deviceId = devices[currentCaptureDeviceIndex]
        let frontFacing = isFrontFacing(deviceId)
        let pjOrient = pjmediaOrient(for: orientation, isFrontFacing: frontFacing)

        // TEMP: calibration logging — remove once the mapping is confirmed on-device.
        logger.debug("setVideoOrientation: orientation=\(orientation), isFrontFacing=\(frontFacing), pjOrient=\(pjOrient.rawValue), deviceId=\(deviceId)")

        var orient = pjmedia_orient(rawValue: pjOrient.rawValue)
        let status = pjsua_vid_dev_set_setting(
            deviceId,
            PJMEDIA_VID_DEV_CAP_ORIENTATION,
            &orient,
            pj_bool_t(PJ_TRUE.rawValue)
        )
        guard status == PJ_SUCCESS.rawValue else {
            logger.warning("setVideoOrientation: failed to set orientation, status = \(status.description)")
            throw CallError.sipError(message: status.description)
        }
    }


    /// Re-applies the last orientation, e.g. after the capture device was (re)opened.
    func reapplyOrientation() {
        try? setVideoOrientation(currentOrientation)
    }


    /// No dedicated "facing" field exists in `pjmedia_vid_dev_info` — inferred from
    /// the device name (PJSIP's iOS backend names capture devices e.g. "Front"/"Back").
    /// Defaults to front-facing (typical for video calls) if the name is inconclusive.
    private func isFrontFacing(_ deviceId: pjmedia_vid_dev_index) -> Bool {
        var info = pjmedia_vid_dev_info()
        guard pjmedia_vid_dev_get_info(deviceId, &info) == PJ_SUCCESS.rawValue else { return true }
        if deviceName(from: info).localizedCaseInsensitiveContains("back") { return false }
        return true
    }


    /// Maps a physical device orientation to the `pjmedia_orient` value that makes
    /// the captured video appear upright, both in the local preview and to the
    /// remote party. Front- and back-facing sensors are mounted mirrored relative
    /// to each other along the horizontal axis, so the front/back rotation swaps
    /// only for landscape orientations — portrait/portraitUpsideDown use the same
    /// value regardless of which camera is active.
    private func pjmediaOrient(for orientation: VideoOrientation, isFrontFacing: Bool) -> pjmedia_orient {
        switch orientation {
        case .portrait:
            return PJMEDIA_ORIENT_ROTATE_90DEG
        case .portraitUpsideDown:
            return PJMEDIA_ORIENT_ROTATE_270DEG
        case .landscapeLeft:
            return isFrontFacing ? PJMEDIA_ORIENT_ROTATE_180DEG : PJMEDIA_ORIENT_NATURAL
        case .landscapeRight:
            return isFrontFacing ? PJMEDIA_ORIENT_NATURAL : PJMEDIA_ORIENT_ROTATE_180DEG
        }
    }


    /// Finds a registered render device other than PJSIP's default "Metal
    /// [Apple]" one (see the Metal-renderer note in `SipEndpointConfigurator.configureAccount`).
    /// PJSIP registers capture and render devices in one flat list,
    /// distinguished only by the `dir` bitmask and `name`.
    func nonMetalRenderDevice() -> (id: pjmedia_vid_dev_index, name: String)? {
        var maxCount: UInt32 = 32
        var infos = [pjmedia_vid_dev_info](repeating: pjmedia_vid_dev_info(), count: Int(maxCount))
        var count = maxCount

        let status = infos.withUnsafeMutableBufferPointer { buf -> pj_status_t in
            guard let base = buf.baseAddress else { return PJ_EINVAL }
            return pjsua_vid_enum_devs(base, &count)
        }

        guard status == PJ_SUCCESS.rawValue else {
            logger.warning("nonMetalRenderDevice: pjsua_vid_enum_devs failed, status = \(status.description)")
            return nil
        }

        for info in infos.prefix(Int(count)) {
            guard (info.dir.rawValue & PJMEDIA_DIR_RENDER.rawValue) != 0 else { continue }
            let name = deviceName(from: info)
            // The actual runtime `driver` value PJSIP reports for the Metal render
            // factory on this build is "Apple" (confirmed via device logs), not the
            // literal "metal-dev" this function used to check for — so the old
            // `driver != "metal-dev"` filter never matched anything and this always
            // silently re-selected the Metal device itself while logging false
            // success. Match on `name` instead, which the native render-open log
            // confirms literally contains "Metal" ("Opening device Metal [Apple]
            // for render") only for the device we actually need to exclude.
            guard !name.isEmpty, !name.localizedCaseInsensitiveContains("metal") else { continue }
            return (info.id, name)
        }

        return nil
    }
}
