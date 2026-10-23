# Webitel Voice SDK for iOS

Voice and video calling for iOS apps on top of the Webitel platform.

- Outgoing and incoming (VoIP push) calls
- Audio and video
- Call control: mute, hold, DTMF, speakerphone, camera
- Call state and media events

## Requirements

- iOS 13+, Swift 5.9
- `NSMicrophoneUsageDescription` in Info.plist (`NSCameraUsageDescription` for video calls)

## Installation

Swift Package Manager — in Xcode choose **File → Add Packages…** and enter:

```
https://github.com/webitel/voice-sdk-ios.git
```

## Getting Started

Create a `VoiceClient`:

```swift
let voiceClient = VoiceClientFactory.create(
    baseURL: URL(string: "https://demo.webitel.com")!,
    authMethod: .contact(
        identity: ContactIdentity(
            sub: "user-123",
            iss: "https://demo.webitel.com/portal",
            name: "John Smith"
        )
    )
) { config in
    config.clientToken = "PORTAL_CLIENT_TOKEN"
    config.logLevel = .debug
}
```

To authenticate with a JWT instead, pass a provider — the SDK reads the current token when it needs one:

```swift
authMethod: .token(tokenProvider: { "your-jwt-token" })
```

Other `VoiceClientConfiguration` options: `deviceId`, `pinnedPublicKeys`, `incomingCallTimeout`, `logHandler`.

## Making a Call

```swift
let call = voiceClient.makeCall(observer: self)  // audio
```

## Observing a Call

Call state and media changes arrive as `CallEvent`s. `onEvent` is called on an internal SDK queue, so dispatch UI work to the main queue:

```swift
extension CallViewController: CallObserver {
    func onEvent(_ event: CallEvent) {
        DispatchQueue.main.async {
            switch event {
            case .connection(.stateChanged(_, let state)):
                if case .disconnected(let reason) = state {
                    print("Call ended: \(reason.type) — \(reason.message)")
                }
            case .video(.remoteViewReady(_, let view)):
                self.remoteVideoContainer.addSubview(view)
            default:
                break
            }
        }
    }
}
```

## Incoming Calls

Incoming calls arrive as VoIP pushes (PushKit). Register the push token:

```swift
func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    voiceClient.registerPushToken(credentials.token) { result in
        if case .failure(let error) = result { print("Push token error: \(error)") }
    }
}
```

Pass the push payload to the SDK — it returns the incoming `Call` right away:

```swift
func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                  for type: PKPushType, completion: @escaping () -> Void) {
    do {
        let call = try voiceClient.handleIncomingPush(payload.dictionaryPayload, observer: self)
        print("Incoming call from \(call.remoteName ?? "")")
    } catch {
        print("Invalid push: \(error)")
    }
    completion()
}
```

Then call `call.answer()` or `call.disconnect()` to decline. If the SIP INVITE doesn't arrive within `incomingCallTimeout` (15 s by default), the call ends with `.requestTimeout`.

## Call Controls

All controls are throwing methods; they fail with `CallError.invalidState` if the call is in the wrong state.

```swift
do {
    try call.mute(true)              // false to unmute
    try call.hold(true)              // false to resume
    try call.sendDTMF("1")
    try call.setSpeakerphoneOn(true)
    try call.disconnect()
} catch {
    print("Call control error: \(error)")
}
```
