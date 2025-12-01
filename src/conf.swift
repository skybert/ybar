import Cocoa
import Foundation

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
    var rightMargin: CGFloat = 20

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
