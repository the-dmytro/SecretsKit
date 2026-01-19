import Foundation
#if canImport(Darwin)
import Darwin
#endif

public enum SecretProtection {
    public static func protect(_ value: String) -> String {
        if isDebugging() || isHooked() {
            return ""
        }
        return value
    }

    private static func isDebugging() -> Bool {
        #if DEBUG
        return false
        #else
        return debuggingFlag()
        #endif
    }

    private static func isHooked() -> Bool {
        #if DEBUG
        return false
        #else
        return false
        #endif
    }

    private static func debuggingFlag() -> Bool {
        #if os(iOS) || os(tvOS) || os(macOS)
        var info = kinfo_proc()
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        if result == 0 {
            return (info.kp_proc.p_flag & P_TRACED) != 0
        }
        return false
        #else
        return false
        #endif
    }
}
