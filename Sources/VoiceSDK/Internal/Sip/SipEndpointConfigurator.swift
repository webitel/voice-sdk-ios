//
//  SipEndpointConfigurator.swift
//  VoiceSDK
//
//  Created by Yurii Zhuk on 22.10.2026.
//

import Foundation
import PJSIPKit


/// Builds pjsua/account configs and sets up transports and codecs from
/// `CallSettings`. Strings handed to PJSIP are kept alive by the caller's `owned`
/// until the corresponding pjsua call returns.
struct SipEndpointConfigurator {
    private let logger = SDKLogger.make("voice.core.sip")
    private let defaultGoogleStunServer = "stun.l.google.com:19302"
    private let PJ_MAX_STUN_SERVERS = 8

    let settings: CallSettings


    /// Configs for `pjsua_init`.
    func makeInitConfigs(
        isVideoEnabled: Bool,
        owned: inout OwnedCStrings
    ) -> (cfg: pjsua_config, logCfg: pjsua_logging_config, mediaCfg: pjsua_media_config) {
        var cfg = pjsua_config()
        var logCfg = pjsua_logging_config()
        var mediaCfg = pjsua_media_config()
        pjsua_config_default(&cfg)
        pjsua_logging_config_default(&logCfg)
        pjsua_media_config_default(&mediaCfg)

        // Logging
    #if DEBUG
        logCfg.msg_logging = pj_bool_t(PJ_TRUE.rawValue)
        logCfg.console_level = 5
        logCfg.level = 5
    #else
        logCfg.msg_logging = pj_bool_t(PJ_FALSE.rawValue)
        logCfg.console_level = 0
        logCfg.level = 0
    #endif

        // Media configuration
        mediaCfg.has_ioqueue = pj_bool_t(PJ_FALSE.rawValue)
        mediaCfg.quality = 5
        mediaCfg.thread_cnt = 1
        mediaCfg.clock_rate = 48000
        mediaCfg.channel_count = 2
        mediaCfg.ec_options = 0
        mediaCfg.ec_tail_len = 0
        mediaCfg.no_vad = pj_bool_t(PJ_TRUE.rawValue)
        mediaCfg.enable_ice = settings.iceEnabled ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)

        // STUN servers
        var stunServers = settings.useDefaultStun ? [defaultGoogleStunServer] : []
        stunServers.append(contentsOf: settings.stunServers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        let count = min(stunServers.count, PJ_MAX_STUN_SERVERS)
        cfg.stun_srv_cnt = UInt32(count)
        if count > 0 {
            withUnsafeMutablePointer(to: &cfg.stun_srv) { ptr in
                let base = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: pj_str_t.self)
                for i in 0..<count {
                    base[i] = owned.pjString(stunServers[i])
                }
            }
        }

        // Callbacks
        cfg.cb.on_call_state = on_call_state
        cfg.cb.on_call_media_state = on_call_media_state
        cfg.cb.on_call_tsx_state = on_call_tsx_state
        cfg.cb.on_incoming_call = on_incoming_call
        cfg.cb.on_reg_state2 = on_reg_state2

        if isVideoEnabled {
            cfg.cb.on_call_media_event = on_call_media_event
        }

        cfg.max_calls = UInt32(VoiceManager.maxCalls)

        // User agent
        cfg.user_agent = owned.pjString("webitel for ios")

