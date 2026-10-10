import AppKit
import Foundation

struct ArchivedMemo: Codable {
    let id: UUID
    let text: String
    let color: String
    let isDone: Bool
    let createdAt: Date
    let tornDownAt: Date
}

@MainActor
final class MemoSyncManager {
    static let shared = MemoSyncManager()

    /// Path to user-accessible markdown document in ~/Documents
    let markdownURL: URL = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let newURL = docs.appendingPathComponent("SunMemo.md")
        let oldURL = docs.appendingPathComponent("Tendedero-Memos.md")
        if !FileManager.default.fileExists(atPath: newURL.path), FileManager.default.fileExists(atPath: oldURL.path) {
            try? FileManager.default.copyItem(at: oldURL, to: newURL)
        }
        return newURL
    }()

    /// Backup path in App Support
    let backupURL: URL = {
        Line.memosFolder.appendingPathComponent("all_memos.md")
    }()

    private let archiveFileURL: URL = {
        Line.memosFolder.appendingPathComponent("archived_memos.json")
    }()

    private(set) var archivedMemos: [ArchivedMemo] = []

    private init() {
        loadArchivedMemos()
    }

    private func loadArchivedMemos() {
        guard let data = try? Data(contentsOf: archiveFileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            archivedMemos = try decoder.decode([ArchivedMemo].self, from: data)
        } catch {
            // Starting from an empty archive would overwrite this file on the
            // next save. Keep the unreadable one aside instead.
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = Line.memosFolder.appendingPathComponent("archived_memos-damaged-\(stamp).json")
            try? FileManager.default.moveItem(at: archiveFileURL, to: aside)
            log.error("Archive unreadable, kept as \(aside.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            Line.warn(L("The memo archive could not be read"),
                      String(format: L("The damaged file was moved to %@ so nothing is lost."), aside.path))
        }
    }

    private func saveArchivedMemos() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(at: Line.memosFolder, withIntermediateDirectories: true)
            try encoder.encode(archivedMemos).write(to: archiveFileURL, options: .atomic)
        } catch {
            log.error("Could not save the archive: \(error.localizedDescription, privacy: .public)")
            Line.warn(L("Could not save the memo archive"), error.localizedDescription)
        }
    }

    /// Records a torn down memo and immediately syncs to the markdown document.
    func archiveTornDown(memo: Pegged) {
        let archived = ArchivedMemo(
            id: memo.id,
            text: memo.memoText,
            color: memo.memoColor,
            isDone: memo.isDone,
            createdAt: memo.createdAt,
            tornDownAt: Date()
        )
        // Keep most recently torn down at the beginning
        archivedMemos.removeAll { $0.id == memo.id }
        archivedMemos.insert(archived, at: 0)
        saveArchivedMemos()
    }

    /// Exports all live memos and archived torn-down memos to the local markdown
    /// document. One way only: the file is rewritten each time, never read back.
    func sync(items: [Pegged]) {
        let memos = items.filter { $0.isMemo && !$0.falling }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let nowString = f.string(from: Date())

        var md = """
        # ☀️ SunMemo (晾想法) 便签与待办事项备份

        > ⚠️ **只读导出，请勿在此编辑**：本文档由 SunMemo 自动生成，每次便签变化都会整份重写，
        > 在这里做的修改会被覆盖、不会回到 SunMemo。要修改便签，请在 SunMemo 里编辑。
        > 可以用 Obsidian、Typora、VS Code 等查看和检索；需要整理时请先复制一份。
        > **最后导出时间**：\(nowString)

        ---

        # 📌 正在悬挂的便签（Active Memos）

        """

        if memos.isEmpty {
            md += "\n*（当前晾衣绳上暂无挂载便签）*\n\n"
        } else {
            for (idx, memo) in memos.enumerated() {
                let colorEmoji: String
                switch memo.memoColor.lowercased() {
                case "green": colorEmoji = "🟢 绿"
                case "pink": colorEmoji = "🌸 粉"
                case "blue": colorEmoji = "🔵 蓝"
                default: colorEmoji = "🟡 黄"
                }

                let todoStats = Self.calculateTodoStats(text: memo.memoText)
                let statusBadge: String
                if todoStats.total > 0 {
                    statusBadge = todoStats.completed == todoStats.total ? "【已全部完成 ☑️】" : "【进行中 ⏳ \(todoStats.completed)/\(todoStats.total)】"
                } else {
                    statusBadge = memo.isDone ? "【已完成 ☑️】" : "【待办便签 📌】"
                }

                let createTimeStr = f.string(from: memo.createdAt)

                md += "## 便签 \(idx + 1) · \(statusBadge) · \(colorEmoji) · 创建时间：\(createTimeStr)\n\n"
                md += memo.memoText.trimmingCharacters(in: .whitespacesAndNewlines)
                md += "\n\n---\n\n"
            }
        }

        // MARK: - Archived Torn-down Memos
        if !archivedMemos.isEmpty {
            md += "\n# 📦 历史已撕下便签归档（Archived & Torn Down）\n\n"
            for (idx, memo) in archivedMemos.enumerated() {
                let colorEmoji: String
                switch memo.color.lowercased() {
                case "green": colorEmoji = "🟢 绿"
                case "pink": colorEmoji = "🌸 粉"
                case "blue": colorEmoji = "🔵 蓝"
                default: colorEmoji = "🟡 黄"
                }

                let todoStats = Self.calculateTodoStats(text: memo.text)
                let statusBadge: String
                if todoStats.total > 0 {
                    statusBadge = todoStats.completed == todoStats.total ? "【已撕下 · 全部完成 ☑️】" : "【已撕下 · 完成 \(todoStats.completed)/\(todoStats.total)】"
                } else {
                    statusBadge = memo.isDone ? "【已撕下 · 已完成 ☑️】" : "【已撕下 🗑️】"
                }

                let tornDownTimeStr = f.string(from: memo.tornDownAt)
                let createTimeStr = f.string(from: memo.createdAt)

                md += "## 归档 \(idx + 1) · \(statusBadge) · \(colorEmoji) · 撕下时间：\(tornDownTimeStr)（创建于 \(createTimeStr)）\n\n"
                md += memo.text.trimmingCharacters(in: .whitespacesAndNewlines)
                md += "\n\n---\n\n"
            }
        }

        do {
            try md.write(to: markdownURL, atomically: true, encoding: .utf8)
            try? FileManager.default.createDirectory(at: Line.memosFolder, withIntermediateDirectories: true)
            try? md.write(to: backupURL, atomically: true, encoding: .utf8)
        } catch {
            log.error("Could not export SunMemo.md: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Reveals or opens the local markdown document
    func openInEditor() {
        if !FileManager.default.fileExists(atPath: markdownURL.path) {
            try? "".write(to: markdownURL, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(markdownURL)
    }

    // MARK: - Todo & Markdown Utilities

    struct TodoStats {
        let total: Int
        let completed: Int
    }

    static func calculateTodoStats(text: String) -> TodoStats {
        let lines = text.components(separatedBy: "\n")
        var total = 0
        var completed = 0
        for l in lines {
            let t = l.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("- [ ] ") || t.hasPrefix("* [ ] ") || t.hasPrefix("[ ] ") {
                total += 1
            } else if t.hasPrefix("- [x] ") || t.hasPrefix("- [X] ") ||
                      t.hasPrefix("* [x] ") || t.hasPrefix("* [X] ") ||
                      t.hasPrefix("[x] ") || t.hasPrefix("[X] ") {
                total += 1
                completed += 1
            }
        }
        return TodoStats(total: total, completed: completed)
    }

    static func toggleTodoLine(in text: String, lineIndex: Int) -> (newText: String, allDone: Bool) {
        var lines = text.components(separatedBy: "\n")
        guard lineIndex >= 0 && lineIndex < lines.count else { return (text, false) }
        let line = lines[lineIndex]
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "- [x] ", with: "- [ ] ", options: .caseInsensitive)
        } else if trimmed.hasPrefix("* [ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [ ] ", with: "* [x] ")
        } else if trimmed.hasPrefix("* [x] ") || trimmed.hasPrefix("* [X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "* [x] ", with: "* [ ] ", options: .caseInsensitive)
        } else if trimmed.hasPrefix("[ ] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[ ] ", with: "[x] ")
        } else if trimmed.hasPrefix("[x] ") || trimmed.hasPrefix("[X] ") {
            lines[lineIndex] = line.replacingOccurrences(of: "[x] ", with: "[ ] ", options: .caseInsensitive)
        }

        let newText = lines.joined(separator: "\n")
        let stats = calculateTodoStats(text: newText)
        let allDone = stats.total > 0 && stats.completed == stats.total
        return (newText, allDone)
    }
}
