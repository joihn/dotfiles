import AppKit
import Foundation
import Vision

func downscaledForOCR(_ image: CGImage, maximumDimension: Int = 2400) -> CGImage {
    let largestDimension = max(image.width, image.height)
    guard largestDimension > maximumDimension else { return image }

    let scale = CGFloat(maximumDimension) / CGFloat(largestDimension)
    let width = max(1, Int((CGFloat(image.width) * scale).rounded()))
    let height = max(1, Int((CGFloat(image.height) * scale).rounded()))

    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return image }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage() ?? image
}

func showToast(_ message: String, success: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let size = NSSize(width: 390, height: 58)
    let mouseLocation = NSEvent.mouseLocation
    let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
    let visibleFrame = screen?.visibleFrame ?? .zero
    let origin = NSPoint(
        x: visibleFrame.midX - size.width / 2,
        y: visibleFrame.maxY - size.height - 28
    )

    let panel = NSPanel(
        contentRect: NSRect(origin: origin, size: size),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: false
    )
    panel.level = .statusBar
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

    let background = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    background.material = .hudWindow
    background.blendingMode = .behindWindow
    background.state = .active
    background.wantsLayer = true
    background.layer?.cornerRadius = 14
    background.layer?.masksToBounds = true

    let symbol = NSTextField(labelWithString: success ? "✓" : "×")
    symbol.frame = NSRect(x: 17, y: 14, width: 30, height: 30)
    symbol.font = .systemFont(ofSize: 24, weight: .bold)
    symbol.textColor = success ? .systemGreen : .systemRed
    symbol.alignment = .center

    let label = NSTextField(labelWithString: message)
    label.frame = NSRect(x: 57, y: 18, width: 315, height: 22)
    label.font = .systemFont(ofSize: 14, weight: .medium)
    label.textColor = .labelColor
    label.lineBreakMode = .byTruncatingTail

    background.addSubview(symbol)
    background.addSubview(label)
    panel.contentView = background
    panel.orderFrontRegardless()
    RunLoop.current.run(until: Date().addingTimeInterval(1.8))
    panel.orderOut(nil)
}

let temporaryURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("ocr-screenshot-\(UUID().uuidString).png")
defer { try? FileManager.default.removeItem(at: temporaryURL) }

let capture = Process()
capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
capture.arguments = ["-i", "-x", temporaryURL.path]

do {
    try capture.run()
    capture.waitUntilExit()
} catch {
    showToast("Could not start screen capture.", success: false)
    exit(1)
}

guard capture.terminationStatus == 0,
      FileManager.default.fileExists(atPath: temporaryURL.path),
      let image = NSImage(contentsOf: temporaryURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    showToast("Screen capture was interrupted or cancelled.", success: false)
    exit(0)
}

let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.usesLanguageCorrection = true
request.automaticallyDetectsLanguage = true
let ocrImage = downscaledForOCR(cgImage)

do {
    try VNImageRequestHandler(cgImage: ocrImage, options: [:]).perform([request])
} catch {
    showToast("Text recognition failed.", success: false)
    exit(1)
}

let text = (request.results ?? [])
    .sorted {
        let verticalDifference = abs($0.boundingBox.midY - $1.boundingBox.midY)
        if verticalDifference > 0.02 { return $0.boundingBox.midY > $1.boundingBox.midY }
        return $0.boundingBox.minX < $1.boundingBox.minX
    }
    .compactMap { $0.topCandidates(1).first?.string }
    .joined(separator: "\n")
    .trimmingCharacters(in: .whitespacesAndNewlines)

guard !text.isEmpty else {
    showToast("No text was found in that area.", success: false)
    exit(0)
}

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
guard pasteboard.setString(text, forType: .string),
      pasteboard.string(forType: .string) == text else {
    showToast("Could not copy the recognized text.", success: false)
    exit(1)
}
showToast("Recognized text copied to the clipboard.", success: true)
