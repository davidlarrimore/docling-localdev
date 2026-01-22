import Cocoa
import Foundation

// MARK: - Data Models

struct AppConfig: Codable {
    var baseURL: String
    var pollIntervalSeconds: Double
    var doclingInstallPath: String?
    var autoStartOnLaunch: Bool

    static let `default` = AppConfig(
        baseURL: "http://127.0.0.1:5001",
        pollIntervalSeconds: 3.0,
        doclingInstallPath: nil,
        autoStartOnLaunch: true
    )
}

enum ServerStatus {
    case offline
    case starting
    case online
    case stopping

    var displayText: String {
        switch self {
        case .offline: return "Server: Offline"
        case .starting: return "Server: Starting..."
        case .online: return "Server: Online"
        case .stopping: return "Server: Stopping..."
        }
    }

    var color: NSColor {
        switch self {
        case .offline: return .systemRed
        case .starting, .stopping: return .systemOrange
        case .online: return .systemGreen
        }
    }
}

// MARK: - Installation Finder

final class DoclingInstallationFinder {
    private let scriptName = "run-docling-local-apple-silicon.sh"

    private let commonLocations: [String] = [
        "~/Documents/Github/docling",
        "~/Documents/docling",
        "~/Developer/docling",
        "~/Projects/docling",
        "/opt/docling",
        "/usr/local/docling"
    ]

    func findInstallation() -> URL? {
        // Priority 1: Check app bundle's parent directory
        if let bundlePath = checkAppBundleParent() {
            return bundlePath
        }

        // Priority 2: Search common locations
        if let found = searchCommonLocations() {
            return found
        }

        return nil
    }

    private func checkAppBundleParent() -> URL? {
        guard let bundlePath = Bundle.main.bundlePath as NSString? else {
            return nil
        }

        // App is at: /path/to/docling/build/DoclingMenuBar.app
        // We want: /path/to/docling
        let appDir = (bundlePath as NSString).deletingLastPathComponent
        let buildDir = (appDir as NSString).deletingLastPathComponent
        let parentDir = URL(fileURLWithPath: buildDir)

        if findRunScript(in: parentDir) != nil {
            return parentDir
        }

        // Also check direct parent (if app is directly in docling folder)
        let directParent = URL(fileURLWithPath: appDir)
        if findRunScript(in: directParent) != nil {
            return directParent
        }

        return nil
    }

    private func searchCommonLocations() -> URL? {
        let fileManager = FileManager.default

        for location in commonLocations {
            let expanded = NSString(string: location).expandingTildeInPath
            let url = URL(fileURLWithPath: expanded)

            if fileManager.fileExists(atPath: url.path), findRunScript(in: url) != nil {
                return url
            }
        }

        return nil
    }

    func findRunScript(in directory: URL) -> URL? {
        let scriptPath = directory.appendingPathComponent(scriptName)
        let fileManager = FileManager.default

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: scriptPath.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }

        guard fileManager.isExecutableFile(atPath: scriptPath.path) else {
            return nil
        }

        return scriptPath
    }
}

// MARK: - Process Manager

final class ProcessManager {
    private var process: Process?
    private var outputPipe: Pipe?
    private var logBuffer = Data()

    var onLogLine: ((String) -> Void)?
    var onStatusChange: ((ServerStatus) -> Void)?

