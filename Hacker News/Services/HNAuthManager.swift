import Foundation
import WebKit
import Observation

@Observable
final class HNAuthManager {
    var isLoggedIn = false
    var username = ""
    var karma = 0
    var isLoggingIn = false
    var loginError: String?

    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil

        do {
            let cookie = try await authenticate(username: username, password: password)
            await injectCookie(cookie)
            let user = try await HNService.fetchUser(id: username)

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

        isLoggedIn = false
        username = ""
        karma = 0
    }

    private func authenticate(username: String, password: String) async throws -> HTTPCookie {
        let url = URL(string: "https://news.ycombinator.com/login")!

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "acct", value: username),
            URLQueryItem(name: "pw", value: password),
            URLQueryItem(name: "goto", value: "news"),
        ]
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

        throw LoginError.invalidCredentials
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

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: "Invalid username or password."
        case .invalidResponse: "Unexpected response from server."
        }
    }
}
