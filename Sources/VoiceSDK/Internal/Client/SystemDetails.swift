#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif


final class SystemDetails {
    lazy var userAgent: String = createUserAgent()

    
    private func createUserAgent() -> String {
        let agent = "\(appNameAndVersion()) (\(osInfo()); \(device())) \(sdkVersion())"
        return agent.removingNonPrintableASCII()
    }

    
    private func appNameAndVersion() -> String {
        let dict = Bundle.main.infoDictionary
        let version = dict?["CFBundleShortVersionString"] as? String ?? "unknown"
        let name = dict?["CFBundleName"] as? String ?? "app"
        return "\(name)/\(version)"
    }

    
    private func osInfo() -> String {
        #if canImport(UIKit)
        let d = UIDevice.current
        return "\(d.systemName) \(d.systemVersion)"
        #elseif canImport(AppKit)
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #else
        return "Unknown OS"
        #endif
    }

    
    private func device() -> String {
        #if canImport(UIKit)
        return UIDevice.current.model
        #elseif canImport(AppKit)
        return "Mac"
        #else
        return "Unknown Device"
        #endif
    }
    

    private func sdkVersion() -> String {
        "chat-sdk/\(SdkInfo.version)"
    }
}


extension String {
    func removingNonPrintableASCII() -> String {
        return self.filter { $0.isASCII && $0.isPrintable }
    }
}


extension Character {
    var isPrintable: Bool {
        return self.unicodeScalars.allSatisfy { scalar in
            return scalar.value >= 32 && scalar.value <= 126
        }
    }
}


public enum SdkInfo {
    public static let version = "0.2.1"
}
