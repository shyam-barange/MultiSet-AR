import Foundation

/// Builds an `ExperienceManifest` from a Content Space.
///
/// The platform has no experience-configuration API, so this app stores its
/// extra fields in the Content Space's generic `metadata` bag under the keys
/// below. Anything absent falls back to a sensible default, so a space created
/// in the web dashboard still opens.
public enum ExperienceManifestBuilder {
    public enum MetadataKey {
        public static let mode = "msar.mode"
        public static let destination = "msar.destination"
        public static let navGraph = "msar.navGraph"
        public static let objectCodes = "msar.objectCodes"
        public static let accentHex = "msar.accentHex"
        public static let subtitle = "msar.subtitle"
    }

    public static func build(
        from detail: ContentSpaceDetail,
        token: AuthToken,
        spaceCode: String
    ) throws -> ExperienceManifest {
        let space = detail.contentSpace
        let metadata = space.metadata ?? [:]

        guard let target = resolveTarget(space) else {
            throw MultiSetError.experienceUnavailable(.mapProcessing)
        }

        let pois = detail.contents.compactMap(PointOfInterest.init(content:))
        let objectCodes = commaSeparated(metadata[MetadataKey.objectCodes]?.text)
        let navGraph = decodeNavGraph(metadata[MetadataKey.navGraph]?.text)

        return ExperienceManifest(
            spaceCode: spaceCode,
            mode: resolveMode(
                declared: metadata[MetadataKey.mode]?.text,
                hasPOIs: !pois.isEmpty,
                hasNavGraph: navGraph != nil,
                hasObjects: !objectCodes.isEmpty
            ),
            target: target,
            branding: ExperienceBranding(
                title: space.name,
                subtitle: metadata[MetadataKey.subtitle]?.text ?? space.description,
                accentHex: metadata[MetadataKey.accentHex]?.text,
                logoURL: space.thumbnail.flatMap(URL.init(string:))
            ),
            pointsOfInterest: pois,
            destinationPOIID: metadata[MetadataKey.destination]?.text,
            objectCodes: objectCodes,
            navGraph: navGraph,
            token: token
        )
    }

    static func resolveTarget(_ space: ContentSpace) -> MapTarget? {
        if let mapSetId = space.mapSetId, !mapSetId.isEmpty {
            return .mapSet(code: mapSetId)
        }
        if let mapId = space.mapId, !mapId.isEmpty {
            return .map(code: mapId)
        }
        return nil
    }

    /// An explicit mode always wins. Otherwise infer from what the space carries,
    /// preferring the richer experience the data can actually support.
    static func resolveMode(
        declared: String?,
        hasPOIs: Bool,
        hasNavGraph: Bool,
        hasObjects: Bool
    ) -> ExperienceMode {
        if let declared, let mode = ExperienceMode(rawValue: declared.lowercased()) {
            return mode
        }
        if hasObjects { return .track }
        if hasNavGraph && hasPOIs { return .navigate }
        return .localize
    }

    static func commaSeparated(_ raw: String?) -> [String] {
        (raw ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// A malformed nav graph degrades the experience to `localize` rather than
    /// failing the whole invocation.
    static func decodeNavGraph(_ raw: String?) -> NavGraph? {
        guard let raw, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(NavGraph.self, from: data)
    }
}
