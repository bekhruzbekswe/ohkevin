import Foundation

/// Claude Code's steps in plain words: what a worker row says while it works, and the
/// question an approval card asks. A step is the server's "Tool argument", as server.mjs describe() writes it.
/// Rows are matched top to bottom; the first hit wins.
public func plainWords(_ step: String) -> (doing: String, asking: String)? {
    let step = step.trimmingCharacters(in: .whitespaces)
    guard !step.isEmpty else { return nil }
    let tool = String(step.prefix { $0 != " " })
    let arg = step.dropFirst(tool.count).trimmingCharacters(in: .whitespaces)
    let file = cut(lastPart(arg))
    switch tool {
    case "Read": return ("Reading \(file)", "Read \(file)?")
    case "Edit", "NotebookEdit": return ("Editing \(file)", "Edit \(file)?")
    case "Write": return ("Writing \(file)", "Create \(file)?")
    case "Grep": return ("Searching the project", "Search the project?")
    case "Glob": return ("Looking for files", "Look for files?")
    case "WebFetch":
        let host = cut(URL(string: arg)?.host ?? "a web page")
        return ("Reading \(host)", "Open \(host)?")
    case "WebSearch": return ("Searching the web", "Search the web?")
    case "Task", "Agent": return ("Handing part of it to a helper", "Hand part of it to a helper?")
    case "TodoWrite": return ("Planning the steps", "Plan the steps?")
    case "Bash": return bash(arg)
    default:
        if tool.hasPrefix("mcp__") {
            let parts = tool.dropFirst(5).components(separatedBy: "__")
            let server = cut(spaced(parts[0])), action = spaced(parts.dropFirst().joined(separator: " "))
            return ("Using \(server)", action.isEmpty ? "Use \(server)?" : "Use \(server): \(cut(action))?")
        }
        let name = cut(spaced(tool))
        return ("Using \(name)", "Use \(name)?")
    }
}

private func bash(_ command: String) -> (String, String) {
    guard var w = shellWords(command), !w.isEmpty else { return ("Running a command", "Run this command?") }
    if lastPart(w[0]) == "npx", w.count > 1 { w.removeFirst() } // npx jest is jest
    let cmd = lastPart(w[0]), sub = w.count > 1 ? w[1] : "", third = w.count > 2 ? w[2] : ""
    let manager = ["npm", "pnpm", "yarn", "bun"].contains(cmd)
    if cmd == "git" {
        switch sub {
        case "status", "diff", "log", "show", "branch": return ("Checking what changed", "Check what changed?")
        case "add": return ("Staging the changes", "Stage the changes?")
        case "commit": return ("Committing", "Commit these changes?")
        case "push": return ("Pushing your commits", "Push your commits?")
        case "pull", "fetch": return ("Getting the latest changes", "Get the latest changes?")
        case "switch" where third == "-c" && w.count > 3, "checkout" where third == "-b" && w.count > 3:
            return ("Starting the branch \(cut(w[3]))", "Start the branch \(cut(w[3]))?")
        default: break
        }
    }
    if (manager && (sub == "test" || (sub == "run" && third.hasPrefix("test")))) || ["pytest", "jest", "vitest"].contains(cmd)
        || (["cargo", "go", "swift"].contains(cmd) && sub == "test") {
        return ("Running the tests", "Run the tests?")
    }
    if (manager && ["install", "i", "ci", "add"].contains(sub)) || (["pip", "pip3", "brew"].contains(cmd) && sub == "install")
        || (cmd == "cargo" && sub == "add") {
        return ("Installing packages", "Install packages?")
    }
    if (manager && sub == "run" && third == "build") || ["tsc", "make"].contains(cmd) || (["cargo", "swift", "go"].contains(cmd) && sub == "build") {
        return ("Building the project", "Build the project?")
    }
    if manager && sub == "run" && !third.isEmpty { return ("Running \(cut(third))", "Run \(cut(third))?") }
    if manager && ["start", "dev"].contains(sub) { return ("Running \(sub)", "Run \(sub)?") }
    switch cmd {
    case "rm", "rmdir": return ("Deleting files", "Delete files?")
    case "mkdir": return ("Making a folder", "Make a folder?")
    case "touch":
        let name = cut(lastPart(w.dropFirst().first { !$0.hasPrefix("-") } ?? "a file"))
        return ("Creating \(name)", "Create \(name)?")
    case "mv": return ("Moving files", "Move files?")
    case "cp": return ("Copying files", "Copy files?")
    case "curl", "wget": return ("Fetching from the web", "Fetch from the web?")
    case "ls", "cat", "head", "tail", "find", "grep", "rg", "wc", "pwd", "which": return ("Looking through the project", "Look through the project?")
    default: break
    }
    let named = ["git", "npm", "pnpm", "yarn", "npx", "pip", "brew", "docker", "kubectl", "gh", "cargo", "go"].contains(cmd)
    let name = cut(named && !sub.isEmpty && !sub.hasPrefix("-") ? "\(cmd) \(sub)" : cmd)
    return ("Running \(name)", "Run \(name)?")
}

/// The words of a plain shell command, or nil when it holds anything else (operators, redirection, substitution,
/// variables, globs, ~, escapes): the same rule as words() in call/approve.mjs.
public func shellWords(_ command: String) -> [String]? {
    var out: [String] = [], word: String? = nil
    var chars = Array(command)[...]
    while let c = chars.popFirst() {
        if c == " " || c == "\t" { if let w = word { out.append(w) }; word = nil }
        else if c == "'" || c == "\"" {
            guard let end = chars.firstIndex(of: c) else { return nil }
            let inner = String(chars[..<end])
            if c == "\"" && inner.contains(where: { "$`\\!".contains($0) }) { return nil }
            word = (word ?? "") + inner
            chars = chars[chars.index(after: end)...]
        } else if c.isLetter || c.isNumber || "_.,/:@%+=-".contains(c) { word = (word ?? "") + String(c) }
        else { return nil }
    }
    if let w = word { out.append(w) }
    return out.isEmpty ? nil : out
}

private func lastPart(_ path: String) -> String { path.split(separator: "/").last.map(String.init) ?? path }

/// Names are cut at 28 characters.
func cut(_ s: String) -> String { s.count > 28 ? String(s.prefix(27)) + "…" : s }

/// "ExitPlanMode" and "create_issue" as words: "Exit Plan Mode", "create issue".
private func spaced(_ s: String) -> String {
    var out = ""
    for (i, c) in s.enumerated() {
        if c == "_" { out += " "; continue }
        if i > 0, c.isUppercase, let last = out.last, last.isLowercase { out += " " }
        out.append(c)
    }
    return out.trimmingCharacters(in: .whitespaces)
}
