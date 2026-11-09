import AppKit
import ServiceManagement
import SwiftUI

struct ClaudeAlerterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = Store.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if UserDefaults.standard.bool(forKey: "pinToDesktop") {
                DesktopPanel.shared.show()
            }
        }
    }
}

struct MenuBarLabel: View {
    let store: Store
    var body: some View {
        let ready = store.attention.count
        if ready > 0 {
            HStack(spacing: 3) {
                Image(systemName: "sparkles")
                Text("\(ready)")
            }
        } else if !store.working.isEmpty {
            Image(systemName: "hourglass")
        } else {
            Image(systemName: "sparkle")
        }
    }
}

struct MenuContent: View {
    let store: Store
    @AppStorage("pinToDesktop") private var pinToDesktop = false
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        VStack(spacing: 0) {
            ThreadBoard(store: store)
                .frame(maxHeight: 460)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.5)

            HStack(spacing: 14) {
                Toggle(isOn: $pinToDesktop) { Text("Pin to desktop") }
                    .onChange(of: pinToDesktop) { _, on in
                        on ? DesktopPanel.shared.show() : DesktopPanel.shared.hide()
                    }
                Toggle(isOn: $openAtLogin) { Text("Open at login") }
                    .onChange(of: openAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            openAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: 360)
    }
}
