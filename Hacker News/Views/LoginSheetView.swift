import SwiftUI

struct LoginSheetView: View {
    var authManager: HNAuthManager
    var textScale: Double = 1.0
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var newUsername = ""
    @State private var newPassword = ""
    @State private var showingForgotPassword = false
    @State private var resetUsername = ""

    var body: some View {
        VStack(spacing: 16) {
            if showingForgotPassword {
                forgotPasswordView
            } else {
                loginAndCreateAccountView
            }
        }
        .font(.system(size: 13 * textScale))
        .padding(24)
        .frame(width: 340)
        .disabled(authManager.isLoggingIn)
        .onChange(of: authManager.isLoggedIn) {
            if authManager.isLoggedIn {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var loginAndCreateAccountView: some View {
        // MARK: - Login Section
        Text("Login")
            .font(.headline)

        TextField("Username", text: $username)
            .textFieldStyle(.roundedBorder)

        SecureField("Password", text: $password)
            .textFieldStyle(.roundedBorder)

        Button("Log In") {
            Task {
                await authManager.login(username: username, password: password)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 1.0, green: 0.4, blue: 0.0))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(username.isEmpty || password.isEmpty || authManager.isLoggingIn)

        Button("Forgot your password?") {
            resetUsername = username
            showingForgotPassword = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.0))
        .font(.caption)

        Divider()

        // MARK: - Create Account Section
        Text("Create Account")
            .font(.headline)

        TextField("Username", text: $newUsername)
            .textFieldStyle(.roundedBorder)

        SecureField("Password", text: $newPassword)
            .textFieldStyle(.roundedBorder)

        Button("Create Account") {
            Task {
                await authManager.createAccount(username: newUsername, password: newPassword)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 1.0, green: 0.4, blue: 0.0))
        .disabled(newUsername.isEmpty || newPassword.isEmpty || authManager.isLoggingIn)

        if let error = authManager.loginError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }

        Button("Cancel", role: .cancel) {
            dismiss()
        }
        .keyboardShortcut(.escape, modifiers: [])
    }

    @ViewBuilder
    private var forgotPasswordView: some View {
        Text("Reset Password")
            .font(.headline)

        Text("Enter your username and we'll send a password reset email to the address on your account.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

        TextField("Username", text: $resetUsername)
            .textFieldStyle(.roundedBorder)

        Button("Send Reset Email") {
            Task {
                await authManager.resetPassword(username: resetUsername)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(red: 1.0, green: 0.4, blue: 0.0))
        .keyboardShortcut(.return, modifiers: [])
        .disabled(resetUsername.isEmpty || authManager.isResettingPassword)

        if authManager.resetSuccess {
            Text("Password reset email sent. Check your inbox.")
                .foregroundStyle(.green)
                .font(.caption)
        }

        if let error = authManager.resetError {
            Text(error)
                .foregroundStyle(.red)
                .font(.caption)
        }

        Button("Back to Login") {
            showingForgotPassword = false
            authManager.resetError = nil
            authManager.resetSuccess = false
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color(red: 1.0, green: 0.4, blue: 0.0))
        .font(.caption)

        Button("Cancel", role: .cancel) {
            dismiss()
        }
        .keyboardShortcut(.escape, modifiers: [])
    }
}
