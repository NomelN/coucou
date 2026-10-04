import AppKit
import EventKit

#if !APPSTORE
/// Reads the Mac's Calendar (EventKit): today's coming events for the Calendar pill, and the
/// alerts set on events. No polling: one timer waits for the next alert, and the list refreshes
/// when the calendar database changes, the day changes or the Mac wakes. Nothing leaves the Mac.
@MainActor
final class CalendarWatcher {
    static let shared = CalendarWatcher()
    static let bundleId = "com.apple.iCal"
    static let pillId = "integration_calendar"

    private let store = EKEventStore()
    private var alertTimer: Timer?
    private var observing = false
    /// Alerts already shown ("event id|fire time"), so a refresh never shows one twice.
    private var notified: Set<String> = []

    /// How far ahead alerts are scheduled: an alert can be set days before its event.
    private static let alertHorizon: TimeInterval = 8 * 24 * 3600
    /// An alert missed by up to this much (Mac asleep, Coucou just launched) still shows.
    private static let lateGrace: TimeInterval = 60

    private init() {}

    // MARK: - Access

    static var authorization: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var hasAccess: Bool { authorization == .fullAccess }

    /// Asks once (the system prompt), then reads the calendar.
    func requestAccess() {
        guard Self.authorization == .notDetermined else { refresh(); return }
        store.requestFullAccessToEvents { granted, _ in
            Task { @MainActor in
                AppState.shared.calendarAccess = Self.authorization
                if granted {
                    CalendarWatcher.shared.store.reset()
                    CalendarWatcher.shared.refresh()
                }
            }
        }
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Lifecycle

    /// At launch: reads the calendar when the pill is active. Asks for access only then.
    func start() {
        guard !observing else { return }
        observing = true
        let center = NotificationCenter.default
        center.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarWatcher.shared.refresh() }
        }
        center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarWatcher.shared.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
                                                          object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { CalendarWatcher.shared.refresh() }
        }
        activate()
    }

    /// The pill was turned on (or Coucou launched with it on).
    func activate() {
        AppState.shared.calendarAccess = Self.authorization
        guard AppState.shared.activeIntegrations.contains(Self.pillId) else { return }
        if Self.authorization == .notDetermined { requestAccess() } else { refresh() }
    }

    // MARK: - Calendars (Settings list)

    /// Every event calendar, grouped by account, for the checkbox list in Settings.
    func calendars() -> [CalendarInfo] {
        guard Self.hasAccess else { return [] }
        return store.calendars(for: .event)
            .map { CalendarInfo(id: $0.calendarIdentifier, title: $0.title,
                                account: $0.source?.title ?? "", color: Self.hex($0.color)) }
            .sorted { ($0.account, $0.title) < ($1.account, $1.title) }
    }

    private var watchedCalendars: [EKCalendar] {
        let hidden = Set(AppState.shared.calendarHidden)
        return store.calendars(for: .event).filter { !hidden.contains($0.calendarIdentifier) }
    }

    // MARK: - Refresh

    func refresh() {
        let state = AppState.shared
        state.calendarAccess = Self.authorization
        alertTimer?.invalidate()
        alertTimer = nil
        guard state.activeIntegrations.contains(Self.pillId), Self.hasAccess else {
            state.calendarEvents = []
            return
        }
        let calendars = watchedCalendars
        guard !calendars.isEmpty else {
            state.calendarEvents = []
            state.calendarLoaded = true
            return
        }

        let now = Date()
        let cal = Calendar.current
        let endOfDay = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

        // Today's events not over yet, all-day ones first
        let today = store.events(matching: store.predicateForEvents(withStart: cal.startOfDay(for: now),
                                                                     end: endOfDay, calendars: calendars))
            .filter { $0.endDate > now }
            .sorted { ($0.isAllDay ? 0 : 1, $0.startDate) < ($1.isAllDay ? 0 : 1, $1.startDate) }
        state.calendarEvents = today.map(Self.info)
        state.calendarLoaded = true

        // Alerts: past ones within the grace show now, the next one gets the timer
        let upcoming = store.events(matching: store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600), end: now.addingTimeInterval(Self.alertHorizon), calendars: calendars))
        var next: Date?
        for event in upcoming {
            for fire in Self.alertDates(of: event) {
                let key = "\(event.eventIdentifier ?? "")|\(Int(fire.timeIntervalSince1970))"
                guard !notified.contains(key) else { continue }
                if fire <= now {
                    if now.timeIntervalSince(fire) <= Self.lateGrace {
                        notified.insert(key)
                        notify(event)
                    }
                } else if next == nil || fire < next! {
                    next = fire
                }
            }
        }
        if let next {
            let timer = Timer(fire: next, interval: 0, repeats: false) { _ in
                MainActor.assumeIsolated { CalendarWatcher.shared.refresh() }
            }
            timer.tolerance = 1
            RunLoop.main.add(timer, forMode: .common)
            alertTimer = timer
        }
        if notified.count > 500 { notified.removeAll() }
    }

    private static func alertDates(of event: EKEvent) -> [Date] {
        (event.alarms ?? []).compactMap { alarm in
            alarm.absoluteDate ?? event.startDate.map { $0.addingTimeInterval(alarm.relativeOffset) }
        }
    }

    // MARK: - Alert

    private func notify(_ event: EKEvent) {
        let state = AppState.shared
        let info = Self.info(event)
        guard let idx = state.tasks.firstIndex(where: { $0.id == Self.pillId }) else { return }
        state.tasks[idx].state = .finished
        state.tasks[idx].steps = [info.title, info.when]
        if state.focusId != Self.pillId { state.tasks[idx].pillBadge = .finished }
        state.calendarAlertEventId = info.id
        state.focusForNotice(Self.pillId)
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("question")
        VoiceEngine.shared.calendarAlert(info.title, startsIn: info.start.timeIntervalSinceNow, isAllDay: info.isAllDay)

        // Back to rest after a minute, like the other services
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
            guard let i = state.tasks.firstIndex(where: { $0.id == Self.pillId }),
                  state.tasks[i].state == .finished else { return }
            state.tasks[i].state = .idle
            state.tasks[i].steps = []
            state.tasks[i].pillBadge = nil
            if state.calendarAlertEventId == info.id { state.calendarAlertEventId = nil }
        }
    }

    // MARK: - Opening

    static func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
        }
    }

    /// Shows the event in Calendar; falls back to opening the app.
    static func open(_ event: CalendarEventInfo) {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.:")
        if let id = event.id.addingPercentEncoding(withAllowedCharacters: allowed),
           let url = URL(string: "ical://ekevent/\(id)?method=show&options=more"),
           NSWorkspace.shared.open(url) {
            return
        }
        openCalendar()
    }

    // MARK: - Helpers

    private static func info(_ event: EKEvent) -> CalendarEventInfo {
        CalendarEventInfo(id: event.eventIdentifier ?? UUID().uuidString,
                          title: (event.title?.isEmpty == false ? event.title! : "Untitled"),
                          start: event.startDate ?? Date(), end: event.endDate ?? Date(),
                          isAllDay: event.isAllDay,
                          color: hex(event.calendar?.color),
                          meetingURL: meetingURL(of: event))
    }

    /// A video call link from the event's URL, location or notes (Meet, Zoom, Teams, Webex…).
    static func meetingURL(of event: EKEvent) -> URL? {
        let hosts = ["meet.google.com", "zoom.us", "teams.microsoft.com", "teams.live.com",
                     "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com"]
        func isMeeting(_ url: URL) -> Bool {
            guard let host = url.host?.lowercased() else { return false }
            return hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
        if let url = event.url, let safe = safeWebURL(url.absoluteString), isMeeting(safe) { return safe }
        let text = [event.location, event.notes].compactMap { $0 }.joined(separator: " ")
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let url = match.url, let safe = safeWebURL(url.absoluteString), isMeeting(safe) { return safe }
        }
        return nil
    }

    private static func hex(_ color: NSColor?) -> String {
        guard let c = color?.usingColorSpace(.sRGB) else { return "#FF7A45" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}
#endif

// MARK: - Models

struct CalendarEventInfo: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let color: String
    let meetingURL: URL?

    /// "All day", "Now" while it runs, otherwise the start time ("14:30").
    var when: String {
        if isAllDay { return "All day" }
        if start <= Date() { return "Now" }
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: start)
    }
}

struct CalendarInfo: Identifiable, Sendable {
    let id: String
    let title: String
    let account: String
    let color: String
}
