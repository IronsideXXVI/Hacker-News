import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: FeedViewModel

    var body: some View {
        Form {
            Section {
                Toggle("Block Ads", isOn: $viewModel.adBlockingEnabled)
                Toggle("Block Pop-ups", isOn: $viewModel.popUpBlockingEnabled)
            } header: {
                Text("Web Content")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
