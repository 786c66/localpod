import Foundation

struct SigningInfo {
    let name: String?
    let teamIdentifier: String?
    let appIdentifier: String?
    let expirationDate: Date?
    let provisionedDeviceCount: Int?

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        let calendar = Calendar.current
        return calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: Date()),
            to: calendar.startOfDay(for: expirationDate)
        ).day
    }

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var statusText: String {
        if isExpired {
            return L10n.string("signing.status.expired")
        }
        guard let daysRemaining else {
            return L10n.string("signing.status.unknownExpiry")
        }
        if daysRemaining <= 2 {
            return L10n.format("signing.status.expiringSoon", daysRemaining)
        }
        return L10n.format("signing.status.valid", daysRemaining)
    }

    /// Parses the plist embedded in the CMS/PKCS#7 mobileprovision payload.
    static func current() -> SigningInfo? {
        #if DEBUG
        if let fake = debugFakeSigningInfo() {
            return fake
        }
        #endif
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        let xmlStart = Data("<?xml".utf8)
        let xmlEnd = Data("</plist>".utf8)
        guard let startRange = data.range(of: xmlStart),
              let endRange = data.range(
                of: xmlEnd,
                options: [],
                in: startRange.lowerBound..<data.count
              ) else {
            return nil
        }
        let plistData = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let plist = try? PropertyListSerialization.propertyList(
            from: plistData,
            options: [],
            format: nil
        ) as? [String: Any] else {
            return nil
        }

        let entitlements = plist["Entitlements"] as? [String: Any]
        return SigningInfo(
            name: plist["Name"] as? String,
            teamIdentifier: (plist["TeamIdentifier"] as? [String])?.first,
            appIdentifier: entitlements?["application-identifier"] as? String,
            expirationDate: plist["ExpirationDate"] as? Date,
            provisionedDeviceCount: (plist["ProvisionedDevices"] as? [String])?.count
        )
    }

    #if DEBUG
    /// UI tests run on the simulator, which has no embedded profile. This
    /// launch-only seam injects a profile expiry without affecting Release
    /// builds. It must never be used by app logic outside diagnostics.
    private static func debugFakeSigningInfo() -> SigningInfo? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flagIndex = arguments.firstIndex(of: "--m5-fake-signing-expiry-days"),
              arguments.indices.contains(flagIndex + 1),
              let days = Int(arguments[flagIndex + 1]) else {
            return nil
        }

        let calendar = Calendar.current
        let expirationDate = calendar.date(
            byAdding: .day,
            value: days,
            to: Date()
        )
        return SigningInfo(
            name: "UI 测试描述文件",
            teamIdentifier: "UITESTTEAM",
            appIdentifier: "UITEST.com.localpod.app",
            expirationDate: expirationDate,
            provisionedDeviceCount: 1
        )
    }
    #endif
}
