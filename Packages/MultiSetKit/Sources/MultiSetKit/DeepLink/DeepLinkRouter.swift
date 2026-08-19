import Foundation

public enum DeepLinkDestination: Sendable, Equatable {
    /// A hosted experience, from a QR scan or an App Clip invocation.
    case experience(spaceCode: String, modeOverride: ExperienceMode?)
    case map(code: String)
    case object(code: String)
    case demo(DemoKind)
    case signIn
    /// Internal navigation to a top-level tab.
    case tab(String)

    public enum DemoKind: String, Sendable, CaseIterable {
        case objectTracking
        case syntheticNavigation
        case simulatedLocalization
    }
}

/// Parses inbound URLs for both targets. One router so the App and the Clip can
/// never disagree about what a link means.
public struct DeepLinkRouter: Sendable {
    /// Hosts that may carry a hosted experience, and the path prefixes each
    /// accepts.
    ///
    /// `api.multiset.ai` is the domain that hosts the
    /// `apple-app-site-association` file, so it is where App Clip invocations
    /// actually arrive and what printed QR codes encode. It accepts both
    /// prefixes because the canonical path shape is not settled yet.
    /// `app.multiset.ai/space/{code}` is the platform's own web share URL and is
    /// still recognised so an older link or a pasted dashboard URL keeps working.
    public static let experienceHosts: [String: Set<String>] = [
        "api.multiset.ai": ["space", "e"],
        "app.multiset.ai": ["space"],
        "clip.multiset.ai": ["e"]
    ]

    /// The host that serves the AASA file, and therefore the only one whose
    /// links can launch the App Clip. Generated QR codes point here.
    public static let canonicalExperienceHost = "api.multiset.ai"
    public static let canonicalExperiencePrefix = "space"

    public static let customScheme = "multisetar"

    /// A space code is short, opaque, and alphanumeric. Anything else is a
    /// malformed or hostile link, not a code we should send to the server.
    static let codeCharacters = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    static let maxCodeLength = 64

    public init() {}

    public func destination(for url: URL) -> DeepLinkDestination? {
        if url.scheme?.lowercased() == Self.customScheme {
            return customSchemeDestination(url)
        }
        return webDestination(url)
    }

    private func webDestination(_ url: URL) -> DeepLinkDestination? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https",
              let host = url.host?.lowercased(),
              let acceptedPrefixes = Self.experienceHosts[host]
        else { return nil }

        // Exactly two segments. A hosted-experience URL is always
        // `/{prefix}/{code}` — anything longer is malformed or an attempt to
        // smuggle extra path through, and must not be truncated into a code.
        let segments = pathSegments(url)
        guard segments.count == 2,
              acceptedPrefixes.contains(segments[0].lowercased()),
              let code = validated(segments[1])
        else { return nil }

        return .experience(spaceCode: code, modeOverride: modeOverride(url))
    }

    private func customSchemeDestination(_ url: URL) -> DeepLinkDestination? {
        // A custom-scheme URL puts the route in the host slot: multisetar://map/CODE
        var segments = pathSegments(url)
        if let host = url.host, !host.isEmpty {
            segments.insert(host, at: 0)
        }
        guard let route = segments.first?.lowercased() else { return nil }

        switch route {
        case "signin":
            return .signIn
        case "home", "library", "publish", "learn", "settings":
            return .tab(route)
        case "demo":
            guard segments.count >= 2,
                  let kind = DeepLinkDestination.DemoKind(rawValue: segments[1])
            else { return nil }
            return .demo(kind)
        case "map":
            guard segments.count >= 2, let code = validated(segments[1]) else { return nil }
            return .map(code: code)
        case "object":
            guard segments.count >= 2, let code = validated(segments[1]) else { return nil }
            return .object(code: code)
        case "experience", "space":
            guard segments.count >= 2, let code = validated(segments[1]) else { return nil }
            return .experience(spaceCode: code, modeOverride: modeOverride(url))
        default:
            return nil
        }
    }

    /// `?mode=` is a testing override only. The canonical mode lives in the
    /// experience manifest, so a stale printed QR cannot pin the wrong one.
    private func modeOverride(_ url: URL) -> ExperienceMode? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "mode" }?
            .value
            .flatMap { ExperienceMode(rawValue: $0.lowercased()) }
    }

    private func pathSegments(_ url: URL) -> [String] {
        url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
    }

    /// Validates a bare code, for manual entry and for scanner payloads that
    /// carry a code rather than a URL. Rejects traversal attempts,
    /// percent-encoded payloads, non-ASCII homoglyphs, and anything longer than
    /// a real code can be.
    public func validated(_ candidate: String) -> String? {
        guard !candidate.isEmpty, candidate.count <= Self.maxCodeLength else { return nil }
        guard candidate.unicodeScalars.allSatisfy({ Self.codeCharacters.contains($0) }) else { return nil }
        return candidate
    }

    /// The URL to print on a QR code. Defaults to the AASA host, since a link on
    /// any other domain cannot launch the App Clip.
    public static func experienceURL(
        spaceCode: String,
        host: String = canonicalExperienceHost,
        prefix: String = canonicalExperiencePrefix
    ) -> URL? {
        guard let accepted = experienceHosts[host], accepted.contains(prefix) else { return nil }
        return URL(string: "https://\(host)/\(prefix)/\(spaceCode)")
    }
}
