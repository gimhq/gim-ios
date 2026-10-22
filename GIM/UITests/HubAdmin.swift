import Foundation

/// The admin API of the hub under test (gim-hub docs/admin.md), as the UI test runner uses it: token login, then the
/// session cookie and the CSRF token on every request. It never prints the token.
final class HubAdmin: Sendable {
    private let baseUrl: String
    private let cookie: String
    private let csrfToken: String

    private init(baseUrl: String, cookie: String, csrfToken: String) {
        self.baseUrl = baseUrl
        self.cookie = cookie
        self.csrfToken = csrfToken
    }

    /// `POST /admin/api/login {"token"}`: keeps the `gim_admin_session` cookie and the `csrf_token` of the answer.
    static func login(baseUrl: String, token: String) async throws -> HubAdmin {
        let (data, response) = try await send(
            baseUrl: baseUrl, "POST", "/admin/api/login", body: ["token": token], headers: [:])
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let csrfToken = object["csrf_token"] as? String,
            let setCookie = response.value(forHTTPHeaderField: "Set-Cookie"),
            let cookie = setCookie.split(separator: ";").first.map(String.init),
            cookie.hasPrefix("gim_admin_session=")
        else { throw AdminError.unexpected("login answered without a session") }
        return HubAdmin(baseUrl: baseUrl, cookie: cookie, csrfToken: csrfToken)
    }

    /// `POST /admin/api/users/{user_id}/suspend`.
    func suspend(userId: String) async throws {
        try await request("POST", "/admin/api/users/\(userId)/suspend", body: ["reason": "gim-ios E2E"])
    }

    /// `POST /admin/api/users/{user_id}/unsuspend`.
    func unsuspend(userId: String) async throws {
        try await request("POST", "/admin/api/users/\(userId)/unsuspend")
    }

    /// `POST /admin/api/users/policy/entries {"user_id"}`.
    func addPolicyEntry(userId: String) async throws {
        try await request("POST", "/admin/api/users/policy/entries", body: ["user_id": userId, "note": "gim-ios E2E"])
    }

    /// `DELETE /admin/api/users/policy/entries/{user_id}`.
    func removePolicyEntry(userId: String) async throws {
        try await request("DELETE", "/admin/api/users/policy/entries/\(userId)")
    }

    /// `PUT /admin/api/settings/GIM_HUB_USER_POLICY {"value"}`: `open`, `allow` or `deny`.
    func setUserPolicy(_ mode: String) async throws {
        try await request("PUT", "/admin/api/settings/GIM_HUB_USER_POLICY", body: ["value": mode])
    }

    /// `DELETE /admin/api/settings/GIM_HUB_USER_POLICY`: back to the default, `open`.
    func unsetUserPolicy() async throws {
        try await request("DELETE", "/admin/api/settings/GIM_HUB_USER_POLICY")
    }

    /// `GET /admin/api/users/policy`: the mode in force and the listed user ids.
    func userPolicy() async throws -> (mode: String, userIds: [String]) {
        let data = try await request("GET", "/admin/api/users/policy")
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let mode = object["mode"] as? String
        else { throw AdminError.unexpected("GET /admin/api/users/policy: no mode") }
        let entries = object["entries"] as? [[String: Any]] ?? []
        return (mode, entries.compactMap { $0["user_id"] as? String })
    }

    /// Sends one authenticated request and returns the body of a 2xx answer.
    @discardableResult
    private func request(_ method: String, _ path: String, body: [String: String]? = nil) async throws -> Data {
        var headers = ["Cookie": cookie]
        if method != "GET" { headers["X-CSRF-Token"] = csrfToken }
        return try await Self.send(baseUrl: baseUrl, method, path, body: body, headers: headers).0
    }

    private static func send(
        baseUrl: String, _ method: String, _ path: String, body: [String: String]?, headers: [String: String]
    ) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: baseUrl + path) else { throw AdminError.unexpected("bad URL \(baseUrl)\(path)") }
        var request = URLRequest(url: url)
        request.httpMethod = method
        // The cookie is sent explicitly, so no shared cookie storage is involved.
        request.httpShouldHandleCookies = false
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AdminError.unexpected("\(method) \(path): no HTTP") }
        guard (200..<300).contains(http.statusCode) else {
            throw AdminError.status(
                method: method, path: path, status: http.statusCode, body: String(decoding: data, as: UTF8.self))
        }
        return (data, http)
    }
}

enum AdminError: Error, CustomStringConvertible {
    case status(method: String, path: String, status: Int, body: String)
    case unexpected(String)

    var description: String {
        switch self {
        case .status(let method, let path, let status, let body): "\(method) \(path) answered \(status): \(body)"
        case .unexpected(let reason): reason
        }
    }
}
