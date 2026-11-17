import AppKit
import SwiftUI

/// Welcome window shown at first launch (and while something essential is missing): installs Flick into
/// Applications if needed, then asks for Accessibility (required) and Screen Recording (for thumbnails).
@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {
    private static var shared: PermissionsWindowController?
    static let completedKey = "onboardingCompleted"

    /// First launch, missing Accessibility, or running from outside Applications.
    static var isNeeded: Bool {
        !UserDefaults.standard.bool(forKey: completedKey) || !Permissions.hasAccessibility || AppMover.shouldOffer
    }

    static func show() {
        NSApp.activate()
        if let shared {
            shared.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = PermissionsWindowController()
        shared = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    static func close() { shared?.close() }

    private init() {
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 560, height: 520),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = tr("Bienvenue dans Flick", "Welcome to Flick")
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        let host = NSHostingController(rootView: OnboardingView())
        host.sizingOptions = .preferredContentSize
        window.contentViewController = host
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func windowWillClose(_ notification: Notification) {
        Self.shared = nil
    }
}

struct OnboardingView: View {
    @State private var accessibility = Permissions.hasAccessibility
    @State private var screenRecording = Permissions.hasScreenRecording
    @State private var needsMove = AppMover.shouldOffer
    @State private var askedScreenRecording = false
    @State private var moveError: String?
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 76, height: 76)
                Text(tr("Bienvenue dans Flick", "Welcome to Flick")).font(.title.bold())
                Text(tr("Passez d’une fenêtre à l’autre en maintenant ⌥ et en appuyant sur ⇥. Encore quelques étapes et c’est prêt.",
                        "Switch between windows by holding ⌥ and pressing ⇥. Just a few steps and you’re ready."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 8)

            VStack(spacing: 10) {
                if needsMove {
                    StepCard(symbol: "folder.fill", tint: .blue,
                             title: tr("Installer dans Applications", "Install in Applications"),
                             detail: tr("Flick est ouvert depuis \(AppMover.isOnDiskImageOrTranslocated ? "l’image disque" : "un autre dossier"). Installé dans Applications, il garde ses autorisations et se met à jour.",
                                        "Flick is running from \(AppMover.isOnDiskImageOrTranslocated ? "the disk image" : "another folder"). Installed in Applications, it keeps its permissions and can update itself."),
                             badge: tr("Recommandé", "Recommended"), done: false) {
                        HStack(spacing: 8) {
                            Button(tr("Plus tard", "Not now")) {
                                UserDefaults.standard.set(true, forKey: AppMover.skipKey)
                                needsMove = false
                            }
                            .buttonStyle(.borderless)
                            Button(tr("Installer", "Install")) { move() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
                StepCard(symbol: "accessibility", tint: .indigo,
                         title: tr("Accessibilité", "Accessibility"),
                         detail: tr("Pour lister vos fenêtres et les activer, les fermer ou les réduire.",
                                    "To list your windows and focus, close or minimize them."),
                         badge: tr("Obligatoire", "Required"), done: accessibility) {
                    Button(tr("Autoriser…", "Allow…")) { Permissions.requestAccessibility() }
                        .buttonStyle(.borderedProminent)
                }
                StepCard(symbol: "rectangle.dashed.badge.record", tint: .pink,
                         title: tr("Enregistrement de l’écran", "Screen Recording"),
                         detail: tr("Pour les miniatures et l’aperçu des fenêtres. Sans elle, Flick montre les icônes des apps.",
                                    "For window thumbnails and previews. Without it, Flick shows app icons."),
                         badge: tr("Recommandé", "Recommended"), done: screenRecording) {
                    Button(tr("Autoriser…", "Allow…")) {
                        askedScreenRecording = true
                        Permissions.requestScreenRecording()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let moveError {
                Label(moveError, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            } else if askedScreenRecording && !screenRecording {
                Text(tr("Après avoir activé Flick dans Réglages Système, macOS peut demander de le relancer.",
                        "After turning Flick on in System Settings, macOS may ask you to relaunch it."))
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if accessibility {
                Label(tr("C’est prêt ! Maintenez ⌥ et appuyez sur ⇥ pour essayer.", "All set! Hold ⌥ and press ⇥ to try it."),
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green).font(.callout.weight(.medium))
            }

            HStack {
                if askedScreenRecording && !screenRecording {
                    Button(tr("Relancer Flick", "Relaunch Flick")) { AppDelegate.relaunch() }
                }
                Spacer()
                if accessibility {
                    Button(screenRecording ? tr("Commencer", "Get Started") : tr("Commencer sans miniatures", "Start without thumbnails")) {
                        UserDefaults.standard.set(true, forKey: PermissionsWindowController.completedKey)
                        PermissionsWindowController.close()
                    }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                } else {
                    Button(tr("Plus tard", "Later")) { PermissionsWindowController.close() }
                        .controlSize(.large)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 22)
        .frame(width: 560)
        .onReceive(timer) { _ in
            accessibility = Permissions.hasAccessibility
            screenRecording = Permissions.hasScreenRecording
        }
    }

    private func move() {
        do {
            try AppMover.moveToApplications()
        } catch {
            moveError = error.localizedDescription
        }
    }
}

/// One step of the welcome window: what it is for, and its button or a check mark once done.
private struct StepCard<Action: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    let badge: String
    let done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    if !done {
                        Text(badge)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(tint.opacity(0.15)))
                            .foregroundStyle(tint)
                    }
                }
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if done {
                Label(tr("Fait", "Done"), systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .foregroundStyle(.green)
                    .help(tr("Autorisé", "Allowed"))
            } else {
                action()
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(done ? Color.green.opacity(0.35) : Color.primary.opacity(0.08)))
    }
}
