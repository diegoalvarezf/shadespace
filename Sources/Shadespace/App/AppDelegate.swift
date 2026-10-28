import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NotchWindowController?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests use the app as host; don't take over the notch or touch other instances
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }

        // Kill any existing instance before taking over
        let running = NSWorkspace.shared.runningApplications
            .filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        running.forEach { $0.terminate() }

        NSApp.setActivationPolicy(.accessory)
        windowController = NotchWindowController()
        windowController?.show()
        setupStatusItem()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func makeStatusBarIcon() -> NSImage {
        let size = NSSize(width: 22, height: 13)
        let img = NSImage(size: size)
        img.lockFocus()

        // isTemplate uses the alpha channel only — draw opaque where we want color.
        // Pill: stroke only (transparent inside) + EQ bars filled inside.
        let pill = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: 21, height: 12),
                                xRadius: 6, yRadius: 6)
        pill.lineWidth = 1.2
        NSColor.black.setStroke()
        pill.stroke()

        // EQ bars
        let barW: CGFloat = 2.5
        let barSpacing: CGFloat = 2.0
        let heights: [CGFloat] = [5.5, 9, 6.5]
        let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * barSpacing
        var bx = (size.width - totalW) / 2
        for h in heights {
            let by = (size.height - h) / 2
            let bar = NSBezierPath(roundedRect: NSRect(x: bx, y: by, width: barW, height: h),
                                   xRadius: barW / 2, yRadius: barW / 2)
            NSColor.black.setFill()
            bar.fill()
            bx += barW + barSpacing
        }

        img.unlockFocus()
        return img
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = makeStatusBarIcon()
        statusItem?.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    private func toggleItem(_ title: String, _ isOn: Bool, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = isOn ? .on : .off
        return item
    }

    @objc private func chooseBotColor(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let color = BotColor(rawValue: raw) else { return }
        AppSettings.shared.botColor = color
    }
    @objc private func toggleClaudeCode() {
        if ClaudeCodeHooksInstaller.isInstalled() {
            ClaudeCodeConnection.disconnect()
        } else {
            ClaudeCodeConnection.connect()
        }
    }
    @objc private func toggleCompanion() { AppSettings.shared.companionEnabled.toggle() }
    @objc private func toggleLiveActivity() { AppSettings.shared.showLiveActivity.toggle() }
    @objc private func toggleLyrics() { AppSettings.shared.lyricsEnabled.toggle() }
    @objc private func toggleLyricsInNotch() { AppSettings.shared.lyricsInNotch.toggle() }
    @objc private func toggleWeather() { AppSettings.shared.weatherEnabled.toggle() }
    @objc private func toggleFahrenheit() { AppSettings.shared.useFahrenheit.toggle() }
    @objc private func toggleBatteryAlerts() { AppSettings.shared.batteryAlerts.toggle() }
    @objc private func toggleAirPodsAlerts() { AppSettings.shared.airPodsAlerts.toggle() }
    @objc private func toggleLaunchAtLogin() {
        AppSettings.shared.setLaunchAtLogin(!AppSettings.shared.launchAtLogin)
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on every open so checkmarks always reflect the current settings.
    func menuNeedsUpdate(_ menu: NSMenu) {
        let settings = AppSettings.shared
        menu.removeAllItems()

        menu.addItem(sectionHeader("Notch"))
        menu.addItem(toggleItem("Show Activity Below Notch", settings.showLiveActivity, #selector(toggleLiveActivity)))

        menu.addItem(toggleItem("Show Bot in Notch", settings.companionEnabled, #selector(toggleCompanion)))
        let colorItem = NSMenuItem(title: "Bot Color", action: nil, keyEquivalent: "")
        let colorMenu = NSMenu()
        for option in BotColor.allCases {
            let item = toggleItem(option.title, settings.botColor == option, #selector(chooseBotColor(_:)))
            item.representedObject = option.rawValue
            colorMenu.addItem(item)
        }
        colorItem.submenu = colorMenu
        menu.addItem(colorItem)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Claude Code"))
        menu.addItem(toggleItem("Connect Claude Code", ClaudeCodeHooksInstaller.isInstalled(),
                                #selector(toggleClaudeCode)))

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Music"))
        menu.addItem(toggleItem("Synced Lyrics", settings.lyricsEnabled, #selector(toggleLyrics)))
        let inNotch = toggleItem("Show Lyrics Below Notch", settings.lyricsInNotch, #selector(toggleLyricsInNotch))
        inNotch.isEnabled = settings.lyricsEnabled && settings.showLiveActivity
        menu.addItem(inNotch)

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Weather"))
        menu.addItem(toggleItem("Show Weather", settings.weatherEnabled, #selector(toggleWeather)))
        menu.addItem(toggleItem("Use Fahrenheit", settings.useFahrenheit, #selector(toggleFahrenheit)))

        menu.addItem(.separator())
        menu.addItem(sectionHeader("Alerts"))
        menu.addItem(toggleItem("Battery & Charging", settings.batteryAlerts, #selector(toggleBatteryAlerts)))
        menu.addItem(toggleItem("AirPods & Headphones", settings.airPodsAlerts, #selector(toggleAirPodsAlerts)))

        menu.addItem(.separator())
        menu.addItem(toggleItem("Launch at Login", settings.launchAtLogin, #selector(toggleLaunchAtLogin)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Shadespace", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        if #available(macOS 14, *) {
            return NSMenuItem.sectionHeader(title: title)
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
