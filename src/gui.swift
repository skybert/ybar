import Cocoa
import Foundation
import IOKit.ps

class YBarApp: NSObject, NSApplicationDelegate {
    var statusBar: StatusBarController?
    var configPath: String?
    var centerClock: Bool?
    var centerWorkspace: Bool?

    func applicationDidFinishLaunching(_: Notification) {
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
    private var isReconfiguring = false
    private let queue = DispatchQueue(label: "com.ybar.screenchange")
    private var workspaceTask: Process?
    private var initialScreen: NSScreen?

    init(configPath: String? = nil, centerClock: Bool? = nil, centerWorkspace: Bool? = nil) {
        config = YBarConfig(path: configPath, centerClock: centerClock, centerWorkspace: centerWorkspace)
    }

    func setup() {
        if let mainScreen = NSScreen.main {
            initialScreen = mainScreen
            createWindowForScreen(mainScreen)
        }

        updateClock()
        updateWorkspace()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateClock()
            self?.updateWorkspace()
            self?.updateBattery()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil,
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil,
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil,
        )
    }

    @objc private func screenParametersChanged() {
        // Defer the reconfiguration to avoid autoreleasepool issues
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // Prevent re-entry
            var alreadyReconfiguring = false
            queue.sync {
                alreadyReconfiguring = self.isReconfiguring
                if !alreadyReconfiguring {
                    self.isReconfiguring = true
                }
            }
            guard !alreadyReconfiguring else { return }

            // Stop timer first
            timer?.invalidate()
            timer = nil

            // Terminate any running workspace task
            if let task = workspaceTask, task.isRunning {
                task.terminate()
            }
            workspaceTask = nil

            // Order out windows instead of closing them to avoid autoreleasepool issues
            for window in windows {
                window.orderOut(nil)
            }
            windows = []
            clockLabels = []
            dateLabels = []
            workspaceLabels = []
            batteryLabels = []

            // Recreate
            if let screen = getValidScreen() {
                createWindowForScreen(screen)
            }

            queue.sync {
                self.isReconfiguring = false
            }

            // Restart timer
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.updateClock()
                self?.updateWorkspace()
                self?.updateBattery()
            }

