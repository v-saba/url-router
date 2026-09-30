import Foundation

/// How a rule's `match` string is interpreted.
enum MatchType: String, Codable, CaseIterable, Identifiable {
    case domain   // host equals value, or is a subdomain of it (a leading "*." is also accepted)
    case glob     // shell-style wildcard (fnmatch) tested against the full URL
    case regex    // regular expression tested against the full URL

    var id: String { rawValue }
}

/// Whether a routed URL opens in a new tab or a new window (for browsers that support it).
enum OpenMode: String, Codable, CaseIterable, Identifiable {
    case newTab = "tab"
    case newWindow = "window"

    var id: String { rawValue }
    var label: String { self == .newTab ? "New tab" : "New window" }
}

/// A single routing rule. The first rule (top to bottom) that matches a URL wins.
struct Rule: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var match: String
    var type: MatchType
    /// Firefox profile name (from profiles.ini `Name=`). nil → use the app's default profile.
    var profile: String?
    /// Path to a `.app` (or executable) to open with. nil → use the global `default_app` (Firefox).
    var app: String?
    /// New tab vs new window. nil → use the global `default_open_mode`.
    var openMode: OpenMode?

    enum CodingKeys: String, CodingKey {
        case name, match, type, profile, app
        case openMode = "open"
    }

    init(id: UUID = UUID(), name: String, match: String, type: MatchType,
         profile: String? = nil, app: String? = nil, openMode: OpenMode? = nil) {
        self.id = id
        self.name = name
        self.match = match
        self.type = type
        self.profile = profile
        self.app = app
        self.openMode = openMode
    }

    // Lenient decoder: tolerate hand-edited YAML that omits `type` (defaults to domain).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        self.match = try c.decode(String.self, forKey: .match)
        self.type = try c.decodeIfPresent(MatchType.self, forKey: .type) ?? .domain
        self.profile = try c.decodeIfPresent(String.self, forKey: .profile)
        self.app = try c.decodeIfPresent(String.self, forKey: .app)
        self.openMode = try c.decodeIfPresent(OpenMode.self, forKey: .openMode)
    }
}

/// Top-level config, persisted as YAML.
struct AppConfig: Codable, Equatable {
    /// Default browser app bundle used when a rule (or the fallback) doesn't specify one.
    var defaultApp: String?
    /// Default Firefox profile used when a rule doesn't specify one.
    var defaultProfile: String?
    /// Default new tab vs new window, used when a rule doesn't specify one.
    var defaultOpenMode: OpenMode?
    var rules: [Rule]

    enum CodingKeys: String, CodingKey {
        case defaultApp = "default_app"
        case defaultProfile = "default_profile"
        case defaultOpenMode = "default_open_mode"
        case rules
    }

    static let firefoxPath = "/Applications/Firefox.app"

    /// The app to use when nothing else is specified.
    var resolvedDefaultApp: String { defaultApp ?? AppConfig.firefoxPath }
    /// The open mode to use when nothing else is specified.
    var resolvedDefaultOpenMode: OpenMode { defaultOpenMode ?? .newTab }
}

/// The concrete launch decision produced by the rule engine.
struct RouteDecision {
    var app: String
    var profile: String?
    var openMode: OpenMode
    /// The rule that matched, or nil if the fallback default was used.
    var matchedRule: Rule?
}
