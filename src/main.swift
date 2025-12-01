import Cocoa
import Foundation
import IOKit.ps

class YBarApp: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var configPath: String?
    var centerClock: Bool?
    var centerWorkspace: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(configPath: configPath, centerClock: centerClock, centerWorkspace: centerWorkspace)
        statusBar?.setup()
    }
}

class StatusBarController {
    private var windows: [NSWindow] = []
    private var clockLabels: [NSTextField] = []
    private var dateLabels: [NSTextField] = []
    private var workspaceLabels: [NSTextField] = []
    private var batteryLabels: [NSTextField] = []
    private var timer: Timer?
    private var config: YBarConfig

    init(configPath: String? = nil, centerClock: Bool? = nil, centerWorkspace: Bool? = nil) {
        self.config = YBarConfig(path: configPath, centerClock: centerClock, centerWorkspace: centerWorkspace)
    }

    func setup() {
        if let mainScreen = NSScreen.main {
            createWindowForScreen(mainScreen)
        }

        updateClock()
        updateWorkspace()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.updateWorkspace()
            self?.updateBattery()
        }

        // Listen for screen configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        // Remove existing windows
        for window in windows {
            window.close()
        }
        windows.removeAll()
        clockLabels.removeAll()
        dateLabels.removeAll()
        workspaceLabels.removeAll()
        batteryLabels.removeAll()

        // Recreate window on main screen
        if let mainScreen = NSScreen.main {
            createWindowForScreen(mainScreen)
        }

