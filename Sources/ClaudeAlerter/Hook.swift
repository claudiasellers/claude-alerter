import Foundation

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/ClaudeAlerter")
    static let cliSessions = support.appendingPathComponent("cli-sessions")
    static let seen = support.appendingPathComponent("seen.json")
    static let desktopSessions = home.appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
}

/// Runs when Claude Code (terminal) fires a hook: `ClaudeAlerter --hook <Event>` with the hook JSON on stdin.
/// Writes one small JSON record per session that the app watches. Must be fast and never fail loudly.
enum Hook {
    static func run(event: String) {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let input = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sid = input["session_id"] as? String, !sid.isEmpty else { return }

        let safe = String(sid.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        let url = Paths.cliSessions.appendingPathComponent(safe + ".json")
        let fm = FileManager.default
        try? fm.createDirectory(at: Paths.cliSessions, withIntermediateDirectories: true)

        if event == "SessionEnd" {
            try? fm.removeItem(at: url)
            return
        }

        var rec: [String: Any] = (try? Data(contentsOf: url))
            .flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let now = Date().timeIntervalSince1970

        rec["session_id"] = sid
        if let cwd = input["cwd"] as? String { rec["cwd"] = cwd }
        if let tp = input["transcript_path"] as? String { rec["transcript_path"] = tp }
        let env = ProcessInfo.processInfo.environment
        if let b = env["__CFBundleIdentifier"], !b.isEmpty { rec["term_bundle"] = b }
        if let t = env["TERM_PROGRAM"], !t.isEmpty { rec["term_program"] = t }

        switch event {
        case "UserPromptSubmit":
            rec["phase"] = "working"
            rec["detail"] = nil
            if let p = input["prompt"] as? String {
                let t = TextUtil.oneLine(p, max: 80)
                if !t.isEmpty && !t.hasPrefix("/") {
                    if rec["title"] == nil { rec["title"] = t }
                    rec["last_prompt"] = t
                }
            }
        case "Stop":
            rec["phase"] = "ready"
            rec["turn_end_at"] = now
            if let tp = rec["transcript_path"] as? String {
                rec["detail"] = lastAssistantText(transcriptPath: tp)
            }
        case "Notification":
            let type = (input["notification_type"] as? String) ?? ""
            let msg = (input["message"] as? String) ?? ""
            // The idle reminder fires after Stop; "ready" already covers it.
            if type == "idle_prompt" || msg.lowercased().contains("waiting for your input") { return }
            rec["phase"] = "needs_you"
            rec["detail"] = msg.isEmpty ? "Waiting for your OK" : msg
            rec["turn_end_at"] = now
        default:
            return
        }
        rec["updated_at"] = now

        if let out = try? JSONSerialization.data(withJSONObject: rec, options: [.prettyPrinted]) {
            try? out.write(to: url, options: .atomic)
        }
    }

    /// Reads the tail of the transcript and returns the start of Claude's last text reply.
    static func lastAssistantText(transcriptPath: String) -> String? {
        guard let fh = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let window: UInt64 = 512 * 1024
        try? fh.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? fh.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }

        for line in text.split(separator: "\n").reversed() {
            guard line.contains("\"assistant\""),
                  let obj = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  obj["type"] as? String == "assistant",
                  let msg = obj["message"] as? [String: Any],
                  let content = msg["content"] as? [[String: Any]] else { continue }
            let joined = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
            let cleaned = TextUtil.oneLine(TextUtil.stripMarkdown(joined), max: 220)
            if !cleaned.isEmpty { return cleaned }
        }
        return nil
    }
}

enum TextUtil {
    static func oneLine(_ s: String, max: Int) -> String {
        let collapsed = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        if collapsed.count <= max { return collapsed }
        return String(collapsed.prefix(max - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func stripMarkdown(_ s: String) -> String {
        var out = s
        for token in ["**", "__", "`", "### ", "## ", "# ", "> "] {
            out = out.replacingOccurrences(of: token, with: "")
        }
        return out
    }
}
