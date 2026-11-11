import Foundation
import Network

/// Network address policy for the local-only upload server.
///
/// The server must never be reachable from a public address. Loopback is
/// allowed so the server can be exercised by unit tests and by an app running
/// on the same device. RFC 1918, link-local, IPv6 ULA and IPv6 link-local
/// addresses are allowed because they are the addresses a phone gets on a home
/// or hotspot LAN.
public enum WiFiNetworkAddress {
    // MARK: Policy

    public static func isAllowedRemote(_ rawHost: String) -> Bool {
        let host = normalize(rawHost)
        guard !host.isEmpty else { return false }
        if host.caseInsensitiveCompare("localhost") == .orderedSame {
            return true
        }
        if parseIPv4(host) != nil {
            return isAllowedRemoteIPv4(host)
        }
        return isAllowedRemoteIPv6(host)
    }

    public static func isAllowedRemoteIPv4(_ rawHost: String) -> Bool {
        let host = normalize(rawHost)
        guard let octets = parseIPv4(host) else { return false }
        switch octets[0] {
        case 10:
            return true
        case 127:
            return true
        case 169:
            return octets[1] == 254
        case 172:
            return (16...31).contains(octets[1])
        case 192:
            return octets[1] == 168
        default:
            return false
        }
    }

    public static func isAllowedRemoteIPv6(_ rawHost: String) -> Bool {
        let host = normalize(rawHost)
        guard let bytes = parseIPv6(host), bytes.count == 16 else { return false }

        // IPv4-mapped IPv6 (::ffff:a.b.c.d) follows the IPv4 policy.
        if bytes[0..<10].allSatisfy({ $0 == 0 }),
           bytes[10] == 0xFF,
           bytes[11] == 0xFF {
            let octets = Array(bytes[12..<16])
            return isAllowedRemoteIPv4(octets.map(String.init).joined(separator: "."))
        }

        // ::1
        if bytes[0..<15].allSatisfy({ $0 == 0 }), bytes[15] == 1 {
            return true
        }

        // fc00::/7 (unique local)
        if bytes[0] & 0xFE == 0xFC {
            return true
        }

        // fe80::/10 (link-local)
        if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 {
            return true
        }

        return false
    }

    public static func isLoopbackIPv4(_ rawHost: String) -> Bool {
        guard let octets = parseIPv4(normalize(rawHost)) else { return false }
        return octets[0] == 127
    }

    /// RFC 1918 plus IPv4 link-local (169.254/16).
    public static func isPrivateIPv4(_ rawHost: String) -> Bool {
        guard let octets = parseIPv4(normalize(rawHost)) else { return false }
        return octets[0] == 10
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }

    // MARK: Local addresses

    /// Non-loopback IPv4 addresses that the policy would accept, with `en0`
    /// first. Returns `127.0.0.1` when no LAN address is available (for
    /// example in a simulator) so the server remains usable/testable.
    public static func localIPv4Addresses() -> [String] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else {
            return ["127.0.0.1"]
        }
        defer { freeifaddrs(ifaddr) }

        struct Candidate {
            let interface: String
            let address: String
        }

        var candidates: [Candidate] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            let flags = Int32(current.pointee.ifa_flags)
            let isUp = flags & IFF_UP != 0
            let isLoopback = flags & IFF_LOOPBACK != 0

            if isUp, !isLoopback, let address = current.pointee.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(address.pointee.sa_len)
                let result = host.withUnsafeMutableBufferPointer { buffer in
                    getnameinfo(
                        address,
                        length,
                        buffer.baseAddress,
                        socklen_t(buffer.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    )
                }
                if result == 0 {
                    let name = String(cString: current.pointee.ifa_name)
                    let value = string(fromCStringBuffer: host)
                    if isAllowedRemoteIPv4(value) {
                        candidates.append(Candidate(interface: name, address: value))
                    }
                }
            }

            pointer = current.pointee.ifa_next
        }

        candidates.sort { lhs, rhs in
            if lhs.interface == "en0" && rhs.interface != "en0" { return true }
            if rhs.interface == "en0" && lhs.interface != "en0" { return false }
            if lhs.interface != rhs.interface { return lhs.interface < rhs.interface }
            return lhs.address < rhs.address
        }

        var seen = Set<String>()
        var addresses: [String] = []
        for candidate in candidates where seen.insert(candidate.address).inserted {
            addresses.append(candidate.address)
        }
        return addresses.isEmpty ? ["127.0.0.1"] : addresses
    }

    // MARK: Endpoint conversion

    /// Converts a Network.framework host into a textual address suitable for
    /// the policy checks above. Names are returned unchanged; the server only
    /// accepts a name when it is `localhost`.
    public static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let address):
            let bytes = Array(address.rawValue)
            guard bytes.count == 4 else { return "" }
            return bytes.map(String.init).joined(separator: ".")
        case .ipv6(let address):
            let bytes = Array(address.rawValue)
            guard bytes.count == 16 else { return "" }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            let result = address.rawValue.withUnsafeBytes { raw in
                inet_ntop(
                    AF_INET6,
                    raw.baseAddress,
                    &buffer,
                    socklen_t(buffer.count)
                )
            }
            guard result != nil else { return "" }
            return string(fromCStringBuffer: buffer)
        case .name(let name, _):
            return name
        @unknown default:
            return ""
        }
    }

    // MARK: Parsing

    private static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("["), value.hasSuffix("]"), value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        // Drop an IPv6 zone identifier (fe80::1%en0); it does not change the
        // address policy.
        if let percent = value.firstIndex(of: "%") {
            value = String(value[..<percent])
        }
        return value
    }

    private static func parseIPv4(_ host: String) -> [UInt8]? {
        var address = in_addr()
        let converted = host.withCString { pointer in
            inet_pton(AF_INET, pointer, &address)
        }
        guard converted == 1 else { return nil }
        let value = UInt32(bigEndian: address.s_addr)
        return [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
    }

    private static func parseIPv6(_ host: String) -> [UInt8]? {
        var address = in6_addr()
        let converted = host.withCString { pointer in
            inet_pton(AF_INET6, pointer, &address)
        }
        guard converted == 1 else { return nil }
        return withUnsafeBytes(of: &address) { Array($0) }
    }

    private static func string(fromCStringBuffer buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
