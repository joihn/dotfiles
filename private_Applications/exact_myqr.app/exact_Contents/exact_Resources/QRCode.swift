import AppKit
import Foundation
import Vision

func showToast(_ message: String, success: Bool) {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let size = NSSize(width: 370, height: 58)
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
    label.frame = NSRect(x: 57, y: 18, width: 295, height: 22)
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
    .appendingPathComponent("qr-code-\(UUID().uuidString).png")
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
    // Escape cancels the selection without showing an error.
    exit(0)
}

let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]

do {
    try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
} catch {
    showToast("QR code detection failed.", success: false)
    exit(1)
}

guard let payload = request.results?
    .compactMap({ $0.payloadStringValue })
    .first,
      !payload.isEmpty else {
    showToast("No QR code was found in that area.", success: false)
    exit(0)
}

let pasteboard = NSPasteboard.general
pasteboard.clearContents()
pasteboard.setString(payload, forType: .string)
showToast("QR code copied to the clipboard.", success: true)
