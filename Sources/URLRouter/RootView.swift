import SwiftUI
import AppKit
import CoreServices

final class ConfigModel: ObservableObject {
    @Published var config: AppConfig
    @Published var browsers: [InstalledBrowser]
    @Published var status: String = ""
    @Published var isDefaultBrowser: Bool = false

    /// Profiles per browser app path, precomputed so SwiftUI re-renders don't re-read disk.
    @Published private var profileCache: [String: [BrowserProfile]] = [:]

    /// Snapshot of the last saved/loaded config, used to detect unsaved changes.
    private var savedConfig: AppConfig

    init() {
        let loaded = ConfigStore.shared.load()
        config = loaded
        savedConfig = loaded
        browsers = BrowserFinder.installed()
        for b in browsers { profileCache[b.path] = Browsers.profiles(for: b.path) }
        refreshDefaultBrowserStatus()
    }

    var isDirty: Bool { config != savedConfig }

    func discardChanges() { config = savedConfig }

    /// Re-reads installed browsers and their profiles from disk (profiles may have changed
    /// while the app was open).
    func refresh() {
        browsers = BrowserFinder.installed()
        var cache: [String: [BrowserProfile]] = [:]
        for b in browsers { cache[b.path] = Browsers.profiles(for: b.path) }
        profileCache = cache
        refreshDefaultBrowserStatus()
        status = "Reloaded browsers & profiles"
    }

    /// Whether this app is currently the system default http handler.
    func refreshDefaultBrowserStatus() {
        guard let id = Bundle.main.bundleIdentifier,
              let web = URL(string: "https://example.com"),
              let appURL = NSWorkspace.shared.urlForApplication(toOpen: web),
              let handlerID = Bundle(url: appURL)?.bundleIdentifier else {
            isDefaultBrowser = false
            return
        }
        isDefaultBrowser = handlerID.caseInsensitiveCompare(id) == .orderedSame
    }

    /// Resolve the browser an entry targets (its own override, or the global default).
    func browserPath(forApp app: String?) -> String { app ?? config.resolvedDefaultApp }

    func supportsProfiles(forApp app: String?) -> Bool {
        Browsers.supportsProfiles(browserPath(forApp: app))
    }

    func supportsOpenMode(forApp app: String?) -> Bool {
        Browsers.supportsOpenMode(browserPath(forApp: app))
    }

    /// Profiles to offer for the given browser, including any key already referenced in
    /// config so a hand-edited/renamed value still appears selected.
    func profiles(forApp app: String?, includingCurrent current: String?) -> [BrowserProfile] {
        let path = browserPath(forApp: app)
        var list = profileCache[path] ?? Browsers.profiles(for: path)
        if let current, !current.isEmpty, !list.contains(where: { $0.key == current }) {
            list.append(BrowserProfile(key: current, label: current))
        }
        return list
    }

    func addRule() {
        config.rules.append(Rule(name: "New rule", match: "example.com", type: .domain,
                                 profile: config.defaultProfile))
    }

    func delete(id: Rule.ID) {
        config.rules.removeAll { $0.id == id }
    }

    func move(from: IndexSet, to: Int) {
        config.rules.move(fromOffsets: from, toOffset: to)
    }

    func save() {
        do {
            try ConfigStore.shared.save(config)
            savedConfig = config
            status = "Saved to \(ConfigStore.shared.fileURL.path)"
        } catch {
            status = "Save failed: \(error.localizedDescription)"
        }
    }

    func setAsDefaultBrowser() {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            status = "No bundle identifier (run from the built .app)"
            return
        }
        _ = LSSetDefaultHandlerForURLScheme("http" as CFString, bundleID as CFString)
        _ = LSSetDefaultHandlerForURLScheme("https" as CFString, bundleID as CFString)
        // Feedback comes from the "Default browser" indicator replacing the button.
        refreshDefaultBrowserStatus()
    }

    // MARK: Test a URL

    /// Parses a typed URL, adding https:// if the user omitted the scheme.
    private func normalizedURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: withScheme), url.host != nil else { return nil }
        return url
    }

    /// A human-readable description of where a URL would be routed (live preview).
    func testDecision(for text: String) -> String? {
        guard let url = normalizedURL(text) else { return nil }
        let decision = RuleEngine.decide(url: url, config: config)
        let browser = BrowserFinder.name(forPath: decision.app)
        let rule = decision.matchedRule?.name ?? "default fallback"
        if Browsers.supportsProfiles(decision.app), let profile = decision.profile, !profile.isEmpty {
            let label = profiles(forApp: decision.app, includingCurrent: profile)
                .first { $0.key == profile }?.label ?? profile
            return "\(browser) · \(label)  ·  \(rule)"
        }
        return "\(browser)  ·  \(rule)"
    }

    /// Actually opens the test URL through the routing engine.
    func openTestURL(_ text: String) {
        guard let url = normalizedURL(text) else { return }
        Launcher.launch(url: url, decision: RuleEngine.decide(url: url, config: config))
    }

    func canTest(_ text: String) -> Bool { normalizedURL(text) != nil }
}