            updateClock()
            updateWorkspace()
            updateBattery()
        }
    }

    @objc private func willSleep() {
        queue.sync {
            isReconfiguring = true
        }
        timer?.invalidate()
        timer = nil

        // Terminate any running workspace task
        workspaceTask?.terminate()
        workspaceTask = nil
    }

    @objc private func didWake() {
        queue.async { [weak self] in
            guard let self else { return }

            DispatchQueue.main.async {
                // Stop the old timer first to prevent it from accessing deallocated objects
                self.timer?.invalidate()
                self.timer = nil

                for window in self.windows {
                    window.orderOut(nil)
                }
                self.windows = []
                self.clockLabels = []
                self.dateLabels = []
                self.workspaceLabels = []
                self.batteryLabels = []

                if let screen = self.getValidScreen() {
                    self.createWindowForScreen(screen)
                }

                self.queue.sync {
                    self.isReconfiguring = false
                }

                self.timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                    self?.updateClock()
                    self?.updateWorkspace()
                    self?.updateBattery()
                }

                self.updateClock()
                self.updateWorkspace()
                self.updateBattery()
            }
        }
    }

    private func getValidScreen() -> NSScreen? {
        // Check if initialScreen is still valid (connected)
        if let initial = initialScreen, NSScreen.screens.contains(where: { $0 == initial }) {
            return initial
        }
        // Fall back to main screen if initial screen is disconnected
        return NSScreen.main
    }

    private func createWindowForScreen(_ screen: NSScreen) {
        let barHeight: CGFloat = config.height
        let fullFrame = screen.frame

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

    private func setupLabels(for _: NSWindow, contentView: NSView) {
        let bothCentered = config.showClock && config.showWorkspace && config.centerClock && config.centerWorkspace

        if config.showWorkspace {
            let workspaceWidth: CGFloat = bothCentered ? 80 : 200
            let workspaceX: CGFloat
            let workspaceAlignment: NSTextAlignment

            if config.centerWorkspace {
                if bothCentered {
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

        setupRightAlignedItems(contentView: contentView)
    }

    private func setupRightAlignedItems(contentView: NSView) {
        struct RightItem {
            let width: CGFloat
            let isMonospaced: Bool
            let alignment: NSTextAlignment
            let setupAction: (NSTextField) -> Void
        }

        var items: [RightItem] = []

        items.append(RightItem(
            width: 60,
            isMonospaced: true,
            alignment: .right,
        ) { [weak self] label in
            self?.batteryLabels.append(label)
        })

        items.append(RightItem(
            width: 85,
            isMonospaced: true,
            alignment: .right,
        ) { [weak self] label in
            self?.dateLabels.append(label)
        })

        if config.showClock {
            items.append(RightItem(
                width: 45,
                isMonospaced: true,
                alignment: .right,
            ) { [weak self] label in
                self?.clockLabels.append(label)
            })
        }

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
            label.alignment = (index == items.count - 1) ? item.alignment : .left
            label.autoresizingMask = [.minXMargin]
            label.lineBreakMode = .byClipping
            label.usesSingleLineMode = true
            label.cell?.truncatesLastVisibleLine = true

            contentView.addSubview(label)
            item.setupAction(label)

            if index > 0 {
                currentX -= config.itemSpacing
            }
        }
    }

    private func updateClock() {
        var shouldUpdate = false
        queue.sync {
            shouldUpdate = !isReconfiguring
        }
        guard shouldUpdate else { return }

        let formatter = DateFormatter()

        formatter.dateFormat = "yyyy-MM-dd"
        let dateString = formatter.string(from: Date())
        for dateLabel in dateLabels {
            dateLabel.stringValue = dateString
        }

        formatter.dateFormat = "HH:mm"
        let timeString = formatter.string(from: Date())
        for clockLabel in clockLabels {
            clockLabel.stringValue = timeString
        }
    }

    private func updateWorkspace() {
        var shouldUpdate = false
        queue.sync {
            shouldUpdate = !isReconfiguring
        }
        guard shouldUpdate else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }

            let task = Process()
            workspaceTask = task
            task.launchPath = "/usr/bin/env"
            task.arguments = ["aerospace", "list-workspaces", "--focused"]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                // Check if we're still valid after waiting
                var stillValid = false
                queue.sync {
                    stillValid = !self.isReconfiguring && self.workspaceTask === task
                }
                guard stillValid else { return }

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
                    let displayText = output.isEmpty ? "" : "\(config.workspacePrefix)\(output)"
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        var shouldUpdate = false
                        queue.sync {
                            shouldUpdate = !self.isReconfiguring
                        }
                        guard shouldUpdate else { return }

                        for workspaceLabel in workspaceLabels {
                            workspaceLabel.stringValue = displayText
                        }
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        var shouldUpdate = false
                        queue.sync {
                            shouldUpdate = !self.isReconfiguring
                        }
                        guard shouldUpdate else { return }

                        for workspaceLabel in workspaceLabels {
                            workspaceLabel.stringValue = ""
                        }
                    }
                }
            } catch {
                // If aerospace is not available, just show nothing
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    var shouldUpdate = false
                    queue.sync {
                        shouldUpdate = !self.isReconfiguring
                    }
                    guard shouldUpdate else { return }

                    for workspaceLabel in workspaceLabels {
                        workspaceLabel.stringValue = ""
                    }
                }
            }

            workspaceTask = nil
        }
    }

    private func updateBattery() {
        var shouldUpdate = false
        queue.sync {
            shouldUpdate = !isReconfiguring
        }
        guard shouldUpdate else { return }

        guard let powerSourceInfo = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let powerSources = IOPSCopyPowerSourcesList(powerSourceInfo)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return
        }

        for source in powerSources {
            guard let info = IOPSGetPowerSourceDescription(powerSourceInfo, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }

            let capacity = info[kIOPSCurrentCapacityKey] as? Int ?? 0
            let isCharging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let isPlugged = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue

            let chargingSymbol = (isCharging || isPlugged) ? "⚡" : "🔋"
            let batteryText = String(format: "%@%02d%%", chargingSymbol, capacity)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                for batteryLabel in batteryLabels {
                    batteryLabel.stringValue = batteryText
                }
            }
            break
        }
    }
}
