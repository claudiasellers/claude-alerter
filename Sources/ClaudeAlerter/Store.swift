import AppKit
import Foundation
import Observation

struct ClaudeThread: Identifiable, Equatable {
    enum Source: Equatable { case desktop, terminal }
    enum Phase: Equatable { case working, needsYou, ready }

    let id: String
    let title: String
    let project: String
    let source: Source
    let phase: Phase
    let detail: String?
    /// When the latest turn ended (nil while the first turn is still running).
    let finishedAt: Date?
    let lastActive: Date
    // How to get back to it
    let desktopSessionId: String?
    let termBundle: String?
    let termProgram: String?
    let cwd: String?
}

@MainActor
@Observable
final class Store {
    static let shared = Store()

    private(set) var threads: [ClaudeThread] = []
    private var seen: [String: Double] = [:]
    private var timer: Timer?

    /// Threads older than this are hidden entirely.
    private let horizon: TimeInterval = 3 * 24 * 3600

    init() {
        loadSeen()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { Store.shared.refresh() }
        }
    }

    // MARK: - Derived lists

    func needsAttention(_ t: ClaudeThread) -> Bool {
        switch t.phase {
        case .needsYou: return (t.finishedAt?.timeIntervalSince1970 ?? .infinity) > (seen[t.id] ?? 0)
        case .ready: return (t.finishedAt?.timeIntervalSince1970 ?? 0) > (seen[t.id] ?? 0)
        case .working: return false
        }
    }

    var attention: [ClaudeThread] {
        threads.filter(needsAttention).sorted {
            // Needs-you first, then newest finished
            if ($0.phase == .needsYou) != ($1.phase == .needsYou) { return $0.phase == .needsYou }
            return ($0.finishedAt ?? .distantPast) > ($1.finishedAt ?? .distantPast)
        }
    }

    var working: [ClaudeThread] {
        threads.filter { $0.phase == .working }.sorted { $0.lastActive > $1.lastActive }
    }

    var caughtUp: [ClaudeThread] {
        threads.filter { $0.phase != .working && !needsAttention($0) }
            .sorted { $0.lastActive > $1.lastActive }
    }

    // MARK: - Actions

    func markSeen(_ t: ClaudeThread) {
        seen[t.id] = Date().timeIntervalSince1970
        saveSeen()
    }

    func markAllSeen() {
        let now = Date().timeIntervalSince1970
        for t in attention { seen[t.id] = now }
        saveSeen()
    }

    func open(_ t: ClaudeThread) {
        markSeen(t)
        if let sid = t.desktopSessionId,
           let url = URL(string: "claude://code/continue?session=\(sid)&source=desktop_action") {
            NSWorkspace.shared.open(url)
            return
        }
        let bundle = t.termBundle ?? Self.bundleFor(termProgram: t.termProgram)
        guard let bundle, let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        let editorish = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf", "dev.zed.Zed"]
        if editorish.contains(bundle), let cwd = t.cwd {
            // Editors focus the window for that folder.
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: config)
        } else {
            NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        }
    }

    private static func bundleFor(termProgram: String?) -> String? {
        switch termProgram {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "vscode": return "com.microsoft.VSCode"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        case "ghostty": return "com.mitchellh.ghostty"
        default: return nil
        }
    }

    // MARK: - Scanning

    func refresh() {
        let now = Date()
        var result: [ClaudeThread] = []
        var desktopCliIds = Set<String>()

        for (t, cliId) in scanDesktop(now: now) {
            result.append(t)
            if let cliId { desktopCliIds.insert(cliId) }
        }
        for t in scanTerminal(now: now) where !desktopCliIds.contains(t.id) {
            result.append(t)
        }
        result = result.filter { now.timeIntervalSince($0.lastActive) < horizon }
        if result != threads { threads = result }
    }

    private func scanDesktop(now: Date) -> [(ClaudeThread, String?)] {
        let fm = FileManager.default
        var out: [(ClaudeThread, String?)] = []
        // claude-code-sessions/<account>/<org>/local_*.json
        let accounts = (try? fm.contentsOfDirectory(at: Paths.desktopSessions, includingPropertiesForKeys: nil)) ?? []
        for account in accounts {
            let orgs = (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? []
            for org in orgs {
                let files = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: nil)) ?? []
                for f in files where f.lastPathComponent.hasPrefix("local_") && f.pathExtension == "json" {
                    if let t = parseDesktop(f, now: now) { out.append(t) }
                }
            }
        }
        return out
    }

    private func parseDesktop(_ url: URL, now: Date) -> (ClaudeThread, String?)? {
        guard let data = try? Data(contentsOf: url),
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sid = d["sessionId"] as? String else { return nil }
        if d["isArchived"] as? Bool == true { return nil }

        func ms(_ key: String) -> Date? {
            (d[key] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        }
        let turnEdge = ms("lastTurnEdgeAt")
        let userFrame = ms("latestUserFrameAt")
        let activity = ms("lastActivityAt") ?? turnEdge ?? userFrame ?? .distantPast
        guard turnEdge != nil || userFrame != nil else { return nil } // never actually ran

        let summary = d["postTurnSummary"] as? [String: Any]
        let category = summary?["status_category"] as? String
        let needsAction = (summary?["needs_action"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let statusDetail = (summary?["status_detail"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        var phase: ClaudeThread.Phase
        let turnRunning = (userFrame ?? .distantPast) > (turnEdge ?? .distantPast)
        if turnRunning && now.timeIntervalSince(activity) < 30 * 60 {
            phase = .working
        } else if category == "blocked" || d["interruptedAwaitingPerson"] as? Bool == true {
            phase = .needsYou
        } else {
            phase = .ready
        }

        let origin = (d["originCwd"] as? String) ?? (d["cwd"] as? String) ?? ""
        var title = (d["title"] as? String) ?? "Untitled session"
        if title.isEmpty { title = "Untitled session" }

        let t = ClaudeThread(
            id: sid,
            title: title,
            project: Self.projectName(origin),
            source: .desktop,
            phase: phase,
            detail: phase == .working ? nil : (phase == .needsYou ? (needsAction ?? statusDetail) : statusDetail),
            finishedAt: turnRunning ? nil : (turnEdge ?? activity),
            lastActive: activity,
            desktopSessionId: sid,
            termBundle: nil, termProgram: nil, cwd: origin
        )
        return (t, d["cliSessionId"] as? String)
    }

    private func scanTerminal(now: Date) -> [ClaudeThread] {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: Paths.cliSessions, includingPropertiesForKeys: nil)) ?? []
        return files.compactMap { f -> ClaudeThread? in
            guard f.pathExtension == "json",
                  let data = try? Data(contentsOf: f),
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let sid = d["session_id"] as? String else { return nil }
            let updated = Date(timeIntervalSince1970: (d["updated_at"] as? Double) ?? 0)
            let turnEnd = (d["turn_end_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            let cwd = d["cwd"] as? String ?? ""
            var phase: ClaudeThread.Phase
            switch d["phase"] as? String {
            case "needs_you": phase = .needsYou
            case "working": phase = .working
            default: phase = .ready
            }
            // After you approve a permission prompt, the transcript keeps moving: treat as working again.
            if phase == .needsYou, let tp = d["transcript_path"] as? String,
               let mod = (try? fm.attributesOfItem(atPath: tp))?[.modificationDate] as? Date,
               mod.timeIntervalSince(updated) > 3 {
                phase = .working
            }
            // A turn that's been "working" for hours without a Stop was almost certainly interrupted.
            if phase == .working && now.timeIntervalSince(updated) > 3 * 3600 { phase = .ready }

            let project = Self.projectName(cwd)
            return ClaudeThread(
                id: sid,
                title: (d["title"] as? String) ?? "Session in \(project)",
                project: project,
                source: .terminal,
                phase: phase,
                detail: phase == .working ? (d["last_prompt"] as? String).map { "You: \($0)" } : d["detail"] as? String,
                finishedAt: phase == .working ? nil : (turnEnd ?? updated),
                lastActive: updated,
                desktopSessionId: nil,
                termBundle: d["term_bundle"] as? String,
                termProgram: d["term_program"] as? String,
                cwd: cwd
            )
        }
    }

    static func projectName(_ path: String) -> String {
        guard !path.isEmpty else { return "—" }
        var comps = URL(fileURLWithPath: path).pathComponents
        // .../repo/.claude/worktrees/<name>  ->  repo
        if let i = comps.firstIndex(of: ".claude"), i > 0 { comps = Array(comps[..<i]) }
        let name = comps.last ?? path
        return name == "/" ? "~" : name
    }

    // MARK: - Seen persistence

    private func loadSeen() {
        if let data = try? Data(contentsOf: Paths.seen),
           let d = try? JSONDecoder().decode([String: Double].self, from: data) {
            seen = d
        } else {
            // First launch: anything that finished more than an hour ago counts as already seen.
            seen = ["__firstRun": Date().timeIntervalSince1970]
            refreshForFirstRun()
        }
    }

    private func refreshForFirstRun() {
        refresh()
        let cutoff = Date().addingTimeInterval(-3600)
        for t in threads where (t.finishedAt ?? .distantFuture) < cutoff {
            seen[t.id] = Date().timeIntervalSince1970
        }
        saveSeen()
    }

    private func saveSeen() {
        // Drop entries for threads we no longer track (keeps the file small).
        let live = Set(threads.map(\.id))
        let pruned = seen.filter { live.contains($0.key) }
        seen = pruned
        try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(pruned) { try? data.write(to: Paths.seen, options: .atomic) }
    }
}
