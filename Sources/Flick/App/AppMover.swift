import AppKit

/// Installs Flick into /Applications when it was opened from the disk image or the Downloads folder: permissions
/// given to a copy that later moves or disappears would be lost.
@MainActor
enum AppMover {
    static let skipKey = "skipMoveToApplications"

    static var bundleURL: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }

    static var isInApplications: Bool {
        let path = bundleURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return path.hasPrefix("/Applications/") || path.hasPrefix(home + "/")
    }

    /// Opened straight from the disk image, or "translocated" by Gatekeeper to a random read-only place.
    static var isOnDiskImageOrTranslocated: Bool {
        let path = bundleURL.path
        return path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
    }

    static var shouldOffer: Bool { !isInApplications && !UserDefaults.standard.bool(forKey: skipKey) }

    enum MoveError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let message): message }
        }
    }

    /// Copies Flick to /Applications (replacing an older copy), removes the download quarantine, opens the new copy
    /// and quits this one. The disk image is ejected and a downloaded original moved to the Trash.
    static func moveToApplications() throws {
        let source = bundleURL
        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        guard fm.isWritableFile(atPath: "/Applications") else {
            throw MoveError.failed(tr("Le dossier Applications n’est pas modifiable avec ce compte. Glissez Flick dans Applications depuis le Finder.",
                                      "The Applications folder isn’t writable with this account. Drag Flick into Applications from the Finder."))
        }
        if fm.fileExists(atPath: destination.path) {
            // An older Flick: quit it if it runs, then send it to the Trash.
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            where app.processIdentifier != getpid() {
                app.terminate()
            }
            try fm.trashItem(at: destination, resultingItemURL: nil)
        }
        do {
            try run("/usr/bin/ditto", [source.path, destination.path])
        } catch {
            throw MoveError.failed(tr("La copie dans Applications a échoué : \(error.localizedDescription)",
                                      "Copying to Applications failed: \(error.localizedDescription)"))
        }
        // The user already chose to open Flick; the installed copy shouldn't be quarantined again.
        try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", destination.path])

        let fromDiskImage = source.path.hasPrefix("/Volumes/")
        let volume = fromDiskImage ? "/Volumes/" + (source.pathComponents.dropFirst(2).first ?? "") : nil
        if !isOnDiskImageOrTranslocated { try? fm.trashItem(at: source, resultingItemURL: nil) }

        // Open the installed copy once this one has quit, then eject the disk image it came from.
        var script = "while kill -0 \"$0\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$1\""
        if let volume { script += "; sleep 1; /usr/bin/hdiutil detach \"$2\" -quiet" }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, String(getpid()), destination.path, volume ?? ""]
        try process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw MoveError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
