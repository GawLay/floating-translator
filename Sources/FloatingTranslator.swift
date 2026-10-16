import AppKit
import SwiftUI
import Vision
import ScreenCaptureKit
import Translation
import Carbon

struct LanguageChoice: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
    var language: Locale.Language? {
        code == "auto" ? nil : Locale.Language(identifier: code)
    }
}

let sourceLanguages: [LanguageChoice] = [
    .init(code: "vi", name: "Vietnamese"),
    .init(code: "auto", name: "Detect language"),
    .init(code: "en", name: "English"),
    .init(code: "fr", name: "French"),
    .init(code: "de", name: "German"),
    .init(code: "es", name: "Spanish"),
    .init(code: "ja", name: "Japanese"),
    .init(code: "ko", name: "Korean"),
    .init(code: "zh-Hans", name: "Chinese"),
    .init(code: "th", name: "Thai"),
    .init(code: "ms", name: "Malay")
]

let targetLanguages = sourceLanguages.filter { $0.code != "auto" }

enum TranslationInput { case area, text }

@MainActor
final class TranslatorModel: ObservableObject {
    @Published var sourceCode = "vi"
    @Published var targetCode = "en"
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var status = "Choose New area, paste text, or send a selection through Services."
    @Published var isWorking = false
    @Published var inputMode = TranslationInput.text
    @Published var hasArea = false
    @Published var isReading = false
    @Published var isEditing = false
    @Published var originalDraft = ""
    @Published var showingTextSize = false
    var startingFraction: Double?
    @Published var liveScan = false { didSet { liveScanHandler?(liveScan) } }
    @Published var isPinned = (UserDefaults.standard.object(forKey: "resultsPinned") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(isPinned, forKey: "resultsPinned"); pinHandler?() }
    }
    @Published var originalExpanded = (UserDefaults.standard.object(forKey: "originalExpanded") as? Bool) ?? true {
        didSet { UserDefaults.standard.set(originalExpanded, forKey: "originalExpanded") }
    }
    @Published var originalFraction = min(0.65, max(0.12, (UserDefaults.standard.object(forKey: "originalFraction") as? Double) ?? 0.28)) {
        didSet { UserDefaults.standard.set(originalFraction, forKey: "originalFraction") }
    }
    @Published var textSize = min(30, max(14, (UserDefaults.standard.object(forKey: "readingTextSize") as? Double) ?? 19)) {
        didSet { UserDefaults.standard.set(textSize, forKey: "readingTextSize") }
    }
    @Published var needsScreenAccess = false
    @Published var configuration: TranslationSession.Configuration?
    private var translationRequestID = 0

    var newAreaHandler: (() -> Void)?
    var showAreaHandler: (() -> Void)?
    var closeHandler: (() -> Void)?
    var pasteHandler: ((String) -> Void)?
    var liveScanHandler: ((Bool) -> Void)?
    var pinHandler: (() -> Void)?
    var languageChangeHandler: (() -> Void)?
    var captureHandler: (() -> Void)?
    var screenAccessHandler: (() -> Void)?

    func translate(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            translationRequestID += 1
            configuration = nil
            status = "No text found. Move the lens or use Paste text."
            isWorking = false
            return
        }
        sourceText = trimmed
        status = "Translating…"
        isWorking = true
        translationRequestID += 1
        let requestID = translationRequestID
        let source = sourceLanguages.first { $0.code == sourceCode }?.language
        let target = targetLanguages.first { $0.code == targetCode }?.language
        let previousConfiguration = configuration
        configuration = nil
        if source == target, source != nil {
            status = "Choose two different languages."
            isWorking = false
            return
        }
        Task {
            if let source, let target {
                let availability = LanguageAvailability()
                let support = await availability.status(from: source, to: target)
                guard requestID == translationRequestID else { return }
                if support == .unsupported {
                    status = "This language pair is unavailable on this macOS version."
                    isWorking = false
                    return
                }
            }
            guard requestID == translationRequestID else { return }
            if var previousConfiguration,
               previousConfiguration.source == source,
               previousConfiguration.target == target {
                previousConfiguration.invalidate()
                configuration = previousConfiguration
            } else {
                configuration = TranslationSession.Configuration(source: source, target: target)
            }
        }
    }

    func retranslate() {
        guard !sourceText.isEmpty else { return }
        translate(sourceText)
    }

    func swapLanguages() {
        guard sourceCode != "auto" else { return }
        (sourceCode, targetCode) = (targetCode, sourceCode)
        // Continue from the translation, like flipping a phrasebook.
        if !translatedText.isEmpty {
            sourceText = translatedText
            translatedText = ""
        }
    }

    func runTranslation(_ session: TranslationSession) async {
        let text = sourceText
        let requestID = translationRequestID
        guard !text.isEmpty, !Task.isCancelled else { return }
        do {
            let response = try await session.translate(text)
            guard requestID == translationRequestID, !Task.isCancelled else { return }
            translatedText = response.targetText
            status = "Ready"
        } catch {
            guard requestID == translationRequestID, !Task.isCancelled else { return }
            status = "Translation unavailable: \(error.localizedDescription)"
        }
        isWorking = false
    }

    func pasteText() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.isEmpty else {
            status = "Clipboard has no text."
            return
        }
        if let pasteHandler { pasteHandler(value) }
        else { translate(value) }
    }

    func copyResult() {
        guard !translatedText.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(translatedText, forType: .string)
        status = "Translation copied."
    }

    func invalidateWork() {
        translationRequestID += 1
        configuration = nil
        isWorking = false
    }

    func languagesChanged() {
        languageChangeHandler?()
        retranslate()
    }

    func startEditing() {
        liveScan = false
        originalExpanded = true
        originalDraft = sourceText
        isEditing = true
    }

    func applyEditedText() {
        isEditing = false
        if let pasteHandler { pasteHandler(originalDraft) }
        else { translate(originalDraft) }
    }

    func openScreenRecordingSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

