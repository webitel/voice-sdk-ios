//
//  ConnectionQualityMonitor.swift
//  VoiceSDK
//

import Foundation


/// Cumulative RTCP counters of one media stream, copied out of `pjsua_stream_stat`.
///
/// - `rxPkt`: packets received from the server.
/// - `rxLoss`: packets from the server lost on the way to us.
/// - `txPkt`: packets sent to the server.
/// - `txLoss`: our packets the server reported lost (RTCP receiver reports).
/// - `txReports`: number of RTCP receiver reports received so far (~1 per 5 s); `txLoss` and
///   `rttMs` only change when it does. Stays 0 if the server doesn't send RTCP.
/// - `rttMs`: last round-trip time in milliseconds; 0 until measured.
struct SipStreamStat: Equatable {
    let rxPkt: Int64
    let rxLoss: Int64
    let txPkt: Int64
    let txLoss: Int64
    let txReports: Int64
    let rttMs: Int
}


/// Turns successive cumulative RTCP counters into a `ConnectionQuality`. Pure logic, no
/// threading: feed it samples with `onSample`. Mirrors the Android SDK's evaluator.
///
/// Loss is the worse of two directions:
///  - incoming — computed per sample from the gaps in RTP sequence numbers PJSIP sees;
///  - outgoing — known only from the server's RTCP receiver reports (~1 per 5 s), so it is
///    computed between two reports, and the last value is kept until the next one.
///    Computing it per sample instead would overstate it when a report arrives and read 0
///    in between.
///
/// A new value is published only after `confirmSamples` consecutive samples agree, so a
/// single bad interval doesn't make the quality flicker.
struct ConnectionQualityEvaluator {

    static let goodMaxLossPercent = 3.0
    static let goodMaxRttMs = 300
    static let badMinLossPercent = 10.0
    static let badMinRttMs = 700

    private let confirmSamples: Int

    private(set) var current: ConnectionQuality = .unknown

    private var previous: SipStreamStat?
    /// Counters at the last receiver report, the start of the next outgoing-loss window.
    private var lastReport: SipStreamStat?
    private var txLossPercent = 0.0

    private var candidate: ConnectionQuality?
    private var candidateCount = 0


    init(confirmSamples: Int = 2) {
        self.confirmSamples = confirmSamples
    }


    /// Forgets the baseline, e.g. after a hold; the next sample only becomes the new baseline.
    mutating func reset() {
        previous = nil
        lastReport = nil
        txLossPercent = 0
        candidate = nil
        candidateCount = 0
    }


    /// Forgets everything, including `current`.
    mutating func clear() {
        reset()
        current = .unknown
    }


    /// - Parameter expectsIncomingMedia: false when the remote party may legitimately send
    ///   nothing (e.g. it muted itself), so silence isn't treated as a dead connection.
    /// - Returns: the new quality if it changed, or `nil`.
    mutating func onSample(_ stat: SipStreamStat, expectsIncomingMedia: Bool = true) -> ConnectionQuality? {
        guard let prev = previous else {
            previous = stat
            lastReport = stat
            return nil
        }
        previous = stat

        // Counters went backwards: the stream was recreated (re-INVITE). Use as a new baseline.
        if stat.rxPkt < prev.rxPkt || stat.rxLoss < prev.rxLoss ||
            stat.txPkt < prev.txPkt || stat.txLoss < prev.txLoss || stat.txReports < prev.txReports {
            reset()
            previous = stat
            lastReport = stat
            return nil
        }

        let rxPkt = stat.rxPkt - prev.rxPkt
        let rxLoss = stat.rxLoss - prev.rxLoss
        updateTxLoss(stat)

        let lossPercent = max(Self.percent(rxLoss, of: rxPkt + rxLoss), txLossPercent)
        let noIncomingMedia = expectsIncomingMedia && rxPkt == 0
        let sample = Self.classify(lossPercent: lossPercent, rttMs: stat.rttMs, noIncomingMedia: noIncomingMedia)

        if sample == current {
            candidate = nil
            candidateCount = 0
            return nil
        }
        if sample == candidate {
            candidateCount += 1
        } else {
            candidate = sample
            candidateCount = 1
        }
        guard candidateCount >= confirmSamples else { return nil }

        current = sample
        candidate = nil
        candidateCount = 0
        return sample
    }


