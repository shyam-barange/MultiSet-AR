import XCTest
@testable import MultiSetKit

final class DeepLinkRouterTests: XCTestCase {
    private let router = DeepLinkRouter()

    private func destination(_ string: String) -> DeepLinkDestination? {
        guard let url = URL(string: string) else { return nil }
        return router.destination(for: url)
    }

    // MARK: - Accepted forms

    func testAcceptsAPIHostWhichServesTheAASAFile() {
        // api.multiset.ai hosts apple-app-site-association, so it is the only
        // domain whose links can actually launch the Clip.
        XCTAssertEqual(
            destination("https://api.multiset.ai/space/k7m2p9xq"),
            .experience(spaceCode: "k7m2p9xq", modeOverride: nil)
        )
    }

    func testAPIHostAcceptsEitherPathPrefix() {
        // The canonical path shape is not settled, so both are recognised there.
        XCTAssertEqual(
            destination("https://api.multiset.ai/e/k7m2p9xq"),
            .experience(spaceCode: "k7m2p9xq", modeOverride: nil)
        )
    }

    func testAcceptsAppHostSpacePath() {
        // The platform's own web share URL stays recognised, so a pasted
        // dashboard link keeps working.
        XCTAssertEqual(
            destination("https://app.multiset.ai/space/k7m2p9xq"),
            .experience(spaceCode: "k7m2p9xq", modeOverride: nil)
        )
    }

    func testAcceptsClipHostExperiencePath() {
        XCTAssertEqual(
            destination("https://clip.multiset.ai/e/k7m2p9xq"),
            .experience(spaceCode: "k7m2p9xq", modeOverride: nil)
        )
    }

    func testAcceptsVanitySlugWithHyphen() {
        XCTAssertEqual(
            destination("https://app.multiset.ai/space/toit-brewery"),
            .experience(spaceCode: "toit-brewery", modeOverride: nil)
        )
    }

    func testHostMatchingIsCaseInsensitive() {
        XCTAssertEqual(
            destination("https://API.MultiSet.AI/space/abc123"),
            .experience(spaceCode: "abc123", modeOverride: nil)
        )
    }

    func testModeOverrideIsParsedForTesting() {
        XCTAssertEqual(
            destination("https://app.multiset.ai/space/abc123?mode=navigate"),
            .experience(spaceCode: "abc123", modeOverride: .navigate)
        )
    }

    func testUnknownModeOverrideIsIgnoredRatherThanFailing() {
        XCTAssertEqual(
            destination("https://app.multiset.ai/space/abc123?mode=teleport"),
            .experience(spaceCode: "abc123", modeOverride: nil)
        )
    }

    func testTrailingSegmentsAfterCodeAreRejected() {
        // A hosted-experience URL is always exactly `/{prefix}/{code}`. Accepting
        // extra segments would silently truncate a malformed URL into a code.
        XCTAssertNil(destination("https://app.multiset.ai/space/abc123/extra"))
    }

    // MARK: - Custom scheme

    func testCustomSchemeRoutes() {
        XCTAssertEqual(destination("multisetar://map/MAP_7UVHMW2TJMOA"), .map(code: "MAP_7UVHMW2TJMOA"))
        XCTAssertEqual(destination("multisetar://object/OBJ_123"), .object(code: "OBJ_123"))
        XCTAssertEqual(destination("multisetar://signin"), .signIn)
        XCTAssertEqual(destination("multisetar://demo/objectTracking"), .demo(.objectTracking))
        XCTAssertEqual(
            destination("multisetar://experience/abc123"),
            .experience(spaceCode: "abc123", modeOverride: nil)
        )
    }

    func testUnknownCustomSchemeRouteIsRejected() {
        XCTAssertNil(destination("multisetar://wipe/everything"))
        XCTAssertNil(destination("multisetar://demo/notARealDemo"))
    }

    // MARK: - Hostile and malformed input

    func testRejectsWrongHost() {
        XCTAssertNil(destination("https://evil.example.com/space/abc123"))
        XCTAssertNil(destination("https://multiset.ai/space/abc123"))
        XCTAssertNil(destination("https://dev-api.multiset.ai/space/abc123"))
    }

    func testRejectsLookalikeHostWithSuffix() {
        XCTAssertNil(destination("https://app.multiset.ai.evil.com/space/abc123"))
        XCTAssertNil(destination("https://api.multiset.ai.evil.com/space/abc123"))
    }

