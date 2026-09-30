import Foundation
import Yams

/// Loads and saves the YAML rules database at ~/.config/url-router/config.yaml.
final class ConfigStore {
    static let shared = ConfigStore()

    let directoryURL: URL
    let fileURL: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        directoryURL = home.appendingPathComponent(".config/url-router", isDirectory: true)
        fileURL = directoryURL.appendingPathComponent("config.yaml")
    }

    /// Loads config, creating a commented default file on first run.
    func load() -> AppConfig {
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            seedDefault()
        }
        do {
            let text = try String(contentsOf: fileURL, encoding: .utf8)
            return try YAMLDecoder().decode(AppConfig.self, from: text)
        } catch {
            FileHandle.standardError.write(
                Data("URLRouter: config load error: \(error)\n".utf8))
            return AppConfig(defaultApp: AppConfig.firefoxPath, defaultProfile: nil, rules: [])
        }
    }

    func save(_ config: AppConfig) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = YAMLEncoder()
        encoder.options.sortKeys = false
        let yaml = try encoder.encode(config)
        try yaml.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    /// Writes a friendly, commented starter config seeded with detected Firefox profiles.
    private func seedDefault() {
        let defaultProfile = FirefoxProfiles.primaryName() ?? "default-release"
        let template = """
        # URL Router config
        # Rules are evaluated top to bottom; the first match wins.
        # match types:
        #   domain  host equals value or is a subdomain (e.g. github.com matches gist.github.com)
        #   glob    shell wildcard against the full URL (e.g. https://*.work.com/*)
        #   regex   regular expression against the full URL
        # `profile` is a Firefox profile name (as shown in Firefox's profile manager
        # / about:profiles, e.g. "Original profile"). Omit to use default_profile.
        # `app` overrides the browser for that rule. Omit to use default_app.
        # `open` is tab or window (Firefox/Chromium only; Safari ignores it).

        default_app: \(AppConfig.firefoxPath)
        default_profile: \(defaultProfile)
        default_open_mode: tab

        rules:
          - name: Example - GitHub in default profile
            type: domain
            match: github.com
            profile: \(defaultProfile)
        """
        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try template.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            FileHandle.standardError.write(
                Data("URLRouter: could not write default config: \(error)\n".utf8))
        }
    }
}
