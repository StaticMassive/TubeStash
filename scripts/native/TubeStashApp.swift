// Tube Stash — native window wrapper.
// Starts the bundled engine (vendor Node + server/index.js, with yt-dlp and
// ffmpeg from vendor/) privately on 127.0.0.1, shows the interface in its own
// WebKit window, and stops the engine when the app quits. No browser involved.
import Cocoa
import WebKit
import Darwin

let kAppName = "Tube Stash"
let kPort = 47841
let kReadyPath = "api/settings"          // cheap endpoint; /api/health re-probes tools
let kBase = URL(string: "http://127.0.0.1:\(kPort)/")!
let kBackground = NSColor(srgbRed: 0.047, green: 0.043, blue: 0.047, alpha: 1)

func ping(_ path: String, timeout: TimeInterval = 1.5) -> Bool {
    var req = URLRequest(url: kBase.appendingPathComponent(path))
    req.timeoutInterval = timeout
    req.cachePolicy = .reloadIgnoringLocalCacheData
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    let task = URLSession.shared.dataTask(with: req) { _, resp, _ in
        if let h = resp as? HTTPURLResponse, (200..<500).contains(h.statusCode) { ok = true }
        sem.signal()
    }
    task.resume()
    _ = sem.wait(timeout: .now() + timeout + 0.5)
    return ok
}

func statusPage(_ title: String, _ detail: String) -> String {
    return """
    <!doctype html><html><head><meta charset="utf-8"><style>
    html,body{height:100%;margin:0;background:#0c0b0c;color:#ece8ea;font:15px -apple-system,system-ui,sans-serif}
    .c{height:100%;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:10px;text-align:center;padding:24px;box-sizing:border-box}
    h1{font-size:20px;font-weight:600;margin:0}p{margin:0;color:#a39ca0;max-width:520px;line-height:1.5}
    </style></head><body><div class="c"><h1>\(title)</h1><p>\(detail)</p></div></body></html>
    """
}

func run(_ path: String, _ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = FileHandle.nullDevice
    guard (try? p.run()) != nil else { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8) ?? ""
}

func executablePath(of pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 4096)
    let n = proc_pidpath(pid, &buf, UInt32(buf.count))
    return n > 0 ? String(cString: buf) : ""
}

final class Engine {
    let root: URL
    let stateDir: URL
    var logURL: URL { stateDir.appendingPathComponent("server.log") }
    var pidURL: URL { stateDir.appendingPathComponent("server.pid") }
    var process: Process?
    var quitting = false

    init(root: URL) {
        self.root = root
        stateDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(kAppName)")
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }

    var vendorDir: URL {
        #if arch(arm64)
        return root.appendingPathComponent("vendor/darwin-arm64")
        #else
        return root.appendingPathComponent("vendor/darwin-x64")
        #endif
    }

    func nodeURL() -> URL? {
        let fm = FileManager.default
        for c in [vendorDir.appendingPathComponent("node").path, "/opt/homebrew/bin/node",
                  "/opt/homebrew/opt/node@22/bin/node", "/usr/local/bin/node"]
        where fm.isExecutableFile(atPath: c) { return URL(fileURLWithPath: c) }
        return nil
    }

    // Stop an engine left running by the old launcher, but only if it is this
    // app's own Node (never an unrelated process that happens to use the port).
    func stopLeftoverEngine() {
        let out = run("/usr/sbin/lsof", ["-nP", "-t", "-iTCP:\(kPort)", "-sTCP:LISTEN"])
        let mine = root.path + "/"
        for line in out.split(separator: "\n") {
            guard let pid = pid_t(line.trimmingCharacters(in: .whitespaces)) else { continue }
            let exe = executablePath(of: pid)
            if exe.hasPrefix(mine) || exe.hasSuffix("/node") { kill(pid, SIGTERM) }
        }
        for _ in 0..<24 { if !ping(kReadyPath, timeout: 0.4) { return }; Thread.sleep(forTimeInterval: 0.25) }
    }