        // Update immediately
        updateClock()
        updateWorkspace()
        updateBattery()
    }

    private func createWindowForScreen(_ screen: NSScreen) {
        let barHeight: CGFloat = config.height
        let fullFrame = screen.frame

        // Position at the very top of the screen
        let windowRect = NSRect(x: fullFrame.origin.x,
                               y: fullFrame.origin.y + fullFrame.height - barHeight,
                               width: fullFrame.width,
                               height: barHeight)

        let window = NSWindow(contentRect: windowRect,
                             styleMask: [.borderless, .fullSizeContentView],
                             backing: .buffered,
                             defer: false,
                             screen: screen)

        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.setFrame(windowRect, display: true)

        let visualEffect = NSVisualEffectView()
        visualEffect.frame = window.contentView!.bounds
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = config.blur ? .hudWindow : .underWindowBackground
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.alphaValue = config.opacity
        window.contentView = visualEffect

        setupLabels(for: window, contentView: visualEffect)

        window.orderFrontRegardless()
        windows.append(window)
    }

    private func setupLabels(for window: NSWindow, contentView: NSView) {
        let bothCentered = config.showClock && config.showWorkspace && config.centerClock && config.centerWorkspace

        // Setup left-aligned workspace indicator
        if config.showWorkspace {
            let workspaceWidth: CGFloat = bothCentered ? 80 : 200
            let workspaceX: CGFloat
            let workspaceAlignment: NSTextAlignment

            if config.centerWorkspace {
                if bothCentered {
                    // Position to the left of center
                    workspaceX = (contentView.bounds.width / 2) - workspaceWidth - (config.padding / 2)
                } else {
                    workspaceX = (contentView.bounds.width - workspaceWidth) / 2
                }
                workspaceAlignment = .right
            } else {
                workspaceX = config.padding
                workspaceAlignment = .left
            }

            let workspaceLabel = NSTextField(frame: NSRect(x: workspaceX,
                                                           y: 0,
                                                           width: workspaceWidth,
                                                           height: contentView.bounds.height - config.padding))
            workspaceLabel.isBordered = false
            workspaceLabel.isEditable = false
            workspaceLabel.backgroundColor = .clear
            workspaceLabel.textColor = config.textColor
            workspaceLabel.font = config.getFont(size: config.fontSize, monospacedForClock: false)
            workspaceLabel.alignment = workspaceAlignment
            workspaceLabel.autoresizingMask = config.centerWorkspace ? [.minXMargin, .maxXMargin] : []
            workspaceLabel.lineBreakMode = .byClipping
            workspaceLabel.usesSingleLineMode = true
            workspaceLabel.cell?.truncatesLastVisibleLine = true
            contentView.addSubview(workspaceLabel)
            workspaceLabels.append(workspaceLabel)
        }
        
        // Setup right-aligned items using generic layout system
        setupRightAlignedItems(contentView: contentView)
    }
    
    private func setupRightAlignedItems(contentView: NSView) {
        // Define right-aligned items in display order (left to right)
        // Each item: (width, isMonospaced, labelArray)
        struct RightItem {
            let width: CGFloat
            let isMonospaced: Bool
            let alignment: NSTextAlignment
            let setupAction: (NSTextField) -> Void
        }
        
        var items: [RightItem] = []
        
        // Battery indicator
        items.append(RightItem(
            width: 60,
            isMonospaced: true,
            alignment: .right
        ) { [weak self] label in
            self?.batteryLabels.append(label)
        })
        
        // Date
        items.append(RightItem(
            width: 85,
            isMonospaced: true,
            alignment: .right
        ) { [weak self] label in
            self?.dateLabels.append(label)
        })
        
        // Clock (time)
        if config.showClock {
            items.append(RightItem(
                width: 45,
                isMonospaced: true,
                alignment: .right
            ) { [weak self] label in
                self?.clockLabels.append(label)
            })
        }
        
        // Calculate positions from right to left
        var currentX = contentView.bounds.width - config.padding - config.rightMargin
        
        for (index, item) in items.enumerated().reversed() {
            currentX -= item.width
            
            let label = NSTextField(frame: NSRect(x: currentX,
                                                   y: 0,
                                                   width: item.width,
                                                   height: contentView.bounds.height - config.padding))
            label.isBordered = false
            label.isEditable = false
            label.backgroundColor = .clear
            label.textColor = config.textColor
            label.font = config.getFont(size: config.fontSize, monospacedForClock: item.isMonospaced)
            // Only right-align the rightmost item, left-align others for tighter spacing
            label.alignment = (index == items.count - 1) ? item.alignment : .left
            label.autoresizingMask = [.minXMargin]
            label.lineBreakMode = .byClipping
            label.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true
            
            contentView.addSubview(label)
            item.setupAction(label)
            
            // Add spacing before the next item (unless this is the last item)
            if index > 0 {
                currentX -= config.itemSpacing
            }
        }
    }

    private func updateClock() {
        let formatter = DateFormatter()
        
        // Update date labels
        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        for dateLabel in dateLabels {
            dateLabel.stringValue = dateString
        }
        
        // Update time labels
        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: Date())
        for clockLabel in clockLabels {
            clockLabel.stringValue = timeString
        }
    }

    private func updateWorkspace() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["aerospace", "list-workspaces", "--focused"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let displayText = output.isEmpty ? "—" : "\(self.config.workspacePrefix)\(output)"
                    DispatchQueue.main.async {
                        for workspaceLabel in self.workspaceLabels {
                            workspaceLabel.stringValue = displayText
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        for workspaceLabel in self.workspaceLabels {
                            workspaceLabel.stringValue = "—"
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    for workspaceLabel in self.workspaceLabels {
                        workspaceLabel.stringValue = "—"
                    }
                }
            }
        }
    }
    
    private func updateBattery() {
        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef] else {
            return
        }
        
        for source in powerSources {
            guard let info = IOPSGetPowerSourceDescription(powerSourceInfo, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            
            let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let isPlugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            
            let chargingSymbol = (isCharging || isPlugged) ? "⚡" : ""
            let batteryText = String(format: "%@%02d%%", chargingSymbol, capacity)
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                for batteryLabel in self.batteryLabels {
                    batteryLabel.stringValue = batteryText
                }
            }
            break
        }
    }
}

struct YBarConfig {
    var height: CGFloat = 24
    var opacity: CGFloat = 0.7
    var blur: Bool = true
    var showClock: Bool = true
    var showWorkspace: Bool = true
    var clockFormat: String = "yyyy-MM-dd HH:mm"
    var fontSize: CGFloat = 13
    var fontFamily: String = "system"
    var textColor: NSColor = .white
    var workspacePrefix: String = ""
    var centerClock: Bool = false
    var centerWorkspace: Bool = false
    var padding: CGFloat = 10
    var itemSpacing: CGFloat = 10
    var rightMargin: CGFloat = 30

