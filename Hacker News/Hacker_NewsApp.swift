import SwiftUI
import Sparkle

private struct UpdaterKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}

extension EnvironmentValues {
    var updater: SPUUpdater? {
        get { self[UpdaterKey.self] }
        set { self[UpdaterKey.self] = newValue }
    }
}

@main
struct Hacker_NewsApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @State private var feedViewModel = FeedViewModel()

    init() {
        ArticleWebView.precompileAdBlockRules()
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.updaterController = controller
        self._checkForUpdatesViewModel = StateObject(
            wrappedValue: CheckForUpdatesViewModel(updater: controller.updater)
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: feedViewModel)
                .environment(\.updater, updaterController.updater)
                .environmentObject(checkForUpdatesViewModel)
                .onAppear {
                    applyAppearance(feedViewModel.appearanceMode)
                    if updaterController.updater.automaticallyChecksForUpdates {
                        updaterController.updater.checkForUpdatesInBackground()
                    }
                }
                .onChange(of: feedViewModel.appearanceMode) {
                    applyAppearance(feedViewModel.appearanceMode)
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    checkForUpdatesViewModel.checkForUpdates()
                }
                .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
            }
            CommandGroup(after: .textEditing) {
                Button("Find...") {
                    feedViewModel.showFindBar.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    feedViewModel.findNextTrigger = UUID()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!feedViewModel.showFindBar || feedViewModel.findQuery.isEmpty)

                Button("Find Previous") {
                    feedViewModel.findPreviousTrigger = UUID()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!feedViewModel.showFindBar || feedViewModel.findQuery.isEmpty)
            }
            CommandGroup(after: .sidebar) {
                Button("Reload Page") {
                    feedViewModel.refreshTrigger = UUID()
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("Back") {
                    feedViewModel.goBackTrigger = UUID()
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    feedViewModel.goForwardTrigger = UUID()
                }
                .keyboardShortcut("]", modifiers: .command)

                Divider()

                Button("Show Post") {
                    feedViewModel.viewMode = .post
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(feedViewModel.selectedStory == nil || feedViewModel.selectedStory?.displayURL == nil || feedViewModel.selectedStory?.type == "comment")

                Button("Show Comments") {
                    feedViewModel.viewMode = .comments
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(feedViewModel.selectedStory == nil || feedViewModel.selectedStory?.displayURL == nil || feedViewModel.selectedStory?.type == "comment")

                Button("Show Both") {
                    feedViewModel.viewMode = .both
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(feedViewModel.selectedStory == nil || feedViewModel.selectedStory?.displayURL == nil || feedViewModel.selectedStory?.type == "comment")

                Divider()

                Button("Zoom In") {
                    feedViewModel.increaseTextScale()
                }
                .keyboardShortcut("=", modifiers: .command)

                Button("Zoom Out") {
                    feedViewModel.decreaseTextScale()
                }
                .keyboardShortcut("-", modifiers: .command)

                Button("Actual Size") {
                    feedViewModel.resetTextScale()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }

    private func applyAppearance(_ mode: AppearanceMode) {
        switch mode {
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }
}
