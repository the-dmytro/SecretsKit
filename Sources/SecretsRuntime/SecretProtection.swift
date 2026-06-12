import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Opt-in, best-effort anti-tamper checks.
///
/// These are **speed bumps only**. A debugger, a jailbreak tweak, or an instrumentation framework
/// such as Frida bypasses them trivially. They must never gate the value of a returned secret —
/// doing so silently turns a real credential into an empty one (the previous `protect(_:)` behavior,
/// now removed). If you want to refuse to run under a debugger, call `isDebuggerAttached()` yourself
/// and handle the result explicitly.
public enum SecretProtection {
    /// Returns `true` if a debugger is currently attached to this process.
    ///
    /// Best-effort and trivially bypassable. Always returns `false` in `DEBUG` builds so local
    /// debugging is unaffected.
    public static func isDebuggerAttached() -> Bool {
        #if DEBUG
        return false
        #elseif os(iOS) || os(tvOS) || os(macOS)
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
