import Foundation

public enum PathSanitizer {
    /// Turns a provider-supplied relative path into a path made of safe single
    /// path components. Traversal, empty components and separators are removed.
    public static func sanitizeRelativePath(_ path: String) -> String {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        let safe = components.map { component -> String in
            var value = String(component)
            value = value.replacingOccurrences(of: "\0", with: "")
            value = value.replacingOccurrences(of: "/", with: "_")
            value = value.replacingOccurrences(of: ":", with: "_")
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty || value == "." || value == ".." {
                value = "_"
            }
            return value
        }
        return safe.isEmpty ? "untitled" : safe.joined(separator: "/")
    }
}
