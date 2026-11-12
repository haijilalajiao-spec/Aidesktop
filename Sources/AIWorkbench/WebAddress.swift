import Foundation

enum WebAddress {
    static func parse(_ input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let hasScheme = text.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*://"#, options: .regularExpression) != nil
        let candidate = hasScheme ? text : "https://" + text
        guard let parts = URLComponents(string: candidate),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains("\\"),
              hasScheme || host.contains(".") || host.contains(":") || host.lowercased() == "localhost",
              parts.port.map({ (1...65535).contains($0) }) ?? true else { return nil }
        return parts.url
    }

    static func comparisonKey(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) {
            parts.port = nil
        }
        if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        return parts.string ?? url.absoluteString
    }
}
