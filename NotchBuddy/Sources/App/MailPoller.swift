import Foundation
import AppKit

#if !APPSTORE
/// Reads the macOS Mail inbox (all accounts) through AppleScript: unread count and latest messages.
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

    func poll() {
        let state = AppState.shared
        guard state.activeIntegrations.contains("integration_mail") else { return }
        let running = !NSRunningApplication.runningApplications(withBundleIdentifier: Self.bundleId).isEmpty
        state.mailRunning = running
        guard running, !polling else { return }
        polling = true
        queue.async {
            let result = MailPoller.readInbox()
            Task { @MainActor in
                MailPoller.shared.polling = false
                MailPoller.shared.handle(result)
            }
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
        case .success(let unread, let messages):
            state.mailAutomationDenied = false
            state.mailUnread = unread
            state.mailMessages = Array(messages.prefix(3))
            notifyNewMail(in: messages)
        }
    }

    /// One notification per read, however many new unread messages came in.
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
        guard let newest = messages.first(where: { !$0.isRead && !seenIds.contains($0.id) }) else { return }

        let state = AppState.shared
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
        case success(unread: Int, messages: [MailMessage])
        case denied
        case error
    }

    /// Unread count, then the first and last 5 messages of the unified inbox: Mail's order is
    /// not guaranteed, so both ends are read and Swift keeps the newest. Fields are separated by
    /// ASCII 31 and records by ASCII 30. Ages are in seconds, which avoids locale-dependent dates.
    private nonisolated static let script = """
    tell application "Mail"
        set us to character id 31
        set rs to character id 30
        set out to (unread count of inbox) as text
        set c to count of messages of inbox
        set picked to {}
        if c > 0 then
            if c > 5 then
                set picked to (messages 1 thru 5 of inbox) & (messages (c - 4) thru c of inbox)
            else
                set picked to messages 1 thru c of inbox
            end if
        end if
        if picked is not {} then
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
                set out to out & rs & (message id of m) & us & nm & us & s & us & age & us & (read status of m)
            end repeat
        end if
        return out
    end tell
    """

    private nonisolated static func readInbox() -> ReadResult {
        guard let script = NSAppleScript(source: script) else { return .error }
        var errDict: NSDictionary?
        let desc = script.executeAndReturnError(&errDict)
        if let errDict {
            let code = (errDict[NSAppleScript.errorNumber] as? Int) ?? 0
            appendAppLog("mail.log", "AppleScript error \(code)")
            return code == -1743 ? .denied : .error
        }
        guard let text = desc.stringValue else { return .error }

        var records = text.components(separatedBy: "\u{1E}")
        let unread = Int(records.removeFirst()) ?? 0
        let now = Date()
        var seen = Set<String>()
        let messages = records.compactMap { record -> MailMessage? in
            let f = record.components(separatedBy: "\u{1F}")
            guard f.count == 5, !f[0].isEmpty, seen.insert(f[0]).inserted else { return nil }
            return MailMessage(id: f[0], sender: f[1], subject: f[2],
                               date: now.addingTimeInterval(-(Double(f[3]) ?? 0)),
                               isRead: f[4] == "true")
        }
        .sorted { $0.date > $1.date }
        return .success(unread: unread, messages: messages)
    }
}
#endif

// MARK: - Model

struct MailMessage: Identifiable, Sendable {
    let id: String       // RFC Message-ID, without the angle brackets
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