let accent = Color(red: 0.95, green: 0.73, blue: 0.36)
let panelColor = Color(white: 0.08)
let fieldColor = Color(white: 0.15)

extension View {
    func panelBackground(cornerRadius: CGFloat = 18) -> some View {
        background(panelColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.28), radius: 14, y: 6)
    }
}

struct MonochromeButtonStyle: ButtonStyle {
    var prominent = false
    var large = false
    @Environment(\.isEnabled) var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: large ? 12 : 10, style: .continuous)
        configuration.label
            .font(.system(size: large ? 14 : 13, weight: large ? .semibold : .medium))
            .foregroundStyle(prominent ? Color.black : Color.white)
            .frame(minHeight: large ? 20 : 18)
            .padding(.horizontal, large ? 18 : 13)
            .padding(.vertical, large ? 11 : 8)
            .background(prominent ? accent : Color(white: 0.14), in: shape)
            .overlay {
                shape.strokeBorder(Color.white.opacity(prominent ? 0 : 0.16), lineWidth: 1)
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

struct SectionLabel: View {
    let title: String
    var color: Color = .secondary

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

struct LanguageField: View {
    let caption: String
    let choices: [LanguageChoice]
    @Binding var selection: String

    var body: some View {
        Menu {
            Picker(caption, selection: $selection) {
                ForEach(choices) { Text($0.name).tag($0.code) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    SectionLabel(title: caption)
                    Text(choices.first { $0.code == selection }?.name ?? selection)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(fieldColor, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .accessibilityLabel(caption)
    }
}

struct LanguageBar: View {
    @ObservedObject var model: TranslatorModel

    var body: some View {
        HStack(spacing: 6) {
            LanguageField(caption: "From", choices: sourceLanguages, selection: $model.sourceCode)
            Button {
                model.swapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(model.sourceCode == "auto")
            .help("Swap languages")
            LanguageField(caption: "To", choices: targetLanguages, selection: $model.targetCode)
        }
        .padding(8)
        .panelBackground()
        .onChange(of: [model.sourceCode, model.targetCode]) { _, _ in model.languagesChanged() }
    }
}
