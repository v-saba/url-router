# URL Router

A tiny macOS app that routes each web link to a specific browser / browser profile,
based on rules you define. Set it as your default browser and every clicked link is
dispatched to the right place (e.g. work links → your work Firefox profile, everything
else → your personal one).

Routes to **Firefox** and **Chromium-family** (Chrome, Edge, Brave, Vivaldi, Comet, …)
**profiles**, plus any other browser (Safari, etc.) without profile selection. A SwiftUI
editor manages the rules, which live in a hand-editable **YAML** file.

### Supported browsers

| Browser | Profile selection | How |
|---|---|---|
| Firefox | ✅ by name | `--profile <dir>`; names from the new profile store / `profiles.ini` |
| Chrome / Edge / Brave / Vivaldi / Chromium / Comet | ✅ by name | `--profile-directory=<dir>`; names from each browser's `Local State` |
| Safari | ❌ opens normally | Apple provides no CLI/AppleScript/URL way to pick a Safari profile |
| Anything else | ❌ opens normally | `open -a <App> <url>` |

Each browser has its own adapter (see `Browsers.swift`); adding another is a small, isolated change.

## How it works

`URL Router.app` is registered with macOS as an `http`/`https` handler. When you set
it as the default browser, macOS sends it each clicked URL (via the `GetURL` Apple
Event). The app:

1. loads the rules from `~/.config/url-router/config.yaml`,
2. finds the first matching rule (top to bottom),
3. launches the chosen browser/profile with the URL (new tab or window),
4. quits immediately (it never shows a window in this mode).

Launched normally (double-click), it instead opens the **SwiftUI rules editor**.

## Build

Requires Xcode / the Swift toolchain.

```sh
./scripts/build_app.sh            # builds "URL Router.app" and registers it
```

This compiles the Swift package, assembles `URL Router.app`, ad-hoc code-signs it,
and registers it with Launch Services so macOS lists it as a browser.

> Move `URL Router.app` to `/Applications` if you want it to live somewhere stable,
> then re-run the build (or re-register) from there.

## Use

```sh
# Edit rules in the GUI
open "URL Router.app"

# List the Firefox profiles the app detects (name → directory)
"URL Router.app/Contents/MacOS/URLRouter" --profiles

# Try a rule without launching anything
"URL Router.app/Contents/MacOS/URLRouter" --dry-run "https://gist.github.com/x"

# Route a URL for real (as the default browser would)
open "URL Router.app" --args "https://github.com"
```

### Set as the default browser

Either click **Set as Default Browser** in the app, or go to
**System Settings → Desktop & Dock → Default web browser** and pick `URL Router`.
macOS may ask for confirmation the first time.

## Config

`~/.config/url-router/config.yaml` — created with a commented template on first run.

```yaml
default_app: /Applications/Firefox.app   # used when a rule doesn't specify one
default_profile: default-release         # used when a rule doesn't specify one
default_open_mode: tab                    # tab | window — used when a rule doesn't specify

rules:
  - name: Work
    type: domain          # domain | glob | regex
    match: company.com    # matches company.com and any subdomain
    profile: Work         # a profile name for the target browser

  - name: Internal apps in Chrome
    type: glob
    match: "https://*.internal.company.com/*"
    app: /Applications/Google Chrome.app   # per-rule browser override
    profile: Work                           # a Chrome profile (name or directory)
    open: window                            # tab | window (per-rule override)

  - name: Apple docs in Safari
    type: domain
    match: developer.apple.com
    app: /System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app
    # no `profile:` — Safari has none

  - name: Personal reading
    type: regex
    match: '^https://(news\.ycombinator\.com|.*\.substack\.com)'
    profile: Personal
```

**Match types**

| type     | matched against     | example                                  |
|----------|---------------------|------------------------------------------|
| `domain` | URL host (+ subdomains) | `github.com` → matches `gist.github.com` |
| `glob`   | full URL (fnmatch)  | `https://*.work.com/*`                    |
| `regex`  | full URL            | `^https://.*\.internal/`                  |

- `profile` is a profile **name** for the rule's target browser (Firefox's
  `about:profiles` names, or a Chromium profile's display name / directory). Run
  `--profiles "<App.app>"` to see what the app detects for a browser. Omit it to use
  `default_profile`.
- `app` (optional, per rule) overrides the browser with an app bundle path. The right
  adapter is chosen automatically (Firefox / Chromium / generic).
- `open` (optional, per rule) is `tab` or `window`. Honored by Firefox (`-new-tab` /
  `-new-window`) and Chromium (`--new-window`); **ignored by Safari and other generic
  browsers**, which have no reliable CLI for tab/window control. Omit it to use
  `default_open_mode`.

## Firefox profile notes

Profiles are launched with `firefox --profile <absolute-path> -new-tab <url>`. Two
deliberate choices, both forced by Firefox's newer profile backend (151+, the one with the
profile selector):

1. **Names come from the new profile store, not `profiles.ini`.** Firefox 151 keeps the
   user-facing profile names ("Original profile", "Work", …) in a per-group SQLite database
   under `~/Library/Application Support/Firefox/Profile Groups/<id>.sqlite`. `profiles.ini`
   only has internal names like `default-release`. The app reads the SQLite store (and
   falls back to `profiles.ini` on older Firefox) so names match Firefox's own selector.

2. **Launch by `--profile <path>`, not `-P <name>`.** On the new backend the legacy
   `-P <name>` flag can pop the profile selector or spawn a fresh profile; `--profile <path>`
   opens the intended profile cleanly and reuses its window via per-profile remoting.

## Project layout

```
Package.swift                     Swift package (depends on Yams for YAML)
Sources/URLRouter/
  main.swift                      entry: CLI modes + NSApplication
  AppDelegate.swift               GetURL Apple Event handling + editor window
  Models.swift                    Rule / AppConfig / RouteDecision
  RuleEngine.swift                domain / glob / regex matching
  Browsers.swift                  per-browser adapters (Firefox, Chromium, generic) + launch
  Launcher.swift                  thin wrapper over the browser registry
  FirefoxProfiles.swift           resolves Firefox profiles (new SQLite store + profiles.ini)
  BrowserPicker.swift             installed-browser finder + SwiftUI dropdown
  ConfigStore.swift               loads/saves YAML, seeds a default
  RootView.swift                  SwiftUI rules editor
Tests/URLRouterTests/           RuleEngine matching + config decoding tests
Resources/Info.plist              declares http/https handler (default-browser)
scripts/build_app.sh              build + assemble + register the .app
scripts/make_icon.swift           draws the app icon PNG
scripts/make_icns.sh              1024 PNG -> AppIcon.icns
```

## Tests

```sh
swift test
```

## License

MIT — see [LICENSE](LICENSE).

## Roadmap ideas

- Menu-bar status item; "open in…" picker on ⌥-click.
- Import/validate rules.
- More browser adapters (Arc, Orion) as needed.