    func start(onUnexpectedExit: @escaping () -> Void) -> (String, String)? {
        guard FileManager.default.fileExists(atPath: root.appendingPathComponent("server/index.js").path) else {
            return ("\(kAppName) can't find its files",
                    "Keep \(kAppName).app inside the \(kAppName) folder, next to the server and vendor folders.")
        }
        guard let node = nodeURL() else {
            return ("The engine is missing", "The vendor folder inside \(kAppName) looks incomplete.")
        }
        if ping(kReadyPath, timeout: 0.8) { stopLeftoverEngine() }
        if !ping(kReadyPath, timeout: 0.4) {
            let p = Process()
            p.executableURL = node
            p.arguments = [root.appendingPathComponent("server/index.js").path]
            p.currentDirectoryURL = root
            var env = ProcessInfo.processInfo.environment
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            env["PATH"] = "\(vendorDir.path):/opt/homebrew/bin:/opt/homebrew/opt/node@22/bin:/usr/local/bin:"
                + "/Library/Frameworks/Python.framework/Versions/3.13/bin:\(home)/Library/Python/3.13/bin:/usr/bin:/bin"
            let ytdlp = vendorDir.appendingPathComponent("yt-dlp").path
            if FileManager.default.isExecutableFile(atPath: ytdlp) { env["YTDLP"] = ytdlp }
            env["STASH_ROOT"] = root.path
            env["PORT"] = String(kPort)
            p.environment = env
            if !FileManager.default.fileExists(atPath: logURL.path) {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            if let fh = try? FileHandle(forWritingTo: logURL) {
                fh.seekToEndOfFile()
                p.standardOutput = fh
                p.standardError = fh
            }
            p.standardInput = FileHandle.nullDevice
            p.terminationHandler = { [weak self] _ in
                guard let self = self, !self.quitting else { return }
                onUnexpectedExit()
            }
            do { try p.run() } catch {
                return ("Couldn't start \(kAppName)", error.localizedDescription)
            }
            process = p
            try? String(p.processIdentifier).write(to: pidURL, atomically: true, encoding: .utf8)
        }
        for _ in 0..<240 {
            if ping(kReadyPath) { return nil }
            if let p = process, !p.isRunning { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return ("\(kAppName) didn't start", "Details are in \(logURL.path)")
    }

    func stop() {
        quitting = true
        if let p = process, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(3)
            while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
            if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        }
        if process != nil { try? FileManager.default.removeItem(at: pidURL) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate,
                         WKUIDelegate, WKNavigationDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var engine: Engine!

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildWindow()
        let eng = Engine(root: Bundle.main.bundleURL.deletingLastPathComponent())
        engine = eng
        show("Starting \(kAppName)…", "Getting things ready.")
        DispatchQueue.global(qos: .userInitiated).async {
            let failure = eng.start(onUnexpectedExit: {
                DispatchQueue.main.async {
                    self.show("\(kAppName) stopped",
                              "Quit and reopen \(kAppName). Details are in \(eng.logURL.path)")
                }
            })
            DispatchQueue.main.async {
                if let f = failure { self.show(f.0, f.1) } else { self.web.load(URLRequest(url: kBase)) }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { engine?.stop() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil); return true
    }

    func show(_ title: String, _ detail: String) { web.loadHTMLString(statusPage(title, detail), baseURL: nil) }

    func buildWindow() {
        web = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        web.uiDelegate = self
        web.navigationDelegate = self
        web.allowsBackForwardNavigationGestures = false
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        window.title = kAppName
        window.minSize = NSSize(width: 520, height: 560)
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = kBackground
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = web
        window.center()
        _ = window.setFrameAutosaveName("TubeStashMainWindow")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func buildMenu() {
        let main = NSMenu()
        func sub(_ title: String) -> NSMenu {
            let item = NSMenuItem(); item.title = title; main.addItem(item)
            let m = NSMenu(title: title); item.submenu = m; return m
        }
        let app = sub(kAppName)
        app.addItem(withTitle: "About \(kAppName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide \(kAppName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = app.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        app.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit \(kAppName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let file = sub("File")
        let dl = file.addItem(withTitle: "Show Downloads Folder", action: #selector(openDownloads), keyEquivalent: "")
        dl.target = self
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let edit = sub("Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let view = sub("View")
        let reload = view.addItem(withTitle: "Reload", action: #selector(reloadPage), keyEquivalent: "r")
        reload.target = self
        let fs = view.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fs.keyEquivalentModifierMask = [.command, .control]

        let win = sub("Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")

        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc func reloadPage() {
        if web.url?.host == "127.0.0.1" { web.reload() } else { web.load(URLRequest(url: kBase)) }
    }
    @objc func openDownloads() {
        let dir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        NSWorkspace.shared.open(dir)
    }

    // MARK: page dialogs
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = NSAlert(); a.messageText = kAppName; a.informativeText = message
        a.addButton(withTitle: "OK")
        a.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = NSAlert(); a.messageText = kAppName; a.informativeText = message
        a.addButton(withTitle: "OK"); a.addButton(withTitle: "Cancel")
        a.beginSheetModal(for: window) { r in completionHandler(r == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let u = navigationAction.request.url, u.host != "127.0.0.1" { NSWorkspace.shared.open(u) }
        return nil
    }

    // Outside links (YouTube, GitHub) open in the default browser; the window stays on the app.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if let u = navigationAction.request.url, let s = u.scheme, s == "http" || s == "https",
           u.host != "127.0.0.1", navigationAction.targetFrame?.isMainFrame ?? true {
            NSWorkspace.shared.open(u); decisionHandler(.cancel, preferences); return
        }
        decisionHandler(.allow, preferences)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
