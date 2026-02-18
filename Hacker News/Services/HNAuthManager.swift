import Foundation
import Security
import WebKit
import Observation

@Observable
final class HNAuthManager {
    var isLoggedIn = false
    var username = ""
    var karma = 0
    var isLoggingIn = false
    var loginError: String?
    var isResettingPassword = false
    var resetError: String?
    var resetSuccess = false

    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil

        do {
            let cookie = try await authenticate(username: username, password: password, creating: false)
            await injectCookie(cookie)
            let user = try await HNService.fetchUser(id: username)

            saveToKeychain(cookieValue: cookie.value, username: user.id)
            self.username = user.id
            self.karma = user.karma
            self.isLoggedIn = true
        } catch let error as LoginError {
            loginError = error.localizedDescription
        } catch {
            loginError = "Network error: \(error.localizedDescription)"
        }

        isLoggingIn = false
    }

    func createAccount(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil

        do {
            let cookie = try await authenticate(username: username, password: password, creating: true)
            await injectCookie(cookie)
            let user = try await HNService.fetchUser(id: username)

            saveToKeychain(cookieValue: cookie.value, username: user.id)
            self.username = user.id
            self.karma = user.karma
            self.isLoggedIn = true
        } catch let error as LoginError {
            loginError = error.localizedDescription
        } catch {
            loginError = "Network error: \(error.localizedDescription)"
        }

        isLoggingIn = false
    }

    func logout() async {
        let dataStore = WKWebsiteDataStore.default()
        let cookieStore = dataStore.httpCookieStore
        let cookies = await cookieStore.allCookies()
        for cookie in cookies where cookie.domain.contains("news.ycombinator.com") {
            await cookieStore.deleteCookie(cookie)
        }

        deleteFromKeychain()
        isLoggedIn = false
        username = ""
        karma = 0
    }

    func resetPassword(username: String) async {
        isResettingPassword = true
        resetError = nil
        resetSuccess = false

        do {
            let fnid = try await fetchFnid()

            let url = URL(string: "https://news.ycombinator.com/x")!
            var components = URLComponents()
            components.queryItems = [
                URLQueryItem(name: "fnid", value: fnid),
                URLQueryItem(name: "fnop", value: "forgot-password"),
                URLQueryItem(name: "s", value: username),
            ]
            let bodyString = components.percentEncodedQuery ?? ""

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = bodyString.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let (data, _) = try await URLSession.shared.data(for: request)
            let body = String(data: data, encoding: .utf8) ?? ""

            if body.lowercased().contains("unknown user") {
                throw LoginError.resetFailed
            }

            resetSuccess = true
        } catch let error as LoginError {
            resetError = error.localizedDescription
        } catch {
            resetError = "Network error: \(error.localizedDescription)"
        }

        isResettingPassword = false
    }

    func restoreSession() async {
        guard let stored = loadFromKeychain() else { return }

        let cookieProperties: [HTTPCookiePropertyKey: Any] = [
            .name: "user",
            .value: stored.cookieValue,
            .domain: ".news.ycombinator.com",
            .path: "/",
        ]
        guard let cookie = HTTPCookie(properties: cookieProperties) else { return }

        await injectCookie(cookie)

        do {
            let user = try await HNService.fetchUser(id: stored.username)
            self.username = user.id
            self.karma = user.karma
            self.isLoggedIn = true
        } catch {
            deleteFromKeychain()
        }
    }

    // MARK: - Keychain

    private static let keychainService = "com.hackernews.session"
    private static let keychainAccount = "userCookie"

    private func saveToKeychain(cookieValue: String, username: String) {
        deleteFromKeychain()

        let payload: [String: String] = ["cookie": cookieValue, "username": username]
        guard let data = try? JSONEncoder().encode(payload) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func loadFromKeychain() -> (cookieValue: String, username: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }

        guard let payload = try? JSONDecoder().decode([String: String].self, from: data),
              let cookie = payload["cookie"],
              let username = payload["username"] else { return nil }

        return (cookie, username)
    }

    private func deleteFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func fetchFnid() async throws -> String {
        let url = URL(string: "https://news.ycombinator.com/forgot")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let html = String(data: data, encoding: .utf8) ?? ""
        guard let fnid = parseFnid(from: html) else {
            throw LoginError.invalidResponse
        }
        return fnid
    }

    private func parseFnid(from html: String) -> String? {
        // Find the hidden input containing "fnid"
        guard let fnidRange = html.range(of: "fnid") else { return nil }
        // Walk backwards to find the <input tag start
        let before = html[html.startIndex..<fnidRange.lowerBound]
        guard let inputStart = before.range(of: "<input", options: [.backwards, .caseInsensitive]) else { return nil }
        // Walk forward to find the > closing the tag
        let after = html[inputStart.lowerBound...]
        guard let tagEnd = after.firstIndex(of: ">") else { return nil }
        let tag = String(html[inputStart.lowerBound...tagEnd])
        // Extract value="..." from the tag
        guard let valueStart = tag.range(of: "value=\"") else { return nil }
        let rest = tag[valueStart.upperBound...]
        guard let valueEnd = rest.firstIndex(of: "\"") else { return nil }
        let value = String(rest[rest.startIndex..<valueEnd])
        return value.isEmpty ? nil : value
    }

    private func authenticate(username: String, password: String, creating: Bool) async throws -> HTTPCookie {
        let url = URL(string: "https://news.ycombinator.com/login")!

        var queryItems = [
            URLQueryItem(name: "acct", value: username),
            URLQueryItem(name: "pw", value: password),
            URLQueryItem(name: "goto", value: "news"),
        ]
        if creating {
            queryItems.append(URLQueryItem(name: "creating", value: "t"))
        }
        var components = URLComponents()
        components.queryItems = queryItems
        let bodyString = components.percentEncodedQuery ?? ""

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyString.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }

        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LoginError.invalidResponse
        }

        if httpResponse.statusCode == 302,
           let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie"),
           let cookie = parseUserCookie(from: setCookie) {
            return cookie
        }

        throw creating ? LoginError.accountCreationFailed : LoginError.invalidCredentials
    }

    private func parseUserCookie(from header: String) -> HTTPCookie? {
        let cookies = HTTPCookie.cookies(
            withResponseHeaderFields: ["Set-Cookie": header],
            for: URL(string: "https://news.ycombinator.com")!
        )
        return cookies.first { $0.name == "user" }
    }

    private func injectCookie(_ cookie: HTTPCookie) async {
        await WKWebsiteDataStore.default().httpCookieStore.setCookie(cookie)
    }
}

private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

enum LoginError: LocalizedError {
    case invalidCredentials
    case invalidResponse
    case accountCreationFailed
    case resetFailed

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid username or password."
        case .invalidResponse: "Unexpected response from server."
        case .accountCreationFailed: "Account creation failed. Username may already be taken."
        case .resetFailed: "Unknown user."
        }
    }
}
