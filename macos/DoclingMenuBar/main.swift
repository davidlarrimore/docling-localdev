import Cocoa

struct AppConfig: Codable {
    var baseURL: String
    var apiKey: String?
    var pollSeconds: Double
    var serviceScriptPath: String
    var serviceWorkingDirectory: String?
}

struct TaskProcessingMeta: Codable {
    var num_docs: Int
    var num_processed: Int?
    var num_succeeded: Int?
    var num_failed: Int?
}

struct TaskStatusResponse: Codable {
    var task_id: String
    var task_type: String?
    var task_status: String
    var task_position: Int?
    var task_meta: TaskProcessingMeta?
}

struct TrackedTask: Codable, Hashable {
    var id: String
    var status: String?
    var completed: Bool
    var updatedAt: Date?
}

final class TaskStore {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    func load() -> [TrackedTask] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        return (try? JSONDecoder().decode([TrackedTask].self, from: data)) ?? []
    }

    func save(_ tasks: [TrackedTask]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(tasks) else {
            return
        }
        try? data.write(to: fileURL, options: [.atomic])
    }
}

final class DoclingClient {
    private let baseURL: URL
    private let apiKey: String?
    private let session: URLSession

    init(baseURL: URL, apiKey: String?) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = URLSession(configuration: .default)
    }

    func fetchHealth(completion: @escaping (Bool) -> Void) {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        session.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse {
                completion(http.statusCode == 200 && error == nil)
                return
            }
            completion(false)
        }.resume()
    }

    func fetchStatus(taskID: String, completion: @escaping (Result<TaskStatusResponse, Error>) -> Void) {
        let url = baseURL.appendingPathComponent("v1/status/poll/")
            .appendingPathComponent(taskID)
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty {
            request.addValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        }
        session.dataTask(with: request) { data, _, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let data else {
                completion(.failure(NSError(domain: "DoclingMenuBar", code: 1, userInfo: nil)))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(TaskStatusResponse.self, from: data)
                completion(.success(decoded))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}

final class StatusBarController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let taskStore: TaskStore
    private let client: DoclingClient
    private let config: AppConfig
    private let serviceIsRunning: () -> Bool
    private let startServiceHandler: () -> Void
    private let stopServiceHandler: () -> Void
    private var tasks: [TrackedTask]
    private var isServerOnline = false
    private var timer: Timer?

    init(
        taskStore: TaskStore,
        client: DoclingClient,
        config: AppConfig,
        serviceIsRunning: @escaping () -> Bool,
        startServiceHandler: @escaping () -> Void,
        stopServiceHandler: @escaping () -> Void
    ) {
        self.taskStore = taskStore
        self.client = client
        self.config = config
        self.serviceIsRunning = serviceIsRunning
        self.startServiceHandler = startServiceHandler
        self.stopServiceHandler = stopServiceHandler
        self.tasks = taskStore.load()
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()

        super.init()

        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: "Docling")
        statusItem.button?.imagePosition = .imageLeft
        statusItem.button?.title = "Docling"
        statusItem.button?.toolTip = "Docling: loading"

        startPolling()
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func startPolling() {
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: config.pollSeconds, repeats: true) { [weak self] _ in
            self?.refreshStatus()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func refreshStatus() {
        client.fetchHealth { [weak self] online in
            DispatchQueue.main.async {
                self?.isServerOnline = online
                self?.updateStatusTitle()
            }
        }

        let activeTasks = tasks.filter { !$0.completed }
        if activeTasks.isEmpty {
            DispatchQueue.main.async {
                self.updateStatusTitle()
            }
            return
        }

        let group = DispatchGroup()
        var updatedTasks = tasks

        for (index, task) in updatedTasks.enumerated() where !task.completed {
            group.enter()
            client.fetchStatus(taskID: task.id) { result in
                switch result {
                case .success(let response):
                    let status = response.task_status
                    let completed = StatusBarController.isCompleted(status)
                    updatedTasks[index].status = status
                    updatedTasks[index].completed = completed
                    updatedTasks[index].updatedAt = Date()
                case .failure:
                    break
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            self.tasks = updatedTasks
            self.taskStore.save(updatedTasks)
            self.updateStatusTitle()
        }
    }

    private func updateStatusTitle() {
        let activeCount = tasks.filter { !$0.completed }.count
        let serverLabel = isServerOnline ? "online" : "offline"
        statusItem.button?.title = activeCount > 0 ? "Docling \(activeCount)" : "Docling"
        statusItem.button?.toolTip = "Docling: \(serverLabel), \(activeCount) active task(s)"
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let header = NSMenuItem(title: "Docling Status", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let serverLabel = isServerOnline ? "Server: online" : "Server: offline"
        let serverItem = NSMenuItem(title: serverLabel, action: nil, keyEquivalent: "")
        serverItem.isEnabled = false
        menu.addItem(serverItem)

        menu.addItem(.separator())

        let serviceRunning = serviceIsRunning()
        let serviceTitle = serviceRunning ? "Stop Service" : "Start Service"
        let serviceItem = NSMenuItem(title: serviceTitle, action: #selector(toggleService), keyEquivalent: "s")
        serviceItem.target = self
        menu.addItem(serviceItem)

        let openUI = NSMenuItem(title: "Open UI", action: #selector(openUI), keyEquivalent: "o")
        openUI.target = self
        menu.addItem(openUI)

        let addTask = NSMenuItem(title: "Add Task ID", action: #selector(promptAddTask), keyEquivalent: "a")
        addTask.target = self
        menu.addItem(addTask)

        let addFromClipboard = NSMenuItem(title: "Add Task ID From Clipboard", action: #selector(addTaskFromClipboard), keyEquivalent: "")
        addFromClipboard.target = self
        menu.addItem(addFromClipboard)

        let clearCompleted = NSMenuItem(title: "Clear Completed", action: #selector(clearCompletedTasks), keyEquivalent: "c")
        clearCompleted.target = self
        menu.addItem(clearCompleted)

        menu.addItem(.separator())

        let activeTasks = tasks.filter { !$0.completed }
        if activeTasks.isEmpty {
            let noneItem = NSMenuItem(title: "No active tasks", action: nil, keyEquivalent: "")
            noneItem.isEnabled = false
            menu.addItem(noneItem)
        } else {
            for task in activeTasks {
                let title = "\(shortID(task.id)) — \(task.status ?? "unknown")"
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    @objc private func openUI() {
        guard let url = URL(string: config.baseURL + "/ui") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func toggleService() {
        if serviceIsRunning() {
            stopServiceHandler()
        } else {
            startServiceHandler()
        }
        refreshStatus()
    }

    @objc private func promptAddTask() {
        let alert = NSAlert()
        alert.messageText = "Add Docling Task ID"
        alert.informativeText = "Paste a task_id returned by an async request."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        alert.accessoryView = input
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        addTask(id: input.stringValue)
    }

    @objc private func addTaskFromClipboard() {
        let pasteboard = NSPasteboard.general
        if let value = pasteboard.string(forType: .string) {
            addTask(id: value)
        }
    }

    private func addTask(id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if tasks.contains(where: { $0.id == trimmed }) {
            return
        }
        tasks.append(TrackedTask(id: trimmed, status: "queued", completed: false, updatedAt: Date()))
        taskStore.save(tasks)
        refreshStatus()
    }

    func addTaskFromLog(id: String) {
        addTask(id: id)
    }

    @objc private func clearCompletedTasks() {
        tasks.removeAll { $0.completed }
        taskStore.save(tasks)
        updateStatusTitle()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private static func isCompleted(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "completed" || normalized == "succeeded" || normalized == "success" ||
            normalized == "failed" || normalized == "error" || normalized == "canceled" || normalized == "cancelled"
    }

    private func shortID(_ id: String) -> String {
        if id.count <= 10 { return id }
        let prefix = id.prefix(6)
        let suffix = id.suffix(4)
        return "\(prefix)...\(suffix)"
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var serviceProcess: Process?
    private var logBuffer = Data()
    private let taskIDRegex = try! NSRegularExpression(
        pattern: "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let fileManager = FileManager.default
        let supportDir = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DoclingMenuBar", isDirectory: true)
        try? fileManager.createDirectory(at: supportDir, withIntermediateDirectories: true)

        let configURL = supportDir.appendingPathComponent("config.json")
        let taskURL = supportDir.appendingPathComponent("tasks.json")

        let config = loadConfig(from: configURL)
        startService(with: config)
        let client = DoclingClient(baseURL: URL(string: config.baseURL)!, apiKey: config.apiKey)
        let store = TaskStore(fileURL: taskURL)

        controller = StatusBarController(
            taskStore: store,
            client: client,
            config: config,
            serviceIsRunning: { [weak self] in
                self?.serviceProcess?.isRunning ?? false
            },
            startServiceHandler: { [weak self] in
                self?.startService(with: config)
            },
            stopServiceHandler: { [weak self] in
                self?.stopService()
            }
        )
    }

    private func loadConfig(from url: URL) -> AppConfig {
        let defaultConfig = AppConfig(
            baseURL: "http://127.0.0.1:5001",
            apiKey: nil,
            pollSeconds: 5,
            serviceScriptPath: "/Users/davidlarrimore/Documents/Github/docling/run-docling.sh",
            serviceWorkingDirectory: "/Users/davidlarrimore/Documents/Github/docling"
        )
        guard let data = try? Data(contentsOf: url) else {
            return defaultConfig
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? defaultConfig
    }

    private func startService(with config: AppConfig) {
        if serviceProcess?.isRunning == true { return }
        let scriptPath = config.serviceScriptPath
        guard !scriptPath.isEmpty else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-lc", "exec \"\(scriptPath)\""]
        if let workingDir = config.serviceWorkingDirectory, !workingDir.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: workingDir)
        }
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.handleLogData(data)
        }
        do {
            try process.run()
            serviceProcess = process
        } catch {
            print("Failed to start Docling service: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopService()
    }

    private func stopService() {
        if let process = serviceProcess {
            terminateProcess(process)
        }
        terminateByPattern("docling-serve run")
        serviceProcess = nil
    }

    private func handleLogData(_ data: Data) {
        logBuffer.append(data)
        while let range = logBuffer.firstRange(of: Data([0x0A])) {
            let lineData = logBuffer.subdata(in: logBuffer.startIndex..<range.lowerBound)
            logBuffer.removeSubrange(logBuffer.startIndex...range.lowerBound)
            if let line = String(data: lineData, encoding: .utf8) {
                extractTaskIDs(from: line)
            }
        }
    }

    private func extractTaskIDs(from line: String) {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        let matches = taskIDRegex.matches(in: line, range: range)
        guard !matches.isEmpty else { return }
        for match in matches {
            if let idRange = Range(match.range, in: line) {
                let id = String(line[idRange])
                DispatchQueue.main.async { [weak self] in
                    self?.controller?.addTaskFromLog(id: id)
                }
            }
        }
    }

    private func terminateProcess(_ process: Process) {
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2.0)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    private func terminateByPattern(_ pattern: String) {
        let killer = Process()
        killer.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killer.arguments = ["-f", pattern]
        do {
            try killer.run()
            killer.waitUntilExit()
        } catch {
            print("Failed to run pkill: \(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
