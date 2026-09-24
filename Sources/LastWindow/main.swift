import AppKit
import ApplicationServices
import LastWindowCore
import ServiceManagement
import os

private let log = Logger(subsystem: "com.adamstahl.LastWindow", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let watcher = WindowWatcher()
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    private var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "enabled"); watcher.isEnabled = newValue }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "LastWindow")
        menu.delegate = self
        statusItem.menu = menu

        watcher.isEnabled = isEnabled
        reloadConfig()

        // Literal value of kAXTrustedCheckOptionPrompt, which Swift 6 flags as shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            watcher.start()
        } else {
            Task {
                while !AXIsProcessTrusted() {
                    try? await Task.sleep(for: .seconds(2))
                }
                watcher.start()
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if AXIsProcessTrusted() {
            let status = NSMenuItem(title: "Accessibility: granted", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        } else {
            menu.addItem(item("Accessibility: needs permission — click to grant", #selector(openAccessibilitySettings)))
        }
        menu.addItem(.separator())

        let enabled = item("Enabled", #selector(toggleEnabled))
        enabled.state = isEnabled ? .on : .off
        menu.addItem(enabled)

        let login = item("Launch at Login", #selector(toggleLaunchAtLogin))
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())
        menu.addItem(item("Open Config…", #selector(openConfig)))
        menu.addItem(item("Reload Config", #selector(reloadConfig)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit LastWindow", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            showError("Couldn't change Launch at Login", error)
        }
    }

    @objc private func openConfig() {
        NSWorkspace.shared.open(Config.defaultURL)
    }

    @objc private func reloadConfig() {
        do {
            let config = try Config.loadOrCreate()
            watcher.excluded = Set(config.excluded)
            log.info("Loaded config with \(config.excluded.count) exclusions")
        } catch {
            showError("Couldn't read \(Config.defaultURL.path)", error)
        }
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    private func showError(_ message: String, _ error: Error) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error.localizedDescription
        NSApp.activate()
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