    /// Recomputes the outgoing loss when a new receiver report arrived since `lastReport`.
    private mutating func updateTxLoss(_ stat: SipStreamStat) {
        guard let report = lastReport else {
            lastReport = stat
            return
        }
        guard stat.txReports != report.txReports else { return }
        txLossPercent = Self.percent(stat.txLoss - report.txLoss, of: stat.txPkt - report.txPkt)
        lastReport = stat
    }


    static func classify(lossPercent: Double, rttMs: Int, noIncomingMedia: Bool) -> ConnectionQuality {
        if noIncomingMedia || lossPercent > badMinLossPercent || rttMs > badMinRttMs {
            return .bad
        }
        if lossPercent < goodMaxLossPercent && rttMs < goodMaxRttMs {
            return .good
        }
        return .medium
    }


    private static func percent(_ part: Int64, of total: Int64) -> Double {
        guard total > 0 else { return 0 }
        return min(Double(part) * 100 / Double(total), 100)
    }
}


/// What `ConnectionQualityMonitor` needs from its call. Called on `SDKQueues.sip` only.
protocol ConnectionQualityMonitorHost: AnyObject {
    /// Current counters, or `nil` if the call has no active audio stream.
    func readStreamStat() -> SipStreamStat?

    /// True once the call ended; the monitor then stops by itself.
    var isQualityMonitorEnded: Bool { get }

    /// True while sampling makes no sense, e.g. on hold.
    var isQualityMonitorPaused: Bool { get }

    /// False when the remote party may send no media (e.g. it muted itself).
    var expectsIncomingMedia: Bool { get }

    func onConnectionQualityChanged(_ quality: ConnectionQuality)
}


/// Periodically samples a call's audio RTCP statistics on `SDKQueues.sip` and reports
/// `ConnectionQuality` changes. Confined to `SDKQueues.sip`.
///
/// The audio stream is used because every call has one and loss/RTT reflect the same
/// network path as video.
final class ConnectionQualityMonitor {

    static let defaultInterval: TimeInterval = 2

    private weak var host: ConnectionQualityMonitorHost?
    private let interval: TimeInterval
    private var evaluator = ConnectionQualityEvaluator()
    private var task: DispatchWorkItem?

    var current: ConnectionQuality { evaluator.current }


    init(host: ConnectionQualityMonitorHost, interval: TimeInterval = ConnectionQualityMonitor.defaultInterval) {
        self.host = host
        self.interval = interval
    }


    func start() {
        SDKQueues.assertOnSip()
        guard task == nil else { return }
        evaluator.reset()
        schedule()
    }


    /// Stops sampling and resets the quality to `.unknown` without reporting it.
    func stop() {
        SDKQueues.assertOnSip()
        task?.cancel()
        task = nil
        evaluator.clear()
    }


    private func schedule() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let task = self.task, !task.isCancelled else { return }
            guard let host = self.host, !host.isQualityMonitorEnded else {
                self.stop()
                return
            }
            self.sample(host)
            if self.task != nil { self.schedule() }
        }
        task = item
        SDKQueues.sip.asyncAfter(deadline: .now() + interval, execute: item)
    }


    private func sample(_ host: ConnectionQualityMonitorHost) {
        if host.isQualityMonitorPaused {
            evaluator.reset()
            guard evaluator.current != .unknown else { return }
            evaluator.clear()
            host.onConnectionQualityChanged(.unknown)
            return
        }
        guard let stat = host.readStreamStat() else { return }
        if let quality = evaluator.onSample(stat, expectsIncomingMedia: host.expectsIncomingMedia) {
            host.onConnectionQualityChanged(quality)
        }
    }
}
