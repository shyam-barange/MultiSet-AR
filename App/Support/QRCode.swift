import CoreImage.CIFilterBuiltins
import MultiSetKit
import PDFKit
import SwiftUI
import UIKit

/// Generates QR codes locally. No network, no third-party service — the code is
/// derived from the URL on device.
enum QRCode {
    /// High error correction, because these get printed and taped to walls where
    /// they collect scuffs and glare.
    static func image(for string: String, side: CGFloat = 1024) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }

        // Nearest-neighbour scaling keeps the module edges hard. Smooth
        // interpolation blurs them and costs scan reliability at distance.
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A printable sheet for a hosted experience. Rendered as PDF vector output so it
/// stays sharp at any print size.
enum PrintableSheet {
    enum PaperSize {
        case a4, usLetter

        /// Points at 72 dpi.
        var rect: CGRect {
            switch self {
            case .a4: CGRect(x: 0, y: 0, width: 595.28, height: 841.89)
            case .usLetter: CGRect(x: 0, y: 0, width: 612, height: 792)
            }
        }

        var displayName: String {
            switch self {
            case .a4: "A4"
            case .usLetter: "US Letter"
            }
        }
    }

    /// 100 mm at 72 dpi. The brief's minimum, and the reason the quiet zone is
    /// preserved explicitly below — a code crowded to its edges is the most
    /// common scan failure.
    private static let codeSide: CGFloat = 283.46

    static func pdfData(
        url: String,
        title: String,
        subtitle: String?,
        paper: PaperSize = .a4
    ) -> Data? {
        guard let qr = QRCode.image(for: url, side: 1200), let qrCG = qr.cgImage else { return nil }

        let renderer = UIGraphicsPDFRenderer(bounds: paper.rect)
        return renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            let page = paper.rect

            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(page)

            // Quiet zone: four modules' worth of white around the code, drawn as
            // an explicit margin rather than trusting the layout to leave room.
            let quietZone = codeSide * 0.08
            let codeRect = CGRect(
                x: (page.width - codeSide) / 2,
                y: page.height * 0.16,
                width: codeSide,
                height: codeSide
            )
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(codeRect.insetBy(dx: -quietZone, dy: -quietZone))

            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: page.height)
            cgContext.scaleBy(x: 1, y: -1)
            cgContext.interpolationQuality = .none
            cgContext.draw(qrCG, in: CGRect(
                x: codeRect.minX,
                y: page.height - codeRect.maxY,
                width: codeRect.width,
                height: codeRect.height
            ))
            cgContext.restoreGState()

            draw(
                text: title,
                in: CGRect(
                    x: 48,
                    y: codeRect.maxY + quietZone + 28,
                    width: page.width - 96,
                    height: 90
                ),
                font: .systemFont(ofSize: 30, weight: .semibold),
                color: .black
            )

            if let subtitle {
                draw(
                    text: subtitle,
                    in: CGRect(
                        x: 48,
                        y: codeRect.maxY + quietZone + 122,
                        width: page.width - 96,
                        height: 60
                    ),
                    font: .systemFont(ofSize: 17, weight: .regular),
                    color: .darkGray
                )
            }

            draw(
                text: url,
                in: CGRect(x: 48, y: page.height - 108, width: page.width - 96, height: 40),
                font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                color: .gray
            )
            draw(
                text: "Scan with an iPhone camera · \(CompanyInfo.legalName)",
                in: CGRect(x: 48, y: page.height - 72, width: page.width - 96, height: 30),
                font: .systemFont(ofSize: 10, weight: .regular),
                color: .lightGray
            )
        }
    }

    private static func draw(text: String, in rect: CGRect, font: UIFont, color: UIColor) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        style.lineBreakMode = .byTruncatingTail
        NSAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style]
        ).draw(in: rect)
    }

    static func write(data: Data, filename: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}

enum PrintableTarget {
    /// The object-tracking demo target, as vector PDF.
    static func writePDF() -> URL? {
        let paper = PrintableSheet.PaperSize.a4.rect
        let renderer = UIGraphicsPDFRenderer(bounds: paper)
        let data = renderer.pdfData { context in
            context.beginPage()
            let cgContext = context.cgContext
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.fill(paper)

            let side = min(paper.width, paper.height) * 0.7
            let rect = CGRect(
                x: (paper.width - side) / 2,
                y: (paper.height - side) / 2,
                width: side,
                height: side
            )

            cgContext.setStrokeColor(UIColor.black.cgColor)
            cgContext.setLineWidth(4)
            cgContext.stroke(rect)

            let block = side * 0.16
            cgContext.setFillColor(UIColor.black.cgColor)
            for corner in [
                CGRect(x: rect.minX, y: rect.minY, width: block, height: block),
                CGRect(x: rect.maxX - block, y: rect.minY, width: block, height: block),
                CGRect(x: rect.minX, y: rect.maxY - block, width: block, height: block)
            ] {
                cgContext.fill(corner)
            }

            let centre = CGPoint(x: rect.midX, y: rect.midY)
            cgContext.setLineWidth(3)
            for ring in 1...4 {
                let radius = side * 0.055 * CGFloat(ring)
                cgContext.strokeEllipse(in: CGRect(
                    x: centre.x - radius, y: centre.y - radius,
                    width: radius * 2, height: radius * 2
                ))
            }
            let arm = side * 0.3
            cgContext.move(to: CGPoint(x: centre.x - arm, y: centre.y))
            cgContext.addLine(to: CGPoint(x: centre.x + arm, y: centre.y))
            cgContext.move(to: CGPoint(x: centre.x, y: centre.y - arm))
            cgContext.addLine(to: CGPoint(x: centre.x, y: centre.y + arm))
            cgContext.strokePath()

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            NSAttributedString(
                string: "MultiSet AR — object tracking demo target",
                attributes: [
                    .font: UIFont.systemFont(ofSize: 12),
                    .foregroundColor: UIColor.gray,
                    .paragraphStyle: style
                ]
            ).draw(in: CGRect(x: 48, y: paper.height - 72, width: paper.width - 96, height: 30))
        }
        return PrintableSheet.write(data: data, filename: "MultiSet-AR-demo-target.pdf")
    }
}
