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
                HStack {
                    Button {
                        viewModel.resetTextScale()
                    } label: {
                        Text("Reset to Default")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.textScale == 1.0)
                    Spacer()
                }
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
                    HStack {
                        Button {
                            checkForUpdatesViewModel.checkForUpdates()
                        } label: {
                            Text("Check for Updates Now")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!checkForUpdatesViewModel.canCheckForUpdates)
                        Spacer()
                    }
                } header: {
                    Text("Updates")
                }
            }
        }
        .font(.system(size: 13 * viewModel.textScale))
        .tint(Color(red: 1.0, green: 0.4, blue: 0.0))
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
