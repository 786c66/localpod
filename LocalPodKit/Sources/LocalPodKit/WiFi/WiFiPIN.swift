import Foundation
import Security

/// Generates short numeric PINs for the Wi-Fi upload server. The PIN is only a
/// convenience gate on the local network; the address policy in
/// `WiFiNetworkAddress` is the primary network boundary.
public enum WiFiPIN {
    /// Generates a PIN made only of ASCII digits using `SecRandomCopyBytes`.
    /// Length is clamped to `1...64` to keep the UI and header comparisons sane.
    public static func generate(length: Int = 6) -> String {
        let count = min(max(1, length), 64)
        var digits = [Character]()
        digits.reserveCapacity(count)

        while digits.count < count {
            var byte: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
            if status == errSecSuccess {
                // Rejection sampling keeps the digit distribution uniform:
                // 250 is the largest multiple of ten representable in a byte.
                if byte < 250 {
                    digits.append(Character(String(byte % 10)))
                }
            } else {
                // Apple's system RNG is also a CSPRNG; this only runs if the
                // Security framework call fails unexpectedly.
                digits.append(Character(String(Int.random(in: 0...9))))
            }
        }

        return String(digits)
    }

    /// Compares two PINs without early exit on the first differing byte.
    /// Length is not secret and is compared first.
    static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var difference: UInt8 = 0
        for index in left.indices {
            difference |= left[index] ^ right[index]
        }
        return difference == 0
    }
}

/// Sliding-window failed-PIN limiter keyed by remote host. A host is blocked
/// once it has `maxAttempts` failures inside `window` seconds. A successful
/// authentication clears that host's history.
public final class WiFiPINRateLimiter: @unchecked Sendable {
    public let maxAttempts: Int
    public let window: TimeInterval

    private let clock: @Sendable () -> Date
    private let lock = NSLock()
    private var failures: [String: [Date]] = [:]

    public init(
        maxAttempts: Int = 8,
        window: TimeInterval = 60,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.window = max(1, window)
        self.clock = now
    }

    /// Returns true when the host must receive 429 without its PIN being
    /// checked. Expired failures are pruned as a side effect.
    public func isLimited(host: String, at date: Date? = nil) -> Bool {
        let current = date ?? clock()
        lock.lock()
        defer { lock.unlock() }
        var timestamps = failures[host] ?? []
        prune(&timestamps, relativeTo: current)
        store(timestamps, for: host)
        return timestamps.count >= maxAttempts
    }

    public func recordFailure(host: String, at date: Date? = nil) {
        let current = date ?? clock()
        lock.lock()
        defer { lock.unlock() }
        var timestamps = failures[host] ?? []
        prune(&timestamps, relativeTo: current)
        timestamps.append(current)
        failures[host] = timestamps
    }

    public func recordSuccess(host: String) {
        lock.lock()
        defer { lock.unlock() }
        failures.removeValue(forKey: host)
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        failures.removeAll()
    }

    private func prune(_ timestamps: inout [Date], relativeTo now: Date) {
        let cutoff = now.addingTimeInterval(-window)
        timestamps.removeAll { $0 <= cutoff }
    }

    private func store(_ timestamps: [Date], for host: String) {
        if timestamps.isEmpty {
            failures.removeValue(forKey: host)
        } else {
            failures[host] = timestamps
        }
    }
}
