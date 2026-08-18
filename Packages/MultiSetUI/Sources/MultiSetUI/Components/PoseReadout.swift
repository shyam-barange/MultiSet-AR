import SwiftUI

/// Everything the pose HUD displays, as plain values so `MultiSetUI` stays
/// independent of the API and AR layers.
public struct PoseReadoutData: Equatable, Sendable {
    public var position: (x: Float, y: Float, z: Float)?
    public var rotation: (x: Float, y: Float, z: Float, w: Float)?
    public var confidence: Float?
    public var latency: Duration?
    public var framesSubmitted: Int
    public var queryCount: Int
    public var mapCode: String?
    public var trackingState: String
    public var isRightHanded: Bool

    public init(
        position: (x: Float, y: Float, z: Float)? = nil,
        rotation: (x: Float, y: Float, z: Float, w: Float)? = nil,
        confidence: Float? = nil,
        latency: Duration? = nil,
        framesSubmitted: Int = 0,
        queryCount: Int = 0,
        mapCode: String? = nil,
        trackingState: String = "unavailable",
        isRightHanded: Bool = true
    ) {
        self.position = position
        self.rotation = rotation
        self.confidence = confidence
        self.latency = latency
        self.framesSubmitted = framesSubmitted
        self.queryCount = queryCount
        self.mapCode = mapCode
        self.trackingState = trackingState
        self.isRightHanded = isRightHanded
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.position?.x == rhs.position?.x
            && lhs.position?.y == rhs.position?.y
            && lhs.position?.z == rhs.position?.z
            && lhs.confidence == rhs.confidence
            && lhs.latency == rhs.latency
            && lhs.framesSubmitted == rhs.framesSubmitted
            && lhs.queryCount == rhs.queryCount
            && lhs.mapCode == rhs.mapCode
            && lhs.trackingState == rhs.trackingState
    }
}

/// The app's signature component: a monospaced instrument readout of the VPS
/// result. Used in the AR overlay and on Map Detail.
public struct PoseReadout: View {
    private let data: PoseReadoutData
    private let style: Style

    public enum Style: Sendable {
        /// High-contrast, for use over a camera feed.
        case overlay
        /// Themed, for use inside a normal screen.
        case inline
    }

    public init(_ data: PoseReadoutData, style: Style = .overlay) {
        self.data = data
        self.style = style
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: MSSpacing.xs) {
            header
            Divider().overlay(separatorColor)
            row("POS", positionText)
            row("ROT", rotationText)
            row("CONF", confidenceText, tone: confidenceTone)
            row("LAT", latencyText)
            row("FRAMES", "\(data.framesSubmitted) submitted · \(data.queryCount) queries")
            row("TRACK", data.trackingState.uppercased())
        }
        .padding(MSSpacing.md)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: MSRadius.md)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: MSRadius.md))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Localization readout")
    }

    private var header: some View {
        HStack(spacing: MSSpacing.sm) {
            Text(data.mapCode ?? "NO MAP")
                .font(MSFont.mono)
                .foregroundStyle(primaryColor)
            Spacer(minLength: MSSpacing.sm)
            Text(data.isRightHanded ? "RH" : "LH")
                .font(MSFont.monoSmall)
                .foregroundStyle(dimColor)
        }
    }

    private func row(_ label: String, _ value: String, tone: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: MSSpacing.sm) {
            Text(label)
                .font(MSFont.monoSmall)
                .foregroundStyle(dimColor)
                .frame(width: 52, alignment: .leading)
            Text(value)
                .font(MSFont.monoSmall)
                .foregroundStyle(tone ?? primaryColor)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private var positionText: String {
        guard let p = data.position else { return "—" }
        return String(format: "%+.3f %+.3f %+.3f", p.x, p.y, p.z)
    }

    private var rotationText: String {
        guard let r = data.rotation else { return "—" }
        return String(format: "%+.3f %+.3f %+.3f %+.3f", r.x, r.y, r.z, r.w)
    }

    private var confidenceText: String {
        guard let c = data.confidence else { return "—" }
        return String(format: "%.2f", c)
    }

    private var confidenceTone: Color? {
        guard let c = data.confidence else { return nil }
        if style == .overlay {
            return c >= 0.6 ? MSColor.AR.good : (c >= 0.3 ? MSColor.AR.poor : MSColor.AR.bad)
        }
        return c >= 0.6 ? MSColor.success : (c >= 0.3 ? MSColor.warning : MSColor.danger)
    }

    private var latencyText: String {
        guard let latency = data.latency else { return "—" }
        let ms = Double(latency.components.seconds) * 1000
            + Double(latency.components.attoseconds) / 1e15
        return String(format: "%.0f ms", ms)
    }

    private var primaryColor: Color { style == .overlay ? MSColor.AR.text : MSColor.textPrimary }
    private var dimColor: Color { style == .overlay ? MSColor.AR.textDim : MSColor.textMuted }
    private var separatorColor: Color { style == .overlay ? MSColor.AR.panelBorder : MSColor.borderSubtle }
    private var borderColor: Color { style == .overlay ? MSColor.AR.panelBorder : MSColor.borderSubtle }
    private var background: Color { style == .overlay ? MSColor.AR.panel : MSColor.surfaceSunken }
}

#Preview("Overlay — localized") {
    ZStack {
        LinearGradient(colors: [.gray, .black], startPoint: .top, endPoint: .bottom)
        PoseReadout(
            PoseReadoutData(
                position: (1.234, 0.456, -2.671),
                rotation: (0.011, 0.994, 0.021, -0.052),
                confidence: 0.87,
                latency: .milliseconds(412),
                framesSubmitted: 4,
                queryCount: 2,
                mapCode: "MAP_7UVHMW2TJMOA",
                trackingState: "normal"
            )
        )
        .padding()
    }
    .ignoresSafeArea()
}

#Preview("Inline — searching") {
    PoseReadout(
        PoseReadoutData(framesSubmitted: 2, queryCount: 1, mapCode: "MAP_7UVHMW2TJMOA", trackingState: "limited"),
        style: .inline
    )
    .padding()
}
