import Cocoa
import Foundation

let VERSION = "1.0.0"

class YBarApp: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var configPath: String?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusBar = StatusBarController(configPath: configPath)
        statusBar?.setup()
    }
}

class StatusBarController {
    private var window: NSWindow?
    private var clockLabel: NSTextField?
    private var workspaceLabel: NSTextField?
    private var timer: Timer?
    private var config: YBarConfig
    
    init(configPath: String? = nil) {
        self.config = YBarConfig(path: configPath)
    }
    
    func setup() {
        guard let screen = NSScreen.main else { return }
        
        let barHeight: CGFloat = config.height
        let windowRect = NSRect(x: 0, y: screen.frame.height - barHeight,
                               width: screen.frame.width, height: barHeight)
        
        window = NSWindow(contentRect: windowRect,
                         styleMask: [.borderless, .fullSizeContentView],
                         backing: .buffered,
                         defer: false)
        
        guard let window = window else { return }
        
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        window.isOpaque = false
        window.hasShadow = false
        window.backgroundColor = .clear
        
        let visualEffect = NSVisualEffectView()
        visualEffect.frame = window.contentView!.bounds
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.material = config.blur ? .hudWindow : .underWindowBackground
        visualEffect.state = .active
        visualEffect.blendingMode = .behindWindow
        visualEffect.alphaValue = config.opacity
        window.contentView = visualEffect
        
        setupLabels()
        updateClock()
        updateWorkspace()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.updateWorkspace()
        }
        
        window.makeKeyAndOrderFront(nil)
    }
    
    private func setupLabels() {
        guard let contentView = window?.contentView else { return }
        
        if config.showClock {
            clockLabel = NSTextField(frame: NSRect(x: contentView.bounds.width - 120,
                                                   y: 0,
                                                   width: 110,
                                                   height: contentView.bounds.height))
            clockLabel?.isBordered = false
            clockLabel?.isEditable = false
            clockLabel?.backgroundColor = .clear
            clockLabel?.textColor = config.textColor
            clockLabel?.font = NSFont.monospacedSystemFont(ofSize: config.fontSize, weight: .regular)
            clockLabel?.alignment = .right
            clockLabel?.autoresizingMask = [.minXMargin]
            contentView.addSubview(clockLabel!)
        }
        
        if config.showWorkspace {
            workspaceLabel = NSTextField(frame: NSRect(x: 10,
                                                       y: 0,
                                                       width: 200,
                                                       height: contentView.bounds.height))
            workspaceLabel?.isBordered = false
            workspaceLabel?.isEditable = false
            workspaceLabel?.backgroundColor = .clear
            workspaceLabel?.textColor = config.textColor
            workspaceLabel?.font = NSFont.systemFont(ofSize: config.fontSize, weight: .medium)
            workspaceLabel?.alignment = .left
            contentView.addSubview(workspaceLabel!)
        }
    }
    
    private func updateClock() {
        guard let clockLabel = clockLabel else { return }
        let formatter = DateFormatter()
        formatter.dateFormat = config.clockFormat
        clockLabel.stringValue = formatter.string(from: Date())
    }
    
    private func updateWorkspace() {
        guard let workspaceLabel = workspaceLabel else { return }
        
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
                workspaceLabel.stringValue = output.isEmpty ? "—" : "\(config.workspacePrefix)\(output)"
            } else {
                workspaceLabel.stringValue = "—"
            }
        } catch {
            workspaceLabel.stringValue = "—"
        }
    }
}

struct YBarConfig {
    var height: CGFloat = 24
    var opacity: CGFloat = 0.7
    var blur: Bool = true
    var showClock: Bool = true
    var showWorkspace: Bool = true
    var clockFormat: String = "HH:mm:ss"
    var fontSize: CGFloat = 13
    var textColor: NSColor = .white
    var workspacePrefix: String = ""
    
    init(path: String? = nil) {
        let configPath = path ?? NSString(string: "~/.ybar.conf").expandingTildeInPath
        loadConfig(from: configPath)
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
        --help              Show this help message
        --version           Show version information
        --conf <file>       Use specified configuration file
    
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
    default:
        print("Error: Unknown option '\(arg)'")
        printHelp()
        exit(1)
    }
    
    i += 1
}

app.run()