    init(path: String? = nil, centerClock: Bool? = nil, centerWorkspace: Bool? = nil) {
        let configPath = path ?? NSString(string: "~/.ybar.conf").expandingTildeInPath
        loadConfig(from: configPath)

        if let centerClock = centerClock {
            self.centerClock = centerClock
        }
        if let centerWorkspace = centerWorkspace {
            self.centerWorkspace = centerWorkspace
        }
    }

    private mutating func loadConfig(from path: String) {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return }

        let lines = content.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard parts.count == 2 else { continue }

            let key = parts[0]
            let value = parts[1]

            switch key {
            case "height":
                if let h = Double(value) { height = CGFloat(h) }
            case "opacity":
                if let o = Double(value) { opacity = min(1.0, max(0.0, CGFloat(o))) }
            case "blur":
                blur = value.lowercased() == "true" || value == "1"
            case "show_clock":
                showClock = value.lowercased() == "true" || value == "1"
            case "show_workspace":
                showWorkspace = value.lowercased() == "true" || value == "1"
            case "clock_format":
                clockFormat = value
            case "font_size":
                if let f = Double(value) { fontSize = CGFloat(f) }
            case "font_family":
                fontFamily = value
            case "text_color":
                if let color = parseColor(value) { textColor = color }
            case "workspace_prefix":
                workspacePrefix = value
            case "center_clock":
                centerClock = value.lowercased() == "true" || value == "1"
            case "center_workspace":
                centerWorkspace = value.lowercased() == "true" || value == "1"
            case "padding":
                if let p = Double(value) { padding = CGFloat(p) }
            case "item_spacing":
                if let s = Double(value) { itemSpacing = CGFloat(s) }
            case "right_margin":
                if let r = Double(value) { rightMargin = CGFloat(r) }
            default:
                break
            }
        }
    }

    private func parseColor(_ hex: String) -> NSColor? {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        return NSColor(red: r, green: g, blue: b, alpha: 1.0)
    }

    func getFont(size: CGFloat, monospacedForClock: Bool = false) -> NSFont {
        switch fontFamily.lowercased() {
        case "system":
            return monospacedForClock ?
                NSFont.monospacedSystemFont(ofSize: size, weight: .regular) :
                NSFont.systemFont(ofSize: size, weight: .medium)
        case "monospace", "monospaced":
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        default:
            // Try to use the specified font family, fallback to system if not found
            if let customFont = NSFont(name: fontFamily, size: size) {
                return customFont
            } else {
                return monospacedForClock ?
                    NSFont.monospacedSystemFont(ofSize: size, weight: .regular) :
                    NSFont.systemFont(ofSize: size, weight: .medium)
            }
        }
    }
}

func printHelp() {
    print("""
    ybar - A custom menubar replacement for macOS

    USAGE:
        ybar [OPTIONS]

    OPTIONS:
        --help                  Show this help message
        --version               Show version information
        --conf <file>           Use specified configuration file
        --center-clock          Center the clock on the bar
        --center-workspace      Center the workspace indicator on the bar

    CONFIGURATION:
        By default, ybar reads configuration from ~/.ybar.conf
        See man ybar for configuration options.
    """)
}

func printVersion() {
    print("ybar version \(VERSION)")
}

let app = NSApplication.shared
let delegate = YBarApp()
app.delegate = delegate

var args = CommandLine.arguments
args.removeFirst()

var i = 0
while i < args.count {
    let arg = args[i]

    switch arg {
    case "--help", "-h":
        printHelp()
        exit(0)
    case "--version", "-v":
        printVersion()
        exit(0)
    case "--conf", "-c":
        if i + 1 < args.count {
            delegate.configPath = args[i + 1]
            i += 1
        } else {
            print("Error: --conf requires a file path")
            exit(1)
        }
    case "--center-clock":
        delegate.centerClock = true
    case "--center-workspace":
        delegate.centerWorkspace = true
    default:
        print("Error: Unknown option '\(arg)'")
        printHelp()
        exit(1)
    }

    i += 1
}

app.run()
