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
        if isExpired { return "描述文件已过期，App 将无法启动；请重新签名。" }
        guard let daysRemaining else { return "无法读取到期时间。" }
        if daysRemaining <= 2 { return "即将过期（\(daysRemaining) 天），请准备重签。" }
        return "有效（剩余 \(daysRemaining) 天）。"
    }

    /// Parses the plist embedded in the CMS/PKCS#7 mobileprovision payload.
    static func current() -> SigningInfo? {
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
}
