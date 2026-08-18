import Foundation

public struct APIEnvironment: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String
    public let baseURL: URL

    public init(id: String, displayName: String, baseURL: URL) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
    }

    public static let production = APIEnvironment(
        id: "production",
        displayName: "Production",
        baseURL: URL(string: "https://api.multiset.ai")!
    )

    public static let staging = APIEnvironment(
        id: "staging",
        displayName: "Staging",
        baseURL: URL(string: "https://stg-api.multiset.ai")!
    )

    public static let development = APIEnvironment(
        id: "development",
        displayName: "Development",
        baseURL: URL(string: "https://dev-api.multiset.ai")!
    )

    public static let all: [APIEnvironment] = [.production, .staging, .development]
}

public enum ExternalLink {
    public static let website = URL(string: "https://www.multiset.ai/")!
    public static let developerPortal = URL(string: "https://developer.multiset.ai/")!
    public static let credentials = URL(string: "https://developer.multiset.ai/credentials")!
    public static let docs = URL(string: "https://docs.multiset.ai/multiset")!
    public static let restAPIDocs = URL(string: "https://docs.multiset.ai/multiset/basics/rest-api-docs")!
    public static let status = URL(string: "https://status.multiset.ai/")!
    public static let privacyPolicy = URL(string: "https://multiset.ai/privacy-policy")!
    public static let termsOfUse = URL(string: "https://multiset.ai/terms-of-use")!
    public static let blog = URL(string: "https://multiset.ai/blog-post")!
    public static let contactEmail = URL(string: "mailto:contact@multiset.ai")!

    public static let vps = URL(string: "https://multiset.ai/visual-positioning-system")!
    public static let objectTracking = URL(string: "https://multiset.ai/object-tracking")!
    public static let mapping = URL(string: "https://multiset.ai/mapping")!
    public static let e57ToVPS = URL(string: "https://multiset.ai/e57-to-vps")!
    public static let gaussianSplatToVPS = URL(string: "https://multiset.ai/3dgs-to-vps")!
    public static let panoramaToVPS = URL(string: "https://multiset.ai/360-to-vps")!

    public static let discord = URL(string: "https://discord.com/invite/pftwqThTxb")!
    public static let youTube = URL(string: "https://www.youtube.com/@MultiSetAI")!
    public static let github = URL(string: "https://github.com/MultiSet-AI")!
    public static let linkedIn = URL(string: "https://www.linkedin.com/company/multiset-ai")!
    public static let x = URL(string: "https://x.com/multiset_ai")!
    public static let instagram = URL(string: "https://www.instagram.com/multiset.ai/")!

    public static let auggieAward = URL(string: "https://www.awexr.com/blog/auggie-Award-Winners-at-AWE-USA-2026")!
    public static let areaReport = URL(string: "https://multiset.ai/post/multiset-ai-earns-most-robust-ranking-in-areas-2025-enterprise-visual-positioning-system-report")!

    public static let appClipDocs = URL(string: "https://developer.apple.com/documentation/appclip/configuring-your-app-clip-s-launch-experience")!
}

public enum CompanyInfo {
    public static let legalName = "MultiSet AI"
    public static let copyright = "© 2026 MultiSet AI · All rights reserved"
    public static let address = "28 Geary Street STE 650 Suite #371, San Francisco, California 94108, USA"
    public static let contactEmail = "contact@multiset.ai"
}
