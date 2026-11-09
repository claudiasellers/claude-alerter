import AppKit
import SwiftUI

/// A frosted card that sits on the desktop wallpaper layer (under your windows, above the icons),
/// visible on every Space. Drag it anywhere; position is remembered.
@MainActor
final class DesktopPanel {
    static let shared = DesktopPanel()
    private var panel: NSPanel?

    func show() {
        if panel == nil { panel = makePanel() }
        panel?.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 330, height: 400)
        let p = ClickablePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false

        let host = FirstMouseHostingView(rootView: DesktopCard(store: Store.shared))
        host.frame = NSRect(origin: .zero, size: size)
        p.contentView = host

        if !p.setFrameUsingName("ClaudeAlerterDesktopCard"), let screen = NSScreen.main {
            let v = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: v.maxX - size.width - 24, y: v.maxY - size.height - 24))
        }
        p.setFrameAutosaveName("ClaudeAlerterDesktopCard")
        return p
    }
}

private final class ClickablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct DesktopCard: View {
    let store: Store

    var body: some View {
        ThreadBoard(store: store, compact: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(VisualEffect().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 0.5)
            )
            .padding(1)
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
