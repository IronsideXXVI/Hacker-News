import SwiftUI

struct LoginSheetView: View {
    var authManager: HNAuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: 16) {
            Text("Log in to Hacker News")
                .font(.headline)

            TextField("Username", text: $username)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            if let error = authManager.loginError {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack {
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Button("Log In") {
                    Task {
                        await authManager.login(username: username, password: password)
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(username.isEmpty || password.isEmpty || authManager.isLoggingIn)
            }
        }
        .padding(24)
        .frame(width: 300)
        .disabled(authManager.isLoggingIn)
        .onChange(of: authManager.isLoggedIn) {
            if authManager.isLoggedIn {
                dismiss()
            }
        }
    }
}
