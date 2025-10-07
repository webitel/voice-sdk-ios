# **Webitel Voice SDK – iOS**  
  
## Overview  
  
Webitel Voice SDK provides a simple way to integrate voice calling functionality into your iOS applications.  
  
It offers built-in support for:  
• User authentication  
• Call control (mute, hold, digits, etc.)  
• Real-time audio streaming  
• Call state and event tracking  

---  
  
## Installation

Add the SDK via **Swift Package Manager (SPM)**:
1. Open Xcode → **File → Add Packages…**

2. Enter repository URL:

```
https://github.com/webitel/voice-sdk-ios.git
```
3. Select the version and add it to your project.

---  
  
## 🚀 Getting Started  
  
### Initialize the SDK  
  
Before making calls, initialize the SDK by building a VoiceClient instance:  
```swift  
let voiceClient = VoiceClientBuilder(
    address: "https://demo.webitel.com", 
    token: "PORTAL_CLIENT_TOKEN")
        .logLevel(.debug) // optional
        .build()
```  
> Optional parameters: deviceId, appName, appVersion, user  
  
---  
  
### Authentication  
  
You can authenticate using one of the two supported methods:  
  
**Option 1 – via User Object:**  
```swift  
let user = User(iss: "https://demo.webitel.com/portal", 
    sub: "user-123", name: "John Smith")
    
voiceClient.setUser(user)
```  
  
**Option 2 – via JWT Token:**  
```swift  
// Set JWT globally
voiceClient.setJWT("your-jwt-token")
```  
or
```swift  
// Provide JWT directly when starting the call
voiceClient.makeAudioCall(jwt: "your-jwt-token", listener: self)
```  
> Both options will authorize the user before initiating the call.
---  
  
### Make a Call  
  
```swift  
let call = voiceClient.makeAudioCall(listener: self)
```  
  
  
### Call Controls  
The Swift SDK provides throwing methods to manage active calls.
Success or failure is handled using do / catch.
  
Sending DTMF Tones  
  
```swift  
do {
    try call.sendDTMF("1")
    print("✅ DTMF sent: 1")
} catch {
    print("❌ DTMF error: \(error.localizedDescription)")
}
```
  
Mute / Unmute Microphone  
  
```swift  
do {
    try call.mute(true) // true = mute, false = unmute
    print("✅ Microphone muted")
} catch {
    print("❌ Mute error: \(error.localizedDescription)")
}
```  
  
Hold / Resume Call  
  
```kotlin  
do {
    try call.hold(true) // true = hold, false = resume
    print("✅ Call held")
} catch {
    print("❌ Hold error: \(error.localizedDescription)")
}
```  
  
Disconnect Call  
  
```swift  
do {
    try call.disconnect()
} catch {
    print("❌ Disconnect error: \(error.localizedDescription)")
}
```  
  