struct RootView: View {
    @ObservedObject var model: ConfigModel
    @State private var selection: Rule.ID?
    @State private var pendingDeleteID: Rule.ID?
    @State private var testURL: String = ""

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 380)
            detail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .safeAreaInset(edge: .bottom) { footer }
        }
        .frame(minWidth: 720, minHeight: 480)
        .alert("Remove this rule?",
               isPresented: Binding(get: { pendingDeleteID != nil },
                                    set: { if !$0 { pendingDeleteID = nil } })) {
            Button("Remove", role: .destructive) { performPendingDelete() }
            Button("Cancel", role: .cancel) { pendingDeleteID = nil }
        } message: {
            Text("“\(pendingDeleteName)” will be removed from the list.")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshDefaultBrowserStatus()
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                defaultsHeader
                defaultsRow("Browser") {
                    BrowserPicker(selectionPath: $model.config.defaultApp,
                                  browsers: model.browsers,
                                  fallbackPath: AppConfig.firefoxPath)
                }
                defaultsRow("Profile") {
                    ProfileControl(model: model, app: model.config.defaultApp,
                                   selection: $model.config.defaultProfile, noneLabel: "(none)")
                }
                defaultsRow("Open in") {
                    Picker("", selection: Binding(
                        get: { model.config.defaultOpenMode ?? .newTab },
                        set: { model.config.defaultOpenMode = $0 })) {
                        ForEach(OpenMode.allCases) { Text($0.label).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                sectionLabel("Rules", topPadding: 12)
                ForEach(model.config.rules) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.name.isEmpty ? "(unnamed)" : rule.name)
                        Text("\(rule.type.rawValue): \(rule.match)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(rule.id)
                }
                .onMove(perform: model.move)
            }
            .listStyle(.inset)
            ruleListControls
            Divider()
            testBar
        }
        .frame(minWidth: 240)
    }

    /// "Test a URL" panel at the bottom of the sidebar: type a URL, see where it routes,
    /// and optionally open it. Kept on the left so it doesn't blend with the rule's settings.
    private var testBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("Test a URL…", text: $testURL)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.openTestURL(testURL) }
                Button("Open") { model.openTestURL(testURL) }
                    .disabled(!model.canTest(testURL))
            }
            if let result = model.testDecision(for: testURL) {
                Text("→ \(result)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .help(result)
            }
        }
        .padding(8)
        .background(.bar)
    }

    /// The "Defaults" title with a refresh button for reloading browsers/profiles.
    private var defaultsHeader: some View {
        HStack(spacing: 6) {
            Text("Defaults")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(action: model.refresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload browsers & profiles")
        }
        .listRowSeparator(.hidden)
    }

    /// A section title rendered as a plain row (no built-in header underline).
    private func sectionLabel(_ text: String, topPadding: CGFloat = 0) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, topPadding)
            .listRowSeparator(.hidden)
    }

    private func defaultsRow<Control: View>(_ label: String,
                                            @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 64, alignment: .leading)
            control()
            Spacer(minLength: 0)
        }
        .listRowSeparator(.hidden)
    }

    /// The add/remove bar pinned under the rules list (macOS source-list style).
    private var ruleListControls: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 0) {
                Button(action: addRule) {
                    Image(systemName: "plus").frame(width: 26, height: 22)
                }
                .help("Add rule")
                Divider().frame(height: 14)
                Button(action: requestDeleteSelectedRule) {
                    Image(systemName: "minus").frame(width: 26, height: 22)
                }
                .help("Remove selected rule")
                .disabled(selection == nil)
                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 4)
            .frame(height: 26)
            .background(.bar)
        }
    }

    private func addRule() {
        model.addRule()
        selection = model.config.rules.last?.id   // select it for immediate editing
    }

    /// Name of the rule queued for deletion, for the confirmation message.
    private var pendingDeleteName: String {
        guard let id = pendingDeleteID,
              let rule = model.config.rules.first(where: { $0.id == id })
        else { return "" }
        return rule.name.isEmpty ? "(unnamed)" : rule.name
    }

    private func requestDeleteSelectedRule() {
        guard selection != nil else { return }
        pendingDeleteID = selection
    }

    private func performPendingDelete() {
        guard let id = pendingDeleteID else { return }
        pendingDeleteID = nil
        let idx = model.config.rules.firstIndex { $0.id == id }
        model.delete(id: id)
        // Select a sensible neighbor so the detail pane isn't left empty.
        if let idx {
            let next = min(idx, model.config.rules.count - 1)
            selection = model.config.rules.indices.contains(next) ? model.config.rules[next].id : nil
        } else {
            selection = nil
        }
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        if let id = selection, let ruleBinding = binding(for: id) {
            RuleDetail(rule: ruleBinding, model: model)
        } else {
            emptyDetail
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.largeTitle).foregroundStyle(.secondary)
            Text("Select or add a rule").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            Text(model.status).font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            if model.isDefaultBrowser {
                Label("Default browser", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Set as Default Browser") { model.setAsDefaultBrowser() }
            }
            Button("Save") { model.save() }.keyboardShortcut("s")
        }
        .padding(10)
        .background(.bar)
    }

    // MARK: Helpers

    private func binding(for id: Rule.ID) -> Binding<Rule>? {
        guard let idx = model.config.rules.firstIndex(where: { $0.id == id }) else { return nil }
        return Binding(get: { model.config.rules[idx] },
                       set: { model.config.rules[idx] = $0 })
    }
}

