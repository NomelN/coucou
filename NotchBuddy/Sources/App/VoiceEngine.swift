import AVFoundation

/// Coucou speaks: agent events and chat answers out loud. With the Mochi voice, events play
/// Mochi's recorded lines (Resources/voice, made with ElevenLabs); anything without a line,
/// like chat answers, uses the Mac's own voices (AVSpeechSynthesizer). Nothing goes over the network.
/// Off by default; turned on in Settings → General → Voice.
@MainActor
final class VoiceEngine: NSObject {
    static let shared = VoiceEngine()

    /// What is being said. An alert cuts anything else; a chat answer never cuts an alert.
    enum Kind { case alert, chat, test }

    private let synth = AVSpeechSynthesizer()
    private var currentKind: Kind?

    /// Mochi's recorded line playing, or about to play once the event's chime has rung.
    private var player: AVAudioPlayer?
    private var pendingLine: DispatchWorkItem?
    private var meterTimer: Timer?
    private var meterFloor: Float = -160
    private var lastNod: CFTimeInterval = 0
    private var lastLine: URL?

    /// Mochi's line starts once the event's chime is mostly over.
    private static let chimeDelay: TimeInterval = 0.45
    private static let lineVolume: Float = 0.8

    private var isBusy: Bool { synth.isSpeaking || player?.isPlaying == true || pendingLine != nil }

    /// Longest chat answer read aloud, in characters; longer ones are cut at a sentence end.
    private static let maxChatLength = 600

    private override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Voices

    /// Saved voice identifier: "" is Mochi (when its lines ship), this tag the system voice,
    /// anything else a Mac voice picked in Settings.
    static let systemVoiceTag = "system"

