import AppKit
import SwiftUI
import Translation

/// Native integration check: exercises the production view and Apple's sessions.
/// Uses only sample text and already installed language models; never captures a screen.
@main
struct TranslationRefreshTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = TranslatorModel()
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 460, height: 740),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Translation refresh checks"
        window.contentView = NSHostingView(rootView: ResultsCard(model: model))
        Task { @MainActor in
            guard await LanguageAvailability().status(from: Locale.Language(identifier: "vi"),
                                                       to: Locale.Language(identifier: "en")) == .installed else {
                print("SKIP: Install Vietnamese and English in macOS Translation Languages first.")
                exit(77)
            }
            window.orderFront(nil)
            let samples = ["Xin chào, hôm nay bạn khỏe không?",
                           "Ngày mai chúng ta sẽ gặp nhau ở công viên."]
            model.translate(samples[0])
            await expectReady("first translation", model)
            model.retranslate()
            await expectReady("refresh unchanged text", model)

            for index in 0..<12 {
                let previousSource = model.sourceText
                let previousResult = model.translatedText
                let sample = samples[(index + 1) % 2]
                // Area changes, pasted text and Services cancel previous work first.
                model.invalidateWork()
                model.translate(sample)
                await expectReady("replacement input \(index + 1)", model)
                require(model.sourceText == sample, "Wrong source text after replacement")
                if previousSource != sample {
                    require(model.translatedText != previousResult, "Old result survived new input")
                }
            }
            model.retranslate()
            await expectReady("refresh after repeated replacements", model)

            model.translate(samples[0])
            try? await Task.sleep(nanoseconds: 100_000_000)
            model.invalidateWork()
            model.translate(samples[1])
            await expectReady("replace in-flight translation", model)
            require(model.sourceText == samples[1], "Superseded input became current")

            model.targetCode = "vi"
            await expectSettled(model)
            require(model.status == "Choose two different languages.", "Expected invalid-pair feedback")
            model.targetCode = "en"
            await expectReady("recover after invalid language pair", model)

            model.sourceCode = "auto"
            await expectReady("detect language", model)
            for index in 0..<4 {
                model.invalidateWork()
                model.translate(samples[index % 2])
                await expectReady("detect replacement \(index + 1)", model)
            }

            model.invalidateWork()
            window.orderOut(nil)
            window.orderFront(nil)
            model.retranslate()
            await expectReady("refresh after hiding and reopening", model)

            model.invalidateWork()
            window.contentView = NSHostingView(rootView: CancelledTranslationCheck(model: model))
            model.translate(samples[0])
            await expectSettled(model)
            require(model.status == "Translation interrupted. Refresh to try again.",
                    "Cancelled work must release Refresh and explain how to retry")
            print("PASS cancelled task releases busy state")
            model.invalidateWork()
            window.contentView = NSHostingView(rootView: ResultsCard(model: model))
            model.retranslate()
            await expectReady("refresh after task cancellation", model)
            window.orderOut(nil)
            print("PASS all translation refresh checks")
            exit(0)
        }
        app.run()
    }

    @MainActor static func expectSettled(_ model: TranslatorModel) async {
        for _ in 0..<200 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            if !model.isWorking { return }
        }
        require(false, "Timed out with status: \(model.status)")
    }

    @MainActor static func expectReady(_ name: String, _ model: TranslatorModel) async {
        await expectSettled(model)
        require(model.status == "Ready" && !model.translatedText.isEmpty, "\(name): \(model.status)")
        print("PASS \(name)")
        fflush(stdout)
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); fflush(stdout); exit(1) }
    }
}

private struct CancelledTranslationCheck: View {
    @ObservedObject var model: TranslatorModel
    var body: some View {
        Color.clear.translationTask(model.configuration) { session in
            let work = Task { @MainActor in await model.runTranslation(session) }
            work.cancel()
            await work.value
        }
    }
}
