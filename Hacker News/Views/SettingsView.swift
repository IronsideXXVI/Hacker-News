import SwiftUI
import Sparkle

struct SettingsView: View {
    @Bindable var viewModel: FeedViewModel
    @EnvironmentObject private var checkForUpdatesViewModel: CheckForUpdatesViewModel
    @Environment(\.updater) private var updater

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $viewModel.appearanceMode) {
                    ForEach(AppearanceMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                HStack {
                    Text("Text Size")
                    Spacer()
                    Text("\(Int(viewModel.textScale * 100))%")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    Text("A")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.textScale, in: 0.75...1.5, step: 0.05)
                    Text("A")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
                Button("Reset to Default") {
                    viewModel.resetTextScale()
                }
                .disabled(viewModel.textScale == 1.0)
            } header: {
                Text("Text Size")
            }

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
        .font(.system(size: 13 * viewModel.textScale))
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
