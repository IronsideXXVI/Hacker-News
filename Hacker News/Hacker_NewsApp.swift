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
}
