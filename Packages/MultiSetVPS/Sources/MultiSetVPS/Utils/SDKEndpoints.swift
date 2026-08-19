/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation

/// Internal API endpoints for MultiSet services.
///
/// Every endpoint is derived from `baseURL` on demand rather than stored, so an
/// override set through `VPSConfig.baseURL` applies to every request the SDK
/// makes afterwards. The SDK ships as a binary framework, so this file is not
/// editable by integrators — the config property is the only way in.
internal struct SDKEndpoints {

    /// Production API. Used unless the host app overrides it.
    static let defaultBaseURL = VPSConfig.productionBaseURL

    /// Base URL all endpoints below are built from.
    private(set) static var baseURL = defaultBaseURL

    /// Point the SDK at a different deployment — staging, on-premise, a local proxy.
    ///
    /// Applied by `MultiSet.initialize` before authentication, because a token is only
    /// valid against the host that issued it. An empty or malformed value is refused
    /// rather than applied, so a typo cannot quietly take the SDK offline.
    /// - Returns: true if `baseURL` now equals the requested host
    @discardableResult
    static func setBaseURL(_ urlString: String) -> Bool {
        guard let normalized = normalized(urlString) else {
            print("MultiSetVPS >> Ignoring invalid baseURL \"\(urlString)\" — staying on \(baseURL)")
            return false
        }

        guard normalized != baseURL else { return true }

        baseURL = normalized
        print("MultiSetVPS >> API base URL set to \(baseURL)")
        return true
    }

    /// True when `urlString` names the host already in use, ignoring the formatting
    /// differences `normalized(_:)` irons out. An unusable value counts as "same",
    /// since it would be refused rather than switched to.
    static func isActiveBaseURL(_ urlString: String) -> Bool {
        guard let normalized = normalized(urlString) else { return true }
        return normalized == baseURL
    }

    /// Trims whitespace and trailing slashes, and requires an http(s) URL with a host.
    /// Returns nil for anything that would not produce a usable request URL.
    private static func normalized(_ urlString: String) -> String? {
        var cleaned = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasSuffix("/") {
            cleaned.removeLast()
        }

        guard !cleaned.isEmpty,
              let url = URL(string: cleaned),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host,
              !host.isEmpty else { return nil }

        return cleaned
    }

    /// Authentication endpoint
    static var authURL: String { "\(baseURL)/m2m/token" }

    /// Single-frame localization endpoint
    static var queryURL: String { "\(baseURL)/vps/map/query-form" }

    /// Multi-frame localization endpoint
    static var multiImageQueryURL: String { "\(baseURL)/vps/map/multi-image-query" }

    /// Get map details endpoint
    static var getMapURL: String { "\(baseURL)/vps/map/" }

    /// Get map set details endpoint
    static var getMapSetURL: String { "\(baseURL)/vps/map-set/" }

    /// Get file (presigned URL) endpoint
    static var getFileURL: String { "\(baseURL)/file" }

    /// Object tracking query endpoint
    static var objectQueryURL: String { "\(baseURL)/vps/object/query" }

    /// Get object details endpoint
    static var getObjectURL: String { "\(baseURL)/vps/object/" }

    /// Get endpoint URL for localization mode
    static func localizationURL(for mode: LocalizationMode) -> String {
        switch mode {
        case .singleFrame:
            return queryURL
        case .multiFrame:
            return multiImageQueryURL
        }
    }
}
