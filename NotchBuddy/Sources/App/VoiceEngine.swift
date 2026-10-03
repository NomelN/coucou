import AVFoundation

/// Coucou speaks: reads agent events and chat answers aloud with the system voices.
/// Everything runs on the Mac (AVSpeechSynthesizer), nothing goes over the network.
/// Off by default; turned on in Settings → General → Voice.
@MainActor
final class VoiceEngine: NSObject {
    static let shared = VoiceEngine()

    /// What is being said. An alert cuts anything else; a chat answer never cuts an alert.
    enum Kind { case alert, chat, test }

    private let synth = AVSpeechSynthesizer()
    private var currentKind: Kind?

    /// Longest chat answer read aloud, in characters; longer ones are cut at a sentence end.
    private static let maxChatLength = 600

    private override init() {
        super.init()
        synth.delegate = self
    }

    // MARK: - Voices

    /// The chosen voice, or the system voice for the user's language.
    var voice: AVSpeechSynthesisVoice? {
        let id = AppState.shared.voiceIdentifier
        if !id.isEmpty, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
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

    /// Phrases follow the voice's language: French for a French voice, English otherwise.
    private var french: Bool { voice?.language.hasPrefix("fr") ?? false }

    // MARK: - Events

    func agentFinished(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAgents else { return }
        speak(french ? "\(name) a terminé." : "\(name) is done.", kind: .alert)
    }

    func agentFailed(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAgents else { return }
        speak(french ? "\(name) a rencontré une erreur." : "\(name) ran into an error.", kind: .alert)
    }

    func approvalNeeded(_ name: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAlerts else { return }
        speak(french ? "\(name) attend ton feu vert." : "\(name) needs your approval.", kind: .alert)
    }

    func questionAsked(_ name: String, question: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksAlerts else { return }
        let q = Self.plainText(question)
        speak(french ? "\(name) te pose une question. \(q)" : "\(name) has a question. \(q)", kind: .alert)
    }

    func chatAnswered(_ markdown: String) {
        guard AppState.shared.voiceEnabled, AppState.shared.voiceSpeaksChat else { return }
        let text = Self.shortened(Self.plainText(markdown), max: Self.maxChatLength)
        guard !text.isEmpty else { return }
        speak(text, kind: .chat)
    }

    func test() {
        speak(french ? "Coucou ! C'est moi, Mochi." : "Hi! It's me, Mochi.", kind: .test)
    }

    // MARK: - Playback

    private func speak(_ text: String, kind: Kind) {
        if synth.isSpeaking {
            // A chat answer never interrupts an alert
            if kind == .chat, currentKind == .alert { return }
            synth.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        currentKind = kind
        synth.speak(utterance)
    }

    /// Stops speaking. With a kind, stops only if that kind is being said
    /// (an answered permission card silences its own announcement, not a chat answer).
    func stop(_ kind: Kind? = nil) {
        guard synth.isSpeaking else { return }
        if let kind, kind != currentKind { return }
        synth.stopSpeaking(at: .word)
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
            if !self.synth.isSpeaking { self.currentKind = nil }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            if !self.synth.isSpeaking { self.currentKind = nil }
        }
    }
}
