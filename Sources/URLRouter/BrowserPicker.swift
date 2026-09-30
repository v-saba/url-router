import SwiftUI
import AppKit

/// A browser app installed on this Mac that can handle web URLs.
struct InstalledBrowser: Identifiable, Hashable {
    var path: String     // e.g. /Applications/Firefox.app
    var name: String     // e.g. Firefox
    var id: String { path }
}

enum BrowserFinder {
    /// All apps registered to open https URLs — the same set macOS shows in its
    /// "Default web browser" dropdown — minus ourselves (routing to us would loop).
    static func installed() -> [InstalledBrowser] {
        guard let web = URL(string: "https://example.com") else { return [] }
        let selfID = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var result: [InstalledBrowser] = []
        for url in NSWorkspace.shared.urlsForApplications(toOpen: web) {
            guard seen.insert(url.path).inserted else { continue }
            if let selfID, Bundle(url: url)?.bundleIdentifier == selfID { continue }
            result.append(InstalledBrowser(path: url.path, name: displayName(for: url)))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Prefer the Finder/localized name; fall back to the bundle name, then "Firefox.app" → "Firefox".
    static func displayName(for url: URL) -> String {
        let finderName = FileManager.default.displayName(atPath: url.path)
        if !finderName.isEmpty && finderName.lowercased() != url.lastPathComponent.lowercased() {
            return finderName
        }
        let bundle = Bundle(url: url)
        if let n = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String { return n }
        if let n = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String { return n }
        return url.deletingPathExtension().lastPathComponent
    }

    static func name(forPath path: String) -> String {
        displayName(for: URL(fileURLWithPath: path))
    }

    /// App icons, cached so SwiftUI re-renders don't re-hit the disk.
    private static var iconCache: [String: NSImage] = [:]
    static func icon(forPath path: String) -> NSImage {
        if let cached = iconCache[path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = image
        return image
    }
}

/// A dropdown that shows installed browsers like the macOS default-browser picker:
/// icon + name in the menu, and icon + name + grey path in the collapsed button.
struct BrowserPicker: View {
    @Binding var selectionPath: String?
    let browsers: [InstalledBrowser]
    let fallbackPath: String
    /// If set, a nil selection means "inherit" and shows this label (used for per-rule overrides).
    var inheritLabel: String? = nil

    private var isInherit: Bool { selectionPath == nil && inheritLabel != nil }
    private var currentPath: String { selectionPath ?? fallbackPath }
    private var currentName: String {
        isInherit ? (inheritLabel ?? "") : BrowserFinder.name(forPath: currentPath)
    }

    var body: some View {
        Menu {
            if let inheritLabel {
                Button { selectionPath = nil } label: {
                    Image(systemName: "arrow.turn.down.right")
                    Text(inheritLabel)
                }
                Divider()
            }
            ForEach(browsers) { browser in
                Button { selectionPath = browser.path } label: {
                    Image(nsImage: BrowserFinder.icon(forPath: browser.path))
                    Text(browser.name)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if isInherit {
                    Image(systemName: "globe").frame(width: 18, height: 18)
                        .foregroundStyle(.secondary)
                } else {
                    icon(currentPath, size: 18)
                }
                Text(currentName)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private func icon(_ path: String, size: CGFloat) -> some View {
        Image(nsImage: BrowserFinder.icon(forPath: path))
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
    }
}
