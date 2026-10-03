import Foundation
import AppKit

#if !APPSTORE
/// Reads macOS Mail through AppleScript: unread count and latest messages, either of the unified
/// inbox (no account picked in Settings) or of the inbox of each picked account (max 2).
/// Polls only while the Mail pill is active and Mail is already running — it never launches Mail.
/// Nothing leaves the Mac.
@MainActor
final class MailPoller {
    static let shared = MailPoller()
    static let bundleId = "com.apple.mail"
    private static let interval: TimeInterval = 45

    private var timer: Timer?
    private let queue = DispatchQueue(label: "fr.louisraille.coucou.mail")
    private var polling = false
    /// Message IDs already seen. Empty until the first read, which sets the baseline and never notifies.
    private var seenIds: Set<String> = []
    private var baselineDone = false
    /// Watched accounts of the last read; a change resets the baseline.
    private var lastAccounts: [String]?

    private init() {}

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { _ in
            Task { @MainActor in MailPoller.shared.poll() }
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            MailPoller.shared.poll()
        }
    }

    static var isMailRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    func poll() {
        let state = AppState.shared
        guard state.activeIntegrations.contains("integration_mail") else { return }
        state.mailRunning = Self.isMailRunning
        guard state.mailRunning, !polling else { return }

        let accounts = state.mailAccountFilter
        if accounts != lastAccounts {
            // Other inboxes: what they already hold is not new mail
            lastAccounts = accounts
            baselineDone = false
            seenIds = []
        }
        polling = true
        queue.async {
            let result = MailPoller.readInboxes(accounts: accounts)
            Task { @MainActor in
                MailPoller.shared.polling = false
                // The watched accounts changed during the read: the next poll redoes it
                guard accounts == MailPoller.shared.lastAccounts else { return }
                MailPoller.shared.handle(result)
            }
        }
    }

    /// Names of the enabled Mail accounts, for the Settings list. nil when Mail is not open
    /// or Coucou may not control it.
    func loadAccounts() async -> [String]? {
        guard Self.isMailRunning else { return nil }
        return await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: MailPoller.readAccounts()) }
        }
    }

    /// Opens one message in Mail through the message: URL scheme.
    static func open(_ message: MailMessage) {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "@.-_+=$")
        guard let encoded = message.id.addingPercentEncoding(withAllowedCharacters: allowed),
              let url = URL(string: "message://%3C\(encoded)%3E") else { return }
        NSWorkspace.shared.open(url)
    }

    static func openMail() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
    }

    // MARK: - Result handling

    private func handle(_ result: ReadResult) {
        let state = AppState.shared
        switch result {
        case .denied:
            state.mailAutomationDenied = true
        case .error:
            break  // Mail quit mid-read or busy: try again next tick
        case .success(let inboxes):
            state.mailAutomationDenied = false
            state.mailInboxes = inboxes.map {
                MailInbox(account: $0.account, unread: $0.unread, messages: Array($0.messages.prefix(3)))
            }
            notifyNewMail(in: inboxes.flatMap(\.messages))
        }
    }

    /// One notification per read, however many new unread messages came in. The account of the
    /// newest one becomes the one shown in the card, until the next new mail or a click on ‹ ›.
    private func notifyNewMail(in messages: [MailMessage]) {
        let ids = Set(messages.map(\.id))
        defer {
            seenIds.formUnion(ids)
            if seenIds.count > 500 { seenIds = ids }
        }
        guard baselineDone else {
            baselineDone = true
            appendAppLog("mail.log", "Baseline: \(messages.count) messages read")
            return
        }
        guard let newest = messages
            .filter({ !$0.isRead && !seenIds.contains($0.id) })
            .max(by: { $0.date < $1.date }) else { return }

        let state = AppState.shared
        if !newest.account.isEmpty { state.mailShownAccount = newest.account }
        guard let idx = state.tasks.firstIndex(where: { $0.id == "integration_mail" }) else { return }
        state.tasks[idx].state = .finished
        state.tasks[idx].steps = [newest.sender, newest.subject].filter { !$0.isEmpty }
        if state.focusId != "integration_mail" { state.tasks[idx].pillBadge = .finished }
        // Always open the island big, even when the Mail pill already has the focus
        state.focusForNotice("integration_mail")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
        appendAppLog("mail.log", "New mail notified")

        // Auto-clear after 60s, like the other services
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            let state = AppState.shared
            guard let i = state.tasks.firstIndex(where: { $0.id == "integration_mail" }),
                  state.tasks[i].state == .finished else { return }
            state.tasks[i].state = .idle
            state.tasks[i].steps = []
            state.tasks[i].pillBadge = nil
        }
    }

    // MARK: - AppleScript (runs on `queue`)

    enum ReadResult: Sendable {
        case success([MailInbox])
        case denied
        case error
    }

    /// Reads one mailbox: label and unread count, then the first and last 5 messages (Mail's
    /// order is not guaranteed, so both ends are read and Swift keeps the newest). Fields are
    /// separated by ASCII 31 and records by ASCII 30. Ages are in seconds, which avoids
    /// locale-dependent dates.
    private nonisolated static let readBoxHandler = """
    on readBox(box, label)
        tell application "Mail"
            set us to character id 31
            set rs to character id 30
            set blk to label & us & ((unread count of box) as text)
            set c to count of messages of box
            set picked to {}
            if c > 0 then
                if c > 5 then
                    set picked to (messages 1 thru 5 of box) & (messages (c - 4) thru c of box)
                else
                    set picked to messages 1 thru c of box
                end if
            end if
            repeat with m in picked
                set s to subject of m
                if s is missing value then set s to ""
                set f to sender of m
                if f is missing value then set f to ""
                set nm to f
                if f is not "" then
                    try
                        set nm to extract name from f
                    end try
                end if
                set age to ((current date) - (date received of m)) as integer
                set blk to blk & rs & (message id of m) & us & nm & us & s & us & age & us & (read status of m)
            end repeat
            return blk
        end tell
    end readBox
    """

    /// Unified inbox when `accounts` is empty, else the inbox of each account (blocks separated
    /// by ASCII 29). An account's inbox is its top-level mailbox named INBOX (any case).
    private nonisolated static func readInboxes(accounts: [String]) -> ReadResult {
        let body: String
        if accounts.isEmpty {
            body = """
            tell application "Mail" to set box to inbox
            return my readBox(box, "")
            """
        } else {
            let list = accounts.map { "\"" + escaped($0) + "\"" }.joined(separator: ", ")
            body = """
            set gs to character id 29
            set out to ""
            repeat with acctName in {\(list)}
                set label to contents of acctName
                set box to missing value
                tell application "Mail"
                    try
                        repeat with mb in (mailboxes of account label)
                            if name of mb is "INBOX" then
                                set box to contents of mb
                                exit repeat
                            end if
                        end repeat
                    end try
                end tell
                if box is not missing value then
                    if out is not "" then set out to out & gs
                    set out to out & my readBox(box, label)
                end if
            end repeat
            return out
            """
        }
        let text: String
        switch run(readBoxHandler + "\n" + body) {
        case .text(let t): text = t
        case .denied:      return .denied
        case .failed:      return .error
        }

        let now = Date()
        var seen = Set<String>()
        let inboxes = text.components(separatedBy: "\u{1D}").compactMap { block -> MailInbox? in
            var records = block.components(separatedBy: "\u{1E}")
            let header = records.removeFirst().components(separatedBy: "\u{1F}")
            guard header.count == 2 else { return nil }
            let account = header[0]
            let messages = records.compactMap { record -> MailMessage? in
                let f = record.components(separatedBy: "\u{1F}")
                guard f.count == 5, !f[0].isEmpty, seen.insert(f[0]).inserted else { return nil }
                return MailMessage(id: f[0], account: account, sender: f[1], subject: f[2],
                                   date: now.addingTimeInterval(-(Double(f[3]) ?? 0)),
                                   isRead: f[4] == "true")
            }
            .sorted { $0.date > $1.date }
            return MailInbox(account: account, unread: Int(header[1]) ?? 0, messages: messages)
        }
        return .success(inboxes)
    }

    private nonisolated static func readAccounts() -> [String]? {
        let script = """
        tell application "Mail"
            set rs to character id 30
            set out to ""
            repeat with a in (every account whose enabled is true)
                if out is not "" then set out to out & rs
                set out to out & (name of a)
            end repeat
            return out
        end tell
        """
        guard case .text(let text) = run(script) else { return nil }
        return text.components(separatedBy: "\u{1E}").filter { !$0.isEmpty }
    }

    private enum RunResult { case text(String), denied, failed }

    private nonisolated static func run(_ source: String) -> RunResult {
        guard let script = NSAppleScript(source: source) else { return .failed }
        var errDict: NSDictionary?
        let desc = script.executeAndReturnError(&errDict)
        if let errDict {
            let code = (errDict[NSAppleScript.errorNumber] as? Int) ?? 0
            appendAppLog("mail.log", "AppleScript error \(code)")
            return code == -1743 ? .denied : .failed  // -1743: Automation not allowed
        }
        return .text(desc.stringValue ?? "")
    }

    private nonisolated static func escaped(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
#endif

// MARK: - Model

struct MailMessage: Identifiable, Sendable {
    let id: String       // RFC Message-ID, without the angle brackets
    let account: String  // "" when read from the unified inbox
    let sender: String
    let subject: String
    let date: Date
    let isRead: Bool

    var timeAgo: String {
        let diff = Date().timeIntervalSince(date)
        if diff < 60    { return "just now" }
        if diff < 3600  { return "\(Int(diff/60))m" }
        if diff < 86400 { return "\(Int(diff/3600))h" }
        return "\(Int(diff/86400))d"
    }
}

/// One inbox shown in the Mail card: the unified inbox (account "") or one account's inbox.
struct MailInbox: Sendable {
    let account: String
    let unread: Int
    let messages: [MailMessage]
}