    func testRejectsPlainHTTP() {
        XCTAssertNil(destination("http://app.multiset.ai/space/abc123"))
    }

    func testRejectsWrongPathPrefixForHost() {
        // `/e/` belongs to clip.multiset.ai, not app.multiset.ai.
        XCTAssertNil(destination("https://app.multiset.ai/e/abc123"))
        XCTAssertNil(destination("https://clip.multiset.ai/space/abc123"))
        XCTAssertNil(destination("https://api.multiset.ai/v1/abc123"))
    }

    func testRejectsMissingCode() {
        XCTAssertNil(destination("https://app.multiset.ai/space"))
        XCTAssertNil(destination("https://app.multiset.ai/space/"))
    }

    func testRejectsPathTraversal() {
        XCTAssertNil(destination("https://app.multiset.ai/space/..%2F..%2Fadmin"))
        XCTAssertNil(destination("https://app.multiset.ai/space/a/../../etc/passwd"))
        XCTAssertNil(destination("https://app.multiset.ai/space/../space/abc123"))
    }

    func testRejectsUnicodeHomoglyphsInCode() {
        // Cyrillic 'а' (U+0430) reads as Latin 'a' but is a different code.
        XCTAssertNil(destination("https://app.multiset.ai/space/\u{0430}bc123"))
    }

    func testRejectsCodeContainingSeparators() {
        XCTAssertNil(destination("https://app.multiset.ai/space/abc:123"))
        XCTAssertNil(destination("https://app.multiset.ai/space/abc.123"))
    }

    func testRejectsOverlongCode() {
        let long = String(repeating: "a", count: 65)
        XCTAssertNil(destination("https://app.multiset.ai/space/\(long)"))
    }

    func testAcceptsCodeAtExactLengthLimit() {
        let atLimit = String(repeating: "a", count: 64)
        XCTAssertEqual(
            destination("https://app.multiset.ai/space/\(atLimit)"),
            .experience(spaceCode: atLimit, modeOverride: nil)
        )
    }

    func testRejectsEmbeddedCredentialsInAuthority() {
        // The authority here is `evil.com`; `app.multiset.ai` is only userinfo.
        XCTAssertNil(destination("https://app.multiset.ai@evil.com/space/abc123"))
    }

    func testRejectsUnrelatedSchemes() {
        XCTAssertNil(destination("javascript://app.multiset.ai/space/abc123"))
        XCTAssertNil(destination("file:///space/abc123"))
    }

    // MARK: - Round trip

    func testExperienceURLDefaultsToTheAASAHost() throws {
        // A QR pointing anywhere else cannot launch the Clip, however valid it looks.
        let url = try XCTUnwrap(DeepLinkRouter.experienceURL(spaceCode: "k7m2p9xq"))
        XCTAssertEqual(url.absoluteString, "https://api.multiset.ai/space/k7m2p9xq")
    }

    func testExperienceURLRoundTripsForEveryHostAndPrefix() throws {
        for (host, prefixes) in DeepLinkRouter.experienceHosts {
            for prefix in prefixes {
                let url = try XCTUnwrap(
                    DeepLinkRouter.experienceURL(spaceCode: "k7m2p9xq", host: host, prefix: prefix)
                )
                XCTAssertEqual(
                    router.destination(for: url),
                    .experience(spaceCode: "k7m2p9xq", modeOverride: nil),
                    "round trip failed for \(host)/\(prefix)"
                )
            }
        }
    }

    func testExperienceURLRejectsUnknownHostOrMismatchedPrefix() {
        XCTAssertNil(DeepLinkRouter.experienceURL(spaceCode: "abc", host: "evil.com"))
        XCTAssertNil(
            DeepLinkRouter.experienceURL(spaceCode: "abc", host: "app.multiset.ai", prefix: "e")
        )
    }
}

extension DeepLinkRouterTests {
    func testTabRoutesNavigateInternally() {
        for tab in ["home", "library", "publish", "learn", "settings"] {
            XCTAssertEqual(destination("multisetar://\(tab)"), .tab(tab), "failed for \(tab)")
        }
    }

    func testUnknownTabIsRejected() {
        XCTAssertNil(destination("multisetar://nonsense"))
    }

    func testTabRoutesAreNotReachableOverHTTPS() {
        // Internal navigation must not be triggerable from a web link.
        XCTAssertNil(destination("https://api.multiset.ai/learn"))
    }
}
