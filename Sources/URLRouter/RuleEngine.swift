import Foundation

enum RuleEngine {
    /// Returns the launch decision for a URL: the first matching rule, or the global default.
    static func decide(url: URL, config: AppConfig) -> RouteDecision {
        for rule in config.rules where matches(rule: rule, url: url) {
            return RouteDecision(
                app: rule.app ?? config.resolvedDefaultApp,
                profile: rule.profile ?? config.defaultProfile,
                openMode: rule.openMode ?? config.resolvedDefaultOpenMode,
                matchedRule: rule
            )
        }
        return RouteDecision(
            app: config.resolvedDefaultApp,
            profile: config.defaultProfile,
            openMode: config.resolvedDefaultOpenMode,
            matchedRule: nil
        )
    }

    static func matches(rule: Rule, url: URL) -> Bool {
        switch rule.type {
        case .domain:
            return matchesDomain(pattern: rule.match, host: url.host)
        case .glob:
            return fnmatch(rule.match, url.absoluteString, 0) == 0
        case .regex:
            guard let re = try? NSRegularExpression(pattern: rule.match) else { return false }
            let s = url.absoluteString
            return re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
        }
    }

    private static func matchesDomain(pattern rawPattern: String, host rawHost: String?) -> Bool {
        guard let host = rawHost?.lowercased(), !host.isEmpty else { return false }
        var pattern = rawPattern.lowercased()
        if pattern.hasPrefix("*.") {
            pattern = String(pattern.dropFirst(2))
        }
        return host == pattern || host.hasSuffix("." + pattern)
    }
}
