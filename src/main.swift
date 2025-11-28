import Cocoa
import Foundation

let VERSION = "1.0.0"

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
    private var workspaceLabels: [NSTextField] = []
    private var timer: Timer?
    private var config: YBarConfig
    
    init(configPath: String? = nil, centerClock: Bool? = nil, centerWorkspace: Bool? = nil) {
        self.config = YBarConfig(path: configPath, centerClock: centerClock, centerWorkspace: centerWorkspace)
    }
    
    func setup() {
        for screen in NSScreen.screens {
            createWindowForScreen(screen)
        }
        
        updateClock()
        updateWorkspace()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.updateWorkspace()
        }
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
        if config.showClock {
            let clockWidth: CGFloat = 170
            let clockX: CGFloat
            let clockAlignment: NSTextAlignment
            
            if config.centerClock {
                clockX = (contentView.bounds.width - clockWidth) / 2
                clockAlignment = .center
            } else {
                clockX = contentView.bounds.width - clockWidth - config.padding
                clockAlignment = .right
            }
            
            let clockLabel = NSTextField(frame: NSRect(x: clockX,
                                                       y: config.padding / 2,
                                                       width: clockWidth,
                                                       height: contentView.bounds.height - config.padding))
            clockLabel.isBordered = false
            clockLabel.isEditable = false
            clockLabel.backgroundColor = .clear
            clockLabel.textColor = config.textColor
            clockLabel.font = NSFont.monospacedSystemFont(ofSize: config.fontSize, weight: .regular)
            clockLabel.alignment = clockAlignment
            clockLabel.autoresizingMask = config.centerClock ? [.minXMargin, .maxXMargin] : [.minXMargin]
            contentView.addSubview(clockLabel)
            clockLabels.append(clockLabel)
        }
        
        if config.showWorkspace {
            let workspaceWidth: CGFloat = 200
            let workspaceX: CGFloat
            let workspaceAlignment: NSTextAlignment
            
            if config.centerWorkspace {
                workspaceX = (contentView.bounds.width - workspaceWidth) / 2
                workspaceAlignment = .center
            } else {
                workspaceX = config.padding
                workspaceAlignment = .left
            }
            
            let workspaceLabel = NSTextField(frame: NSRect(x: workspaceX,
                                                           y: config.padding / 2,
                                                           width: workspaceWidth,
                                                           height: contentView.bounds.height - config.padding))
            workspaceLabel.isBordered = false
            workspaceLabel.isEditable = false
            workspaceLabel.backgroundColor = .clear
            workspaceLabel.textColor = config.textColor
            workspaceLabel.font = NSFont.systemFont(ofSize: config.fontSize, weight: .medium)
            workspaceLabel.alignment = workspaceAlignment
            workspaceLabel.autoresizingMask = config.centerWorkspace ? [.minXMargin, .maxXMargin] : []
            contentView.addSubview(workspaceLabel)
            workspaceLabels.append(workspaceLabel)
        }
    }
    
    private func updateClock() {
        let formatter = DateFormatter()
        formatter.dateFormat = config.clockFormat
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
}

struct YBarConfig {
    var height: CGFloat = 24
    var opacity: CGFloat = 0.7
    var blur: Bool = true
    var showClock: Bool = true
    var showWorkspace: Bool = true
    var clockFormat: String = "yyyy-MM-dd HH:mm"
    var fontSize: CGFloat = 13
    var textColor: NSColor = .white
    var workspacePrefix: String = ""
    var centerClock: Bool = false
    var centerWorkspace: Bool = false
    var padding: CGFloat = 10
    
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
