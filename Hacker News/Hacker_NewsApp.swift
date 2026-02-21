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

struct FocusedFeedViewModelKey: FocusedValueKey {
    typealias Value = FeedViewModel
}

extension FocusedValues {
    var feedViewModel: FeedViewModel? {
        get { self[FocusedFeedViewModelKey.self] }
        set { self[FocusedFeedViewModelKey.self] = newValue }
    }
}

@main
struct Hacker_NewsApp: App {
    private let updaterController: SPUStandardUpdaterController
    @StateObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @FocusedValue(\.feedViewModel) private var feedViewModel

    init() {
        ArticleWebView.precompileAdBlockRules()
        Task {
            await OpenGraphService.shared.clearExpired()
            await ImageCacheService.shared.clearExpired()
        }
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
            ContentView()
                .environment(\.updater, updaterController.updater)
                .environmentObject(checkForUpdatesViewModel)
                .onAppear {
                    if updaterController.updater.automaticallyChecksForUpdates {
                        updaterController.updater.checkForUpdatesInBackground()
                    }
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
                    feedViewModel?.showFindBar.toggle()
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(feedViewModel == nil)

                Button("Find Next") {
                    feedViewModel?.findNextTrigger = UUID()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(feedViewModel == nil || !(feedViewModel?.showFindBar ?? false) || (feedViewModel?.findQuery.isEmpty ?? true))

                Button("Find Previous") {
                    feedViewModel?.findPreviousTrigger = UUID()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(feedViewModel == nil || !(feedViewModel?.showFindBar ?? false) || (feedViewModel?.findQuery.isEmpty ?? true))
            }
            CommandGroup(after: .sidebar) {
                Button("Reload Page") {
                    feedViewModel?.refreshTrigger = UUID()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(feedViewModel == nil)

                Button("Back") {
                    feedViewModel?.goBackTrigger = UUID()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(feedViewModel == nil)

                Button("Forward") {
                    feedViewModel?.goForwardTrigger = UUID()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(feedViewModel == nil)

                Divider()

                Button("Show Post") {
                    feedViewModel?.changeViewMode(to: .post)
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(feedViewModel == nil || feedViewModel?.selectedStory == nil || feedViewModel?.selectedStory?.displayURL == nil || feedViewModel?.selectedStory?.type == "comment")

                Button("Show Comments") {
                    feedViewModel?.changeViewMode(to: .comments)
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(feedViewModel == nil || feedViewModel?.selectedStory == nil || feedViewModel?.selectedStory?.displayURL == nil || feedViewModel?.selectedStory?.type == "comment")

                Button("Show Both") {
                    feedViewModel?.changeViewMode(to: .both)
                }
                .keyboardShortcut("3", modifiers: .command)
                .disabled(feedViewModel == nil || feedViewModel?.selectedStory == nil || feedViewModel?.selectedStory?.displayURL == nil || feedViewModel?.selectedStory?.type == "comment")

                Divider()

                Button("Zoom In") {
                    feedViewModel?.increaseTextScale()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(feedViewModel == nil)

                Button("Zoom Out") {
                    feedViewModel?.decreaseTextScale()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(feedViewModel == nil)

                Button("Actual Size") {
                    feedViewModel?.resetTextScale()
                }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(feedViewModel == nil)
            }
        }
    }
}