    private(set) var status: ServerStatus = .offline {
        didSet {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.onStatusChange?(self.status)
            }
        }
    }

    var isRunning: Bool {
        process?.isRunning ?? false
    }

    func start(scriptPath: URL, workingDirectory: URL) {
        guard !isRunning else { return }
        status = .starting

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "exec \"\(scriptPath.path)\""]
        process.currentDirectoryURL = workingDirectory

        // Capture stdout/stderr via Pipe (no terminal window)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        // Inherit environment for PATH, etc.
        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        process.environment = env

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.handleLogData(data)
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.status = .offline
            }
        }

        do {
            try process.run()
            self.process = process
            self.outputPipe = pipe
        } catch {
            print("Failed to start process: \(error)")
            status = .offline
        }
    }

    func stop() {
        guard let process = process else {
            forceKillFallback()
            status = .offline
            return
        }

        status = .stopping

        if process.isRunning {
            // Step 1: SIGTERM for graceful shutdown
            process.terminate()

            // Step 2: Wait up to 2 seconds
            DispatchQueue.global().async { [weak self] in
                let deadline = Date().addingTimeInterval(2.0)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }

                // Step 3: SIGINT if still running
                if process.isRunning {
                    process.interrupt()
                    Thread.sleep(forTimeInterval: 0.5)
                }

                // Step 4: SIGKILL as last resort
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }

                // Step 5: pkill fallback
                self?.forceKillFallback()

                DispatchQueue.main.async {
                    self?.process = nil
                    self?.outputPipe = nil
                    self?.status = .offline
                }
            }
        } else {
            forceKillFallback()
            self.process = nil
            self.outputPipe = nil
            status = .offline
        }
    }

    func restart(scriptPath: URL, workingDirectory: URL) {
        stop()

        // Wait for stop to complete, then start
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            self?.start(scriptPath: scriptPath, workingDirectory: workingDirectory)
        }
    }

    private func forceKillFallback() {
        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-f", "docling-serve run"]
        pkill.standardOutput = FileHandle.nullDevice
        pkill.standardError = FileHandle.nullDevice
        try? pkill.run()
        pkill.waitUntilExit()
    }

    private func handleLogData(_ data: Data) {
        logBuffer.append(data)

        // Process complete lines
        while let newlineRange = logBuffer.range(of: Data([0x0A])) {
            let lineData = logBuffer.subdata(in: logBuffer.startIndex..<newlineRange.lowerBound)
            logBuffer.removeSubrange(logBuffer.startIndex...newlineRange.lowerBound)

            if let line = String(data: lineData, encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.onLogLine?(line)
                }
            }
        }
    }
}

// MARK: - Health Checker

final class HealthChecker {
    private let session: URLSession
    private let baseURL: URL
    private var timer: Timer?

    var onStatusChange: ((Bool) -> Void)?

    init(baseURL: URL) {
        self.baseURL = baseURL

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 5.0
        config.timeoutIntervalForResource = 5.0
        self.session = URLSession(configuration: config)
    }

    func startPolling(interval: TimeInterval) {
        stopPolling()

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkNow { _ in }
        }
        timer?.tolerance = 0.5

        // Immediate first check
        checkNow { _ in }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func checkNow(completion: @escaping (Bool) -> Void) {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        session.dataTask(with: request) { [weak self] _, response, error in
            let isOnline = (response as? HTTPURLResponse)?.statusCode == 200 && error == nil
            DispatchQueue.main.async {
                self?.onStatusChange?(isOnline)
                completion(isOnline)
            }
        }.resume()
    }
}