/// Profile dropdown for a given browser. Shows a disabled note for browsers without
/// profile support (e.g. Safari).
struct ProfileControl: View {
    @ObservedObject var model: ConfigModel
    let app: String?
    @Binding var selection: String?
    var noneLabel: String = "(use default)"

    var body: some View {
        if model.supportsProfiles(forApp: app) {
            Picker("", selection: $selection) {
                Text(noneLabel).tag(String?.none)
                ForEach(model.profiles(forApp: app, includingCurrent: selection)) { profile in
                    Text(profile.label).tag(String?.some(profile.key))
                }
            }
            .labelsHidden()
        } else {
            Text("— no profiles for this browser")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// New tab / new window dropdown. Shows a disabled note for browsers that can't control it
/// from the CLI (e.g. Safari). `includeDefault` adds an "inherit" option for per-rule use.
struct OpenModeControl: View {
    @ObservedObject var model: ConfigModel
    let app: String?
    @Binding var selection: OpenMode?
    var includeDefault: Bool = true
    var defaultLabel: String = "(use default)"

    var body: some View {
        if model.supportsOpenMode(forApp: app) {
            Picker("", selection: $selection) {
                if includeDefault { Text(defaultLabel).tag(OpenMode?.none) }
                ForEach(OpenMode.allCases) { Text($0.label).tag(OpenMode?.some($0)) }
            }
            .labelsHidden()
        } else {
            Text("— not supported for this browser")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct RuleDetail: View {
    @Binding var rule: Rule
    @ObservedObject var model: ConfigModel

    var body: some View {
        Form {
            Section("Rule") {
                TextField("Name", text: $rule.name)
                Picker("Match type", selection: $rule.type) {
                    ForEach(MatchType.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Match", text: $rule.match)
                Text(hint).font(.caption).foregroundStyle(.secondary)
            }
            Section("Target") {
                LabeledContent("Browser") {
                    BrowserPicker(selectionPath: $rule.app,
                                  browsers: model.browsers,
                                  fallbackPath: model.config.resolvedDefaultApp,
                                  inheritLabel: "Default browser")
                }
                LabeledContent("Profile") {
                    ProfileControl(model: model, app: rule.app, selection: $rule.profile)
                }
                LabeledContent("Open in") {
                    OpenModeControl(model: model, app: rule.app, selection: $rule.openMode)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var hint: String {
        switch rule.type {
        case .domain: return "Matches the host or any subdomain, e.g. github.com → gist.github.com"
        case .glob:   return "Shell wildcard over the full URL, e.g. https://*.work.com/*"
        case .regex:  return "Regular expression over the full URL"
        }
    }
}

// Binds a String? to a non-optional TextField, treating "" as nil.
extension Binding where Value == String {
    init(_ source: Binding<String?>, replacingNilWith nilValue: String) {
        self.init(
            get: { source.wrappedValue ?? nilValue },
            set: { source.wrappedValue = $0.isEmpty ? nil : $0 }
        )
    }
}
