import Foundation
import SQLite3

struct FirefoxProfile: Identifiable, Hashable {
    var name: String
    var relativePath: String
    var absolutePath: String
    /// The profile Firefox would launch by default.
    var isPrimary: Bool
    var id: String { absolutePath }
}

/// Resolves the user's Firefox profiles.
///
/// Firefox 151+ keeps the user-facing profile names ("Original profile", "Work", …) in a
/// per-group SQLite store under `Profile Groups/<id>.sqlite`, *not* in `profiles.ini`
/// (which only carries internal names like `default-release`). We prefer the store so the
/// UI matches Firefox's own profile selector, and fall back to `profiles.ini` on older
/// Firefox. Either way a profile resolves to an absolute directory for `--profile`.
enum FirefoxProfiles {
    static var supportDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
            + "/Library/Application Support/Firefox"
    }
    static var profilesINIPath: String { supportDirectory + "/profiles.ini" }
    static var profileGroupsDirectory: String { supportDirectory + "/Profile Groups" }

    /// Profiles to show in the UI: the new-store profiles if present, else legacy ini ones.
    static func list() -> [FirefoxProfile] {
        let installDefaults = installDefaultPaths()
        let store = storeProfiles(installDefaults: installDefaults)
        return store.isEmpty ? legacyProfiles(installDefaults: installDefaults) : store
    }

    /// Every profile we can resolve, from both sources, deduped by directory. Used to turn
    /// a configured profile *name* into a directory even if the config still uses an old name.
    static func allKnown() -> [FirefoxProfile] {
        let installDefaults = installDefaultPaths()
        var byPath: [String: FirefoxProfile] = [:]
        for p in legacyProfiles(installDefaults: installDefaults) { byPath[p.absolutePath] = p }
        // Store names win on collision (they're the user-facing ones).
        for p in storeProfiles(installDefaults: installDefaults) { byPath[p.absolutePath] = p }
        return Array(byPath.values)
    }

    static func path(forName name: String) -> String? {
        allKnown().first { $0.name == name }?.absolutePath
    }

    static func primaryName() -> String? {
        let profiles = list()
        return (profiles.first { $0.isPrimary } ?? profiles.first)?.name
    }

    // MARK: New profile store (SQLite)

    private static func storeProfiles(installDefaults: Set<String>) -> [FirefoxProfile] {
        guard let entries = try? FileManager.default
            .contentsOfDirectory(atPath: profileGroupsDirectory) else { return [] }
        var seen = Set<String>()
        var result: [FirefoxProfile] = []
        for entry in entries where entry.hasSuffix(".sqlite") {
            for p in readProfilesTable(dbPath: profileGroupsDirectory + "/" + entry,
                                       installDefaults: installDefaults) {
                if seen.insert(p.relativePath).inserted { result.append(p) }
            }
        }
        return result
    }

    private static func readProfilesTable(dbPath: String,
                                          installDefaults: Set<String>) -> [FirefoxProfile] {
        var db: OpaquePointer?
        // Read-only so we never interfere with a running Firefox.
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT name, path FROM Profiles", -1, &stmt, nil) == SQLITE_OK
        else { return [] }
        defer { sqlite3_finalize(stmt) }

        var out: [FirefoxProfile] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameC = sqlite3_column_text(stmt, 0),
                  let pathC = sqlite3_column_text(stmt, 1) else { continue }
            let name = String(cString: nameC)
            let rel = String(cString: pathC)
            out.append(FirefoxProfile(
                name: name,
                relativePath: rel,
                absolutePath: supportDirectory + "/" + rel,
                isPrimary: installDefaults.contains(rel)
            ))
        }
        return out
    }

    // MARK: Legacy profiles.ini

    private static func legacyProfiles(installDefaults: Set<String>) -> [FirefoxProfile] {
        return iniSections()
            .filter { $0.name.lowercased().hasPrefix("profile") }
            .compactMap { s in
                guard let name = s.values["Name"], let rel = s.values["Path"] else { return nil }
                let isRelative = (s.values["IsRelative"] ?? "1") == "1"
                let abs = isRelative ? supportDirectory + "/" + rel : rel
                let primary = installDefaults.contains(rel)
                    || (installDefaults.isEmpty && s.values["Default"] == "1")
                return FirefoxProfile(name: name, relativePath: rel,
                                      absolutePath: abs, isPrimary: primary)
            }
    }

    private static func installDefaultPaths() -> Set<String> {
        var paths = Set<String>()
        for s in iniSections() where s.name.lowercased().hasPrefix("install") {
            if let d = s.values["Default"] { paths.insert(d) }
        }
        return paths
    }

    // MARK: Minimal INI parsing

    private struct INISection { var name: String; var values: [String: String] }

    private static func iniSections() -> [INISection] {
        guard let text = try? String(contentsOfFile: profilesINIPath, encoding: .utf8) else {
            return []
        }
        var sections: [INISection] = []
        var current: INISection?
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                if let current { sections.append(current) }
                current = INISection(name: String(line.dropFirst().dropLast()), values: [:])
            } else if let eq = line.firstIndex(of: "="), current != nil {
                let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                current?.values[key] = value
            }
        }
        if let current { sections.append(current) }
        return sections
    }
}