    static let hasMochiLines: Bool = !(Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "voice") ?? []).isEmpty

    /// Mochi's recorded lines are used for events.
    var usesMochi: Bool { AppState.shared.voiceIdentifier.isEmpty && Self.hasMochiLines }

    /// The Mac voice for text: the one picked, or the system voice for the user's language.
    var voice: AVSpeechSynthesisVoice? {
        let id = AppState.shared.voiceIdentifier
        if !id.isEmpty, id != Self.systemVoiceTag, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    /// A recorded line: `name.wav` or one of `name-1.wav`, `name-2.wav`…, never the same twice in a row.
    private func line(_ name: String) -> URL? {
        let all = (Bundle.main.urls(forResourcesWithExtension: "wav", subdirectory: "voice") ?? []).filter {
            let base = $0.deletingPathExtension().lastPathComponent
            return base == name || base.range(of: "^\\Q\(name)\\E-\\d+$", options: .regularExpression) != nil
        }
        let fresh = all.filter { $0 != lastLine }
        return (fresh.isEmpty ? all : fresh).randomElement()
    }

    /// Installed voices for the picker: the user's languages and English, novelty voices
    /// left out, best quality first. The saved voice stays listed even in another language.
    static func availableVoices() -> [AVSpeechSynthesisVoice] {
        let languages = Set(Locale.preferredLanguages.map { String($0.prefix(2)) } + ["en"])
        let saved = AppState.shared.voiceIdentifier
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { !$0.voiceTraits.contains(.isNoveltyVoice) }
            .filter { languages.contains(String($0.language.prefix(2))) || $0.identifier == saved }
            .sorted {
                if $0.language != $1.language { return $0.language < $1.language }
                if $0.quality != $1.quality { return $0.quality.rawValue > $1.quality.rawValue }
                return $0.name < $1.name
            }
    }

    static func label(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium:  quality = " · Premium"
        case .enhanced: quality = " · Enhanced"
        default:        quality = ""
        }
        return "\(voice.name) (\(voice.language))\(quality)"
    }

    /// Phrases follow the voice's language: French for a French voice (and for Mochi), English otherwise.
    private var french: Bool { usesMochi || (voice?.language.hasPrefix("fr") ?? false) }

    // MARK: - Events

    func agentFinished(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAgents else { return }
        say(line: "fini", else: french ? "\(name) a terminé." : "\(name) is done.", kind: .alert)
    }

    func agentFailed(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAgents else { return }
        say(line: "erreur", else: french ? "\(name) a rencontré une erreur." : "\(name) ran into an error.", kind: .alert)
    }

    func rateLimited(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAgents else { return }
        say(line: "limite", else: french ? "\(name) a atteint sa limite d'usage." : "\(name) hit its usage limit.", kind: .alert)
    }

    func approvalNeeded(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAlerts else { return }
        say(line: "feu-vert", else: french ? "\(name) attend ton feu vert." : "\(name) needs your approval.", kind: .alert)
    }

    /// Mochi only says it has a question; the Mac voice also reads the question itself.
    func questionAsked(_ name: String, question: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAlerts else { return }
        let q = Self.plainText(question)
        say(line: "question", else: french ? "\(name) te pose une question. \(q)" : "\(name) has a question. \(q)", kind: .alert)
    }

    func chatAnswered(_ markdown: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksChat else { return }
        let text = Self.shortened(Self.plainText(markdown), max: Self.maxChatLength)
        guard !text.isEmpty else { return }
        speak(text, kind: .chat)
    }

    func test() {
        if usesMochi, let url = line("coucou") ?? line("fini") {
            play(url, kind: .test, delay: 0)
        } else {
            speak(french ? "Coucou ! C'est moi, Mochi." : "Hi! It's me, Mochi.", kind: .test)
        }
    }

    // MARK: - Playback

    /// Mochi's line when there is one, otherwise the text with the Mac voice.
    private func say(line name: String, else text: String, kind: Kind) {
        if usesMochi, let url = line(name) {
            play(url, kind: kind, delay: Self.chimeDelay)
        } else {
            speak(text, kind: kind)
        }
    }

    /// Makes room for something new. False when it must not play: a chat answer never cuts an alert.
    private func makeRoom(for kind: Kind) -> Bool {
        guard isBusy else { return true }
        if kind == .chat, currentKind == .alert { return false }
        silence()
        return true
    }

    private func silence() {
        pendingLine?.cancel()
        pendingLine = nil
        player?.stop()
        player = nil
        stopMeter()
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    private func speak(_ text: String, kind: Kind) {
        guard makeRoom(for: kind) else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentKind = kind
        synth.speak(utterance)
    }

    private func play(_ url: URL, kind: Kind, delay: TimeInterval) {
        guard makeRoom(for: kind) else { return }
        currentKind = kind
        lastLine = url
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingLine = nil
            guard let p = try? AVAudioPlayer(contentsOf: url) else { self.currentKind = nil; return }
            p.delegate = self
            p.isMeteringEnabled = true
            p.volume = Self.lineVolume
            self.player = p
            p.play()
            self.startMeter()
        }
        pendingLine = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Stops speaking. With a kind, stops only if that kind is being said
    /// (an answered permission card silences its own announcement, not a chat answer).
    func stop(_ kind: Kind? = nil) {
        guard isBusy else { return }
        if let kind, kind != currentKind { return }
        pendingLine?.cancel()
        pendingLine = nil
        player?.stop()
        player = nil
        stopMeter()
        if synth.isSpeaking { synth.stopSpeaking(at: .word) }
        if !synth.isSpeaking { currentKind = nil }
    }

    // MARK: - Mochi nods with a recorded line

    /// A nod each time the line gets clearly louder again (roughly each syllable), and at least
    /// every 0.4 s while the voice stays loud.
    private func startMeter() {
        meterTimer?.invalidate()
        meterFloor = -160
        meterTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.meterTick() }
        }
    }

    private func meterTick() {
        guard let p = player, p.isPlaying else { return }
        p.updateMeters()
        let power = p.averagePower(forChannel: 0)
        let now = CACurrentMediaTime()
        meterFloor = min(meterFloor, power)
        let rose = power > -30 && power - meterFloor > 6 && now - lastNod > 0.18
        let held = power > -26 && now - lastNod > 0.4
        if rose || held {
            lastNod = now
            meterFloor = power
            NotificationCenter.default.post(name: .botSpeakWord, object: nil)
        }
    }

    private func stopMeter() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: - Text

    /// Markdown to something worth hearing: no code blocks, links, emphasis or headings.
    static func plainText(_ markdown: String) -> String {
        var s = markdown
        s = s.replacingOccurrences(of: "```[\\s\\S]*?```", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: "https?://\\S+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "(?m)^\\s{0,3}(#{1,6}|>|[-*+]|\\d+\\.)\\s+", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "[`*_~|]", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cuts a long text at the last sentence end before `max` characters.
    static func shortened(_ text: String, max: Int) -> String {
        guard text.count > max else { return text }
        let head = String(text.prefix(max))
        if let end = head.lastIndex(where: { ".!?".contains($0) }), head.distance(from: head.startIndex, to: end) > max / 3 {
            return String(head[...end])
        }
        return head + "…"
    }
}

// MARK: - Mochi moves with the words

extension VoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .botSpeakWord, object: nil)
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.isBusy { self.currentKind = nil }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.isBusy { self.currentKind = nil }
        }
    }
}

extension VoiceEngine: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            guard let current = self.player, ObjectIdentifier(current) == finished else { return }
            self.player = nil
            self.stopMeter()
            if !self.isBusy { self.currentKind = nil }
        }
    }
}