        return (cfg, logCfg, mediaCfg)
    }


    func createTransport(forProxy proxy: String) {
        let transport = transportFrom(sipUri: proxy) ?? .TCP_UDP
        createTransport(transport)
    }


    /// Fills an already defaulted `accCfg`. Takes a pointer, not a returned value:
    /// `pjsua_acc_config_default` links `reg_hdr_list`/`sub_hdr_list` to the struct's
    /// own address, so a copy would point at freed memory and crash `pjsua_acc_add`.
    /// `renderDevice` is only used for video calls — see the note below.
    func configureAccount(
        _ accCfg: UnsafeMutablePointer<pjsua_acc_config>,
        config: SipConfig,
        renderDevice: (id: pjmedia_vid_dev_index, name: String)?,
        owned: inout OwnedCStrings
    ) {
        accCfg.pointee.id = owned.pjString("sip:\(config.getExtension())@\(config.getDomain())")

        accCfg.pointee.cred_count = 1
        accCfg.pointee.cred_info.0.username = owned.pjString(config.getAuth())
        accCfg.pointee.cred_info.0.realm = owned.pjString("*")
        accCfg.pointee.cred_info.0.data = owned.pjString(config.getPassword())
        accCfg.pointee.cred_info.0.scheme = owned.pjString("digest")
        accCfg.pointee.cred_info.0.data_type = 0

        // Registration is only needed for incoming calls and is triggered explicitly
        // via `register(sipConfig:completion:)`; outgoing calls never REGISTER.
        accCfg.pointee.reg_uri = owned.pjString(config.getProxy())
        accCfg.pointee.register_on_acc_add = pj_bool_t(PJ_FALSE.rawValue)
        
        accCfg.pointee.allow_contact_rewrite = settings.contactRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.pointee.allow_via_rewrite = settings.viaRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.pointee.allow_sdp_nat_rewrite = settings.sdpNatRewriteUse ? pj_bool_t(PJ_TRUE.rawValue) : pj_bool_t(PJ_FALSE.rawValue)
        accCfg.pointee.use_srtp = getPjsipCode(code: settings.srtpUse)

        if config.isVideoCallEnabled() {
            accCfg.pointee.vid_out_auto_transmit = pj_bool_t(PJ_TRUE.rawValue)
            accCfg.pointee.vid_in_auto_show = pj_bool_t(PJ_TRUE.rawValue)

            // PJSIP's default "Metal [Apple]" render device stops presenting
            // frames after a handful of Stop/Start cycles (which happen often —
            // vid_conf.c recomputes the port's frame rate from incoming RTP
            // timestamps on nearly every frame): CAMetalLayer starts rejecting
            // presents ("Each CAMetalLayerDrawable can only be presented once!")
            // and the picture freezes even though decoding is healthy. PJSIP also
            // registers an OpenGL and a Darwin/UIView renderer; prefer whichever
            // of those is available over Metal.
            if let renderDevice {
                accCfg.pointee.vid_rend_dev = renderDevice.id
                logger.debug("configureAccount: using render device id=\(renderDevice.id), name=\"\(renderDevice.name)\" instead of Metal")
            } else {
                logger.warning("configureAccount: no non-Metal render device found, falling back to default renderer")
            }
        } else {
            accCfg.pointee.vid_out_auto_transmit = pj_bool_t(PJ_FALSE.rawValue)
            accCfg.pointee.vid_in_auto_show = pj_bool_t(PJ_FALSE.rawValue)
        }

        // ICE config
        if settings.iceEnabled {
            accCfg.pointee.ice_cfg_use = PJSUA_ICE_CONFIG_USE_CUSTOM
            accCfg.pointee.ice_cfg.enable_ice = pj_bool_t(PJ_TRUE.rawValue)
            accCfg.pointee.ice_cfg.ice_always_update = pj_bool_t(PJ_TRUE.rawValue)
        }
    }


    func setupVideoCodec(w: UInt32, h: UInt32) {
        // `pjsua_vid_codec_set_param` clones the fmtp strings into the codec manager.
        var owned = OwnedCStrings()
        defer { owned.free() }
        var codecId = owned.pjString("H264/98")
        var param = pjmedia_vid_codec_param()

        guard pjsua_vid_codec_get_param(&codecId, &param) == PJ_SUCCESS.rawValue else {
            logger.warning("setupVideoCodec: failed to get H264 codec param")
            return
        }

        // Mirrors the Android SDK's H264 fmtp config: same profile-level-id and
        // packetization-mode on both the decode and encode side.
        param.dec_fmtp = buildFmtp(Self.h264FmtpParams, owned: &owned)
        param.enc_fmtp = buildFmtp(Self.h264FmtpParams, owned: &owned)

        param.dec_fmt.det.vid.size.w = w
        param.dec_fmt.det.vid.size.h = h
        param.dec_fmt.det.vid.fps.num = 20
        param.dec_fmt.det.vid.fps.denum = 1

        param.enc_fmt.det.vid.size.w = 480
        param.enc_fmt.det.vid.size.h = 640
        param.enc_fmt.det.vid.fps.num = 20
        param.enc_fmt.det.vid.fps.denum = 1

        // Without an explicit bitrate cap the encoder falls back to PJSIP's own default,
        // which can exceed what the network path can sustain and cause continuous
        // congestion-driven packet loss (seen as a steady stream of "Frame lost, recovered!"
        // on the receiving end's jitter buffer, not a one-off burst). These values are a
        // sane starting point for 480x640@15fps H.264 and may need tuning per deployment.
        param.enc_fmt.det.vid.avg_bps = 300_000
        param.enc_fmt.det.vid.max_bps = 800_000

        let status = pjsua_vid_codec_set_param(&codecId, &param)
        if status != PJ_SUCCESS.rawValue {
            logger.warning("setupVideoCodec: failed to set H264 codec param, status = \(status.description)")
        }
    }


    // Mirrors the Android SDK's H264 codec fmtp setup.
    private static let h264FmtpParams: [(name: String, value: String)] = [
        ("profile-level-id", "42e01f"),
        ("packetization-mode", "1"),
    ]

    private func buildFmtp(_ entries: [(name: String, value: String)], owned: inout OwnedCStrings) -> pjmedia_codec_fmtp {
        var fmtp = pjmedia_codec_fmtp()
        for (i, entry) in entries.enumerated() {
            guard i < 16 else { break }
            let name = owned.pjString(entry.name)
            let value = owned.pjString(entry.value)
            switch i {
            case 0: fmtp.param.0.name = name; fmtp.param.0.val = value
            case 1: fmtp.param.1.name = name; fmtp.param.1.val = value
            case 2: fmtp.param.2.name = name; fmtp.param.2.val = value
            case 3: fmtp.param.3.name = name; fmtp.param.3.val = value
            case 4: fmtp.param.4.name = name; fmtp.param.4.val = value
            case 5: fmtp.param.5.name = name; fmtp.param.5.val = value
            case 6: fmtp.param.6.name = name; fmtp.param.6.val = value
            case 7: fmtp.param.7.name = name; fmtp.param.7.val = value
            case 8: fmtp.param.8.name = name; fmtp.param.8.val = value
            case 9: fmtp.param.9.name = name; fmtp.param.9.val = value
            case 10: fmtp.param.10.name = name; fmtp.param.10.val = value
            case 11: fmtp.param.11.name = name; fmtp.param.11.val = value
            case 12: fmtp.param.12.name = name; fmtp.param.12.val = value
            case 13: fmtp.param.13.name = name; fmtp.param.13.val = value
            case 14: fmtp.param.14.name = name; fmtp.param.14.val = value
            case 15: fmtp.param.15.name = name; fmtp.param.15.val = value
            default: break
            }
        }
        fmtp.cnt = pj_uint8_t(min(entries.count, 16))
        return fmtp
    }


    func setCodecPriority() {
        let codecs = [
            "opus/48000/2": PJMEDIA_CODEC_PRIO_HIGHEST.rawValue,
            "G722/16000/1": 135,
            "PCMU/8000/1": 133,
            "PCMA/8000/1": PJMEDIA_CODEC_PRIO_NORMAL.rawValue,
            "speex/16000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "speex/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "speex/32000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "iLBC/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue,
            "GSM/8000/1": PJMEDIA_CODEC_PRIO_DISABLED.rawValue
        ]
        var codec = pj_str_t()
        for (name, prio) in codecs {
            pjsua_codec_set_priority(pj_cstr(&codec, name), pj_uint8_t(prio))
        }
    }


    private func createTransport(_ transport: Transport) {
        logger.debug("Create transport: \(transport)")
        switch transport {
            case .UDP: initTransport(type: PJSIP_TRANSPORT_UDP)
            case .TCP: initTransport(type: PJSIP_TRANSPORT_TCP)
            case .TLS: initTransport(type: PJSIP_TRANSPORT_TLS)
            case .TCP_UDP: initTransport(type: PJSIP_TRANSPORT_TCP); initTransport(type: PJSIP_TRANSPORT_UDP)
        }
    }
    

    private func initTransport(type: pjsip_transport_type_e) {
        pj_activesock_enable_iphone_os_bg(pj_bool_t(PJ_FALSE.rawValue))
        var transportId = pjsua_transport_id()
        var cfg = pjsua_transport_config()
        pjsua_transport_config_default(&cfg)
        //cfg.qos_type = PJ_QOS_TYPE_VIDEO
     //   cfg. = 300; // 5 min
        let status = pjsua_transport_create(type, &cfg, &transportId)
        if status != PJ_SUCCESS.rawValue {
            logger.warning("Transport \(type) not created")
        }
    }
    

    private func transportFrom(sipUri: String) -> Transport? {
        let components = sipUri.split(separator: ";")
        for comp in components {
            let pair = comp.split(separator: "=")
            if pair.count == 2, pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "transport" {
                switch pair[1].trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                    case "tcp": return .TCP
                    case "udp": return .UDP
                    case "tls": return .TLS
                    default: return nil
                }
            }
        }
        return nil
    }


    private func getPjsipCode(code: SrtpUse) -> pjmedia_srtp_use {
        switch code {
            case .PJMEDIA_SRTP_OPTIONAL: return PJMEDIA_SRTP_OPTIONAL
            case .PJMEDIA_SRTP_MANDATORY: return PJMEDIA_SRTP_MANDATORY
            default: return PJMEDIA_SRTP_DISABLED
        }
    }
}
