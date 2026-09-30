import XCTest
@testable import URLRouter

final class RuleEngineTests: XCTestCase {

    private func rule(_ name: String, _ type: MatchType, _ match: String,
                      profile: String? = nil, app: String? = nil,
                      open: OpenMode? = nil) -> Rule {
        Rule(name: name, match: match, type: type, profile: profile, app: app, openMode: open)
    }

    private func config(_ rules: [Rule], defaultOpen: OpenMode? = nil) -> AppConfig {
        AppConfig(defaultApp: "/Applications/Firefox.app",
                  defaultProfile: "Personal",
                  defaultOpenMode: defaultOpen,
                  rules: rules)
    }

    private func decide(_ urlString: String, _ config: AppConfig) -> RouteDecision {
        RuleEngine.decide(url: URL(string: urlString)!, config: config)
    }

    // MARK: matching

    func testDomainMatchesHostAndSubdomains() {
        let c = config([rule("gh", .domain, "github.com")])
        XCTAssertEqual(decide("https://github.com/a", c).matchedRule?.name, "gh")
        XCTAssertEqual(decide("https://gist.github.com/a", c).matchedRule?.name, "gh")
    }

    /// A lookalike host must not match: "notgithub.com" merely *ends with* the pattern.
    func testDomainRejectsLookalikeHost() {
        let c = config([rule("gh", .domain, "github.com")])
        XCTAssertNil(decide("https://notgithub.com/a", c).matchedRule)
    }

    func testDomainIsCaseInsensitiveAndAcceptsWildcardPrefix() {
        let c = config([rule("gh", .domain, "*.GitHub.com")])
        XCTAssertEqual(decide("https://GIST.github.COM/a", c).matchedRule?.name, "gh")
        XCTAssertEqual(decide("https://github.com/a", c).matchedRule?.name, "gh")
    }

    func testGlobMatchesFullURL() {
        let c = config([rule("ci", .glob, "https://*.ci.example.com/*")])
        XCTAssertEqual(decide("https://build.ci.example.com/job/1", c).matchedRule?.name, "ci")
        XCTAssertNil(decide("https://ci.example.com/job/1", c).matchedRule)
    }

    func testRegexMatchesFullURL() {
        let c = config([rule("news", .regex, #"^https://(news\.ycombinator\.com|.*\.substack\.com)"#)])
        XCTAssertEqual(decide("https://news.ycombinator.com/item?id=1", c).matchedRule?.name, "news")
        XCTAssertEqual(decide("https://foo.substack.com/p/x", c).matchedRule?.name, "news")
        XCTAssertNil(decide("https://example.com", c).matchedRule)
    }

    func testInvalidRegexDoesNotMatchOrCrash() {
        let c = config([rule("bad", .regex, "([unclosed")])
        XCTAssertNil(decide("https://example.com", c).matchedRule)
    }

    // MARK: resolution

    func testFirstMatchingRuleWins() {
        let c = config([rule("first", .domain, "github.com"),
                        rule("second", .domain, "github.com")])
        XCTAssertEqual(decide("https://github.com", c).matchedRule?.name, "first")
    }

    func testFallbackUsesDefaultsAndNewTab() {
        let d = decide("https://nothing.example", config([]))
        XCTAssertNil(d.matchedRule)
        XCTAssertEqual(d.app, "/Applications/Firefox.app")
        XCTAssertEqual(d.profile, "Personal")
        XCTAssertEqual(d.openMode, .newTab)
    }

    func testRuleOverridesAppProfileAndOpenMode() {
        let c = config([rule("chrome", .domain, "example.com",
                             profile: "Work", app: "/Applications/Google Chrome.app",
                             open: .newWindow)])
        let d = decide("https://example.com", c)
        XCTAssertEqual(d.app, "/Applications/Google Chrome.app")
        XCTAssertEqual(d.profile, "Work")
        XCTAssertEqual(d.openMode, .newWindow)
    }

    func testRuleInheritsDefaultsWhenUnset() {
        let c = config([rule("bare", .domain, "example.com")], defaultOpen: .newWindow)
        let d = decide("https://example.com", c)
        XCTAssertEqual(d.app, "/Applications/Firefox.app")
        XCTAssertEqual(d.profile, "Personal")
        XCTAssertEqual(d.openMode, .newWindow)
    }

    // MARK: lenient decoding of hand-edited config

    func testRuleDecodesWithoutOptionalFields() throws {
        let json = #"{"match": "example.com"}"#.data(using: .utf8)!
        let r = try JSONDecoder().decode(Rule.self, from: json)
        XCTAssertEqual(r.type, .domain)   // omitted `type` defaults to domain
        XCTAssertEqual(r.match, "example.com")
        XCTAssertEqual(r.name, "")
        XCTAssertNil(r.profile)
        XCTAssertNil(r.app)
        XCTAssertNil(r.openMode)
    }

    func testOpenModeDecodesFromShortNames() throws {
        let json = #"{"match": "a.com", "open": "window"}"#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(Rule.self, from: json).openMode, .newWindow)
    }
}
