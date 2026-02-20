import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var viewModel: FeedViewModel
    @EnvironmentObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @Environment(\.updater) private var updater

    var body: some View {
        Form {
            Section {
                Toggle("Block Ads", isOn: $viewModel.adBlockingEnabled)
                Toggle("Block Pop-ups", isOn: $viewModel.popUpBlockingEnabled)
            } header: {
                Text("Web Content")
            }

            if let updater {
                Section {
                    Toggle(
                        "Automatically check for updates",
                        isOn: Binding(
                            get: { updater.automaticallyChecksForUpdates },
                            set: { updater.automaticallyChecksForUpdates = $0 }
                        )
                    )
                    Button("Check for Updates Now") {
                        checkForUpdatesViewModel.checkForUpdates()
                    }
                    .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
                } header: {
                    Text("Updates")
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
