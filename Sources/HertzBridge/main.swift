import AppKit
import CoreAudio
import ServiceManagement
import HertzBridgeCore

class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, SwitcherServiceDelegate {
    var statusItem: NSStatusItem!
    let switcher = SwitcherService.shared
    
    // UI Elements
    var statusMenu: NSMenu!
    var trackInfoItem: NSMenuItem!
    var trackFormatItem: NSMenuItem!
    var deviceInfoItem: NSMenuItem!
    var deviceFormatItem: NSMenuItem!
    var deviceListSubmenu: NSMenu!
    var overrideSubmenu: NSMenu!
    
    // Custom label references to bypass grey disabled text
    var trackInfoLabel: NSTextField!
    var trackFormatLabel: NSTextField!
    var deviceInfoLabel: NSTextField!
    var deviceFormatLabel: NSTextField!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            // Variable length allows tighter padding
            // (Layout Loop issue was caused by AnimationView, which is now gone)
            button.title = "—"
        }
        
        setupMenu()
        
        // Setup Switcher Service
        switcher.delegate = self
        
        switcher.start()
        
        // Initial Update
        refreshDeviceList()
    }
    
    func setupMenu() {
        statusMenu = NSMenu()
        statusMenu.delegate = self // To refresh device list on open
        
        // BRANDING HEADER
        let headerItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        _ = setupInfoItem(headerItem, title: "HertzBridge v1.5", isHeader: true)
        statusMenu.addItem(headerItem)
        statusMenu.addItem(NSMenuItem.separator())
        
        // SECTION 1: INFO
        trackInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        trackFormatItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        trackInfoLabel = setupInfoItem(trackInfoItem, title: "Track: Idle")
        trackFormatLabel = setupInfoItem(trackFormatItem, title: "-")
        
        statusMenu.addItem(trackInfoItem)
        statusMenu.addItem(trackFormatItem)
        statusMenu.addItem(NSMenuItem.separator())
        
        deviceInfoItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deviceFormatItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        deviceInfoLabel = setupInfoItem(deviceInfoItem, title: "Output: Default")
        deviceFormatLabel = setupInfoItem(deviceFormatItem, title: "-")
        
        statusMenu.addItem(deviceInfoItem)
        statusMenu.addItem(deviceFormatItem)
        statusMenu.addItem(NSMenuItem.separator())
        
        // SECTION: DEVICE SELECTION
        let deviceMenuItem = NSMenuItem(title: "Select Output Device", action: nil, keyEquivalent: "")
        deviceListSubmenu = NSMenu()
        deviceMenuItem.submenu = deviceListSubmenu
        statusMenu.addItem(deviceMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // SECTION: MANUAL CONTROL
        let overrideMenuItem = NSMenuItem(title: "Manual Sample Rate", action: nil, keyEquivalent: "")
        overrideSubmenu = NSMenu()
        
        let autoItem = NSMenuItem(title: "Auto-Detect", action: #selector(selectOverrideRate(_:)), keyEquivalent: "")
        autoItem.representedObject = nil
        overrideSubmenu.addItem(autoItem)
        overrideSubmenu.addItem(NSMenuItem.separator())
        
        // Common sample rates
        let rates: [Double] = [44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000]
        for rate in rates {
            let khz = Int(rate / 1000)
            let item = NSMenuItem(title: "\(khz)kHz", action: #selector(selectOverrideRate(_:)), keyEquivalent: "")
            item.representedObject = rate
            overrideSubmenu.addItem(item)
        }
        
        overrideMenuItem.submenu = overrideSubmenu
        statusMenu.addItem(overrideMenuItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        
        // SECTION: SETTINGS
        let autostartItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleAutostart(_:)), keyEquivalent: "")
        autostartItem.state = isLaunchAtLogin() ? .on : .off
        statusMenu.addItem(autostartItem)
        
        statusMenu.addItem(NSMenuItem.separator())
        statusMenu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        
        statusItem.menu = statusMenu
    }
    
    // Refresh Device List when menu opens
    func menuWillOpen(_ menu: NSMenu) {
        refreshDeviceList()
        refreshOverrideList()
    }
    
    func refreshDeviceList() {
        deviceListSubmenu.removeAllItems()
        
        // Option: System Default
        let defaultItem = NSMenuItem(title: "System Default", action: #selector(selectDevice(_:)), keyEquivalent: "")
        defaultItem.representedObject = nil // Nil means default
        if switcher.selectedDeviceID == nil { defaultItem.state = .on }
        deviceListSubmenu.addItem(defaultItem)
        
        deviceListSubmenu.addItem(NSMenuItem.separator())
        
        // List Hardware
        let devices = DeviceManager.shared.getAllOutputDevices()
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(selectDevice(_:)), keyEquivalent: "")
            item.representedObject = device.id
            if switcher.selectedDeviceID == device.id { item.state = .on }
            deviceListSubmenu.addItem(item)
        }
    }
    
    @objc func selectDevice(_ sender: NSMenuItem) {
        if let id = sender.representedObject as? AudioDeviceID {
            switcher.selectedDeviceID = id
            print("User selected device: \(id)")
        } else {
            switcher.selectedDeviceID = nil
            print("User selected System Default")
        }
        // Force refresh
        refreshDeviceList()
    }
    
    func refreshOverrideList() {
        let activeRate = switcher.manualOverrideRate
        for item in overrideSubmenu.items {
            if item.isSeparatorItem { continue }
            let itemRate = item.representedObject as? Double
            item.state = (itemRate == activeRate) ? .on : .off
        }
    }
    
    @objc func quit() {
        switcher.stop()
        NSApplication.shared.terminate(nil)
    }
    
    @objc func selectOverrideRate(_ sender: NSMenuItem) {
        if let rate = sender.representedObject as? Double {
            switcher.setManualOverride(rate: rate)
            print("User selected manual override: \(rate)Hz")
        } else {
            switcher.setManualOverride(rate: nil)
            print("User disabled manual override (auto-detect)")
        }
        refreshOverrideList()
    }
    
    @objc func toggleAutostart(_ sender: NSMenuItem) {
        let currentState = isLaunchAtLogin()
        setLaunchAtLogin(!currentState)
        sender.state = !currentState ? .on : .off
    }
    
    // Modern Login Items management (macOS 13+)
    func isLaunchAtLogin() -> Bool {
        return SMAppService.mainApp.status == .enabled
    }
    
    func setLaunchAtLogin(_ enable: Bool) {
        do {
            if enable {
                if SMAppService.mainApp.status == .enabled {
                    print("Already registered for launch at login")
                } else {
                    try SMAppService.mainApp.register()
                    print("Enabled launch at login")
                }
            } else {
                try SMAppService.mainApp.unregister()
                print("Disabled launch at login")
            }
        } catch {
            print("Failed to \(enable ? "enable" : "disable") launch at login: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Update UI
    private func setupInfoItem(_ item: NSMenuItem, title: String, isHeader: Bool = false) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = isHeader ? NSFont.systemFont(ofSize: 14, weight: .semibold) : NSFont.menuFont(ofSize: 14)
        label.textColor = isHeader ? NSColor.secondaryLabelColor : NSColor.labelColor
        label.isEditable = false
        label.isSelectable = false
        label.isBordered = false
        label.backgroundColor = .clear
        label.lineBreakMode = .byTruncatingTail
        label.sizeToFit()
        
        let view = NSView(frame: NSRect(x: 0, y: 0, width: label.frame.width + 37, height: 22))
        label.frame = NSRect(x: 21, y: 2, width: label.frame.width + 5, height: 18)
        view.addSubview(label)
        
        item.view = view
        return label
    }

    // SwitcherServiceDelegate
    func didUpdateStatus(track: String, trackFormat: String, device: String, deviceFormat: String) {
        DispatchQueue.main.async {
            self.trackInfoLabel.stringValue = "Track: \(track)"
            self.trackFormatLabel.stringValue = "\(trackFormat)"
            self.deviceInfoLabel.stringValue = "Output: \(device)"
            self.deviceFormatLabel.stringValue = "\(deviceFormat)"
            
            // Dynamically resize custom NSViews to fit long strings natively
            for label in [self.trackInfoLabel, self.trackFormatLabel, self.deviceInfoLabel, self.deviceFormatLabel] {
                guard let label = label, let view = label.superview else { continue }
                label.sizeToFit()
                
                // Set wide enough to hold the text + trailing padding
                let newWidth = max(label.frame.width + 37, 240) 
                
                // Update parent menu item frame
                view.frame = NSRect(x: 0, y: 0, width: newWidth, height: 22)
                label.frame = NSRect(x: 21, y: 2, width: newWidth - 21, height: 18) // ensure label fills available space and truncates if impossibly long natively
            }
            
            // Update menu bar (PLAIN TEXT)
            let components = deviceFormat.components(separatedBy: "Hz")
            if let hzString = components.first, let hz = Double(hzString) {
                let khz = Int(hz / 1000)
                self.statusItem.button?.title = "\(khz)k"
            } else {
                self.statusItem.button?.title = "—"
            }
        }
    }
}

// Entry point
@main
struct HertzBridgeApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
