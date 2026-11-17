import AppKit
import ScreenCaptureKit

/// Captures window contents for the thumbnails and the preview of the selected window.
@MainActor
final class Thumbnails {
    static let shared = Thumbnails()

    private let queue = DispatchQueue(label: "app.flick.capture", qos: .userInitiated, attributes: .concurrent)
    private var inFlight: Set<CGWindowID> = []
    private var backgroundTimer: Timer?
    /// Called when a new image for a window is ready.
    var onUpdate: ((CGWindowID) -> Void)?

    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Captures each window (unless one is already being captured) and stores the image on it.
    func capture(_ windows: [TrackedWindow], maxPixelSize: CGFloat) {
        guard Self.hasPermission else { return }
        for window in windows where !window.isMinimized && !inFlight.contains(window.id) {
            inFlight.insert(window.id)
            let id = window.id
            queue.async {
                let image = Private.captureWindow(id).map { Self.downscaled($0, maxPixelSize: maxPixelSize) }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let store = Thumbnails.shared
                        store.inFlight.remove(id)
                        if let image {
                            window.thumbnail = image
                            window.thumbnailDate = Date()
                            store.onUpdate?(id)
                        } else if !Private.canCaptureWindows {
                            store.captureWithScreenCaptureKit(window, maxPixelSize: maxPixelSize)
                        }
                    }
                }
            }
        }
    }

    /// Fallback if the window server capture call ever disappears.
    private func captureWithScreenCaptureKit(_ window: TrackedWindow, maxPixelSize: CGFloat) {
        let id = window.id
        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
                  let scWindow = content.windows.first(where: { $0.windowID == id }) else { return }
            let filter = SCContentFilter(desktopIndependentWindow: scWindow)
            let configuration = SCStreamConfiguration()
            let scale = min(1, maxPixelSize / max(scWindow.frame.width, scWindow.frame.height, 1))
            configuration.width = max(1, Int(scWindow.frame.width * scale * 2))
            configuration.height = max(1, Int(scWindow.frame.height * scale * 2))
            configuration.showsCursor = false
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) else { return }
            window.thumbnail = image
            window.thumbnailDate = Date()
            onUpdate?(id)
        }
    }

    nonisolated static func downscaled(_ image: CGImage, maxPixelSize: CGFloat) -> CGImage {
        let largest = CGFloat(max(image.width, image.height))
        guard largest > maxPixelSize * 1.15 else { return image }
        let scale = maxPixelSize / largest
        let width = max(1, Int(CGFloat(image.width) * scale)), height = max(1, Int(CGFloat(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { return image }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }

    /// Keeps thumbnails of recently used windows fresh so the switcher opens with recent images.
    func setBackgroundCapture(_ enabled: Bool) {
        backgroundTimer?.invalidate()
        backgroundTimer = nil
        guard enabled else { return }
        backgroundTimer = Timer.scheduledTimer(withTimeInterval: 8, repeats: true) { _ in
            MainActor.assumeIsolated {
                guard !SwitcherController.shared.isVisible else { return }
                let recent = WindowTracker.shared.apps.values.flatMap { $0.windows.values }
                    .filter { !$0.isMinimized }
                    .sorted { $0.focusOrder > $1.focusOrder }
                    .prefix(12)
                Thumbnails.shared.capture(Array(recent), maxPixelSize: 900)
            }
        }
    }
}