// MARK: - Status Bar Controller

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu

    private let processManager: ProcessManager
    private let healthChecker: HealthChecker
    private var config: AppConfig
    private let installPath: URL?

    private var serverStatus: ServerStatus = .offline {
        didSet {
            updateStatusIndicator()
        }
    }

    init(processManager: ProcessManager, healthChecker: HealthChecker, config: AppConfig, installPath: URL?) {
        self.processManager = processManager
        self.healthChecker = healthChecker
        self.config = config
        self.installPath = installPath

        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()

        setupStatusItem()
        setupCallbacks()

        healthChecker.startPolling(interval: config.pollIntervalSeconds)
    }

    private func setupStatusItem() {
        guard let button = statusItem.button else { return }

        button.title = " Docling"
        button.imagePosition = .imageLeft

        statusItem.menu = menu
        menu.delegate = self

        updateStatusIndicator()
    }

    private func setupCallbacks() {
        processManager.onStatusChange = { [weak self] status in
            if status == .starting {
                self?.serverStatus = .starting
            } else if status == .stopping {
                self?.serverStatus = .stopping
            } else if status == .offline {
                self?.serverStatus = .offline
            }
        }

        healthChecker.onStatusChange = { [weak self] isOnline in
            guard let self = self else { return }
            if isOnline {
                self.serverStatus = .online
            } else if self.processManager.isRunning {
                if self.serverStatus != .starting && self.serverStatus != .stopping {
                    self.serverStatus = .starting
                }
            } else {
                self.serverStatus = .offline
            }
        }
    }

    private func updateStatusIndicator() {
        guard let button = statusItem.button else { return }

        // Create colored circle image
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size, flipped: false) { rect in
            self.serverStatus.color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }

        button.image = image
        button.toolTip = serverStatus.displayText
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        // Status header
        let statusMenuItem = NSMenuItem(title: serverStatus.displayText, action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        menu.addItem(.separator())

        // Service controls
        let startItem = NSMenuItem(title: "Start Service", action: #selector(startService), keyEquivalent: "")
        startItem.target = self
        startItem.isEnabled = (serverStatus == .offline) && (installPath != nil)
        menu.addItem(startItem)

        let stopItem = NSMenuItem(title: "Stop Service", action: #selector(stopService), keyEquivalent: "")
        stopItem.target = self
        stopItem.isEnabled = (serverStatus == .online || serverStatus == .starting)
        menu.addItem(stopItem)

        let restartItem = NSMenuItem(title: "Restart Service", action: #selector(restartService), keyEquivalent: "r")
        restartItem.target = self
        restartItem.isEnabled = (serverStatus == .online) && (installPath != nil)
        menu.addItem(restartItem)

        menu.addItem(.separator())

        // Quick actions
        let openUI = NSMenuItem(title: "Open Docling UI", action: #selector(openDoclingUI), keyEquivalent: "o")
        openUI.target = self
        openUI.isEnabled = (serverStatus == .online)
        menu.addItem(openUI)

        let openWebsite = NSMenuItem(title: "Open Docling Website", action: #selector(openDoclingWebsite), keyEquivalent: "")
        openWebsite.target = self
        menu.addItem(openWebsite)

        menu.addItem(.separator())

        // Installation path info
        if let path = installPath {
            let pathItem = NSMenuItem(title: "Install: \(path.lastPathComponent)", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            pathItem.toolTip = path.path
            menu.addItem(pathItem)
        } else {
            let pathItem = NSMenuItem(title: "Install: Not found", action: nil, keyEquivalent: "")
            pathItem.isEnabled = false
            pathItem.toolTip = "Could not auto-detect Docling installation"
            menu.addItem(pathItem)
        }

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func startService() {
        guard let path = installPath else { return }
        let scriptPath = path.appendingPathComponent("run-docling-local-apple-silicon.sh")
        processManager.start(scriptPath: scriptPath, workingDirectory: path)
    }

    @objc private func stopService() {
        processManager.stop()
    }

    @objc private func restartService() {
        guard let path = installPath else { return }
        let scriptPath = path.appendingPathComponent("run-docling-local-apple-silicon.sh")
        processManager.restart(scriptPath: scriptPath, workingDirectory: path)
    }

    @objc private func openDoclingUI() {
        if let url = URL(string: "\(config.baseURL)/ui") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func openDoclingWebsite() {
        if let url = URL(string: "https://www.docling.ai/") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - Config Manager

final class ConfigManager {
    private let fileManager = FileManager.default
    private let configURL: URL

    init() {
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DoclingMenuBar", isDirectory: true)

        try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)

        configURL = supportDir.appendingPathComponent("config.json")
    }

    func load() -> AppConfig {
        if let data = try? Data(contentsOf: configURL),
           let config = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return config
        }

        let defaultConfig = AppConfig.default
        save(defaultConfig)
        return defaultConfig
    }

    func save(_ config: AppConfig) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        if let data = try? encoder.encode(config) {
            try? data.write(to: configURL)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusBarController: StatusBarController?
    private var processManager: ProcessManager?
    private let configManager = ConfigManager()
    private let installationFinder = DoclingInstallationFinder()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load configuration
        var config = configManager.load()

        // Auto-detect Docling installation
        let installPath: URL?

        if let configuredPath = config.doclingInstallPath {
            let url = URL(fileURLWithPath: configuredPath)
            if installationFinder.findRunScript(in: url) != nil {
                installPath = url
            } else {
                // Config path is invalid, try auto-detection
                installPath = installationFinder.findInstallation()
            }
        } else {
            installPath = installationFinder.findInstallation()
        }

        // Save detected path to config for future use
        if let path = installPath, config.doclingInstallPath == nil {
            config.doclingInstallPath = path.path
            configManager.save(config)
        }

        // Initialize process manager
        let processManager = ProcessManager()
        processManager.onLogLine = { line in
            print("[Docling] \(line)")
        }
        self.processManager = processManager

        // Initialize health checker
        guard let baseURL = URL(string: config.baseURL) else {
            print("Invalid base URL: \(config.baseURL)")
            return
        }
        let healthChecker = HealthChecker(baseURL: baseURL)

        // Create status bar controller
        statusBarController = StatusBarController(
            processManager: processManager,
            healthChecker: healthChecker,
            config: config,
            installPath: installPath
        )

        // Auto-start if enabled
        if config.autoStartOnLaunch, let path = installPath {
            let scriptPath = path.appendingPathComponent("run-docling-local-apple-silicon.sh")

            // Small delay to let UI initialize
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                processManager.start(scriptPath: scriptPath, workingDirectory: path)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop the Docling process before app exits
        processManager?.stop()

        // Give it a moment to clean up
        Thread.sleep(forTimeInterval: 0.5)
    }
}

// MARK: - Main Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate

// Don't show in Dock (backup for Info.plist LSUIElement)
app.setActivationPolicy(.accessory)

app.run()
