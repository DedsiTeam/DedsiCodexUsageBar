import Foundation

struct CodexTokens: Equatable, Sendable {
    var accessToken: String
    var refreshToken: String?
    var accountID: String?
}

enum CodexAuthError: LocalizedError {
    case missingAuthFile
    case apiKeyOnly
    case invalidAuthFile
    case refreshFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingAuthFile:
            return "未找到 Codex 登录信息，请先运行 codex login。"
        case .apiKeyOnly:
            return "当前是 API Key 登录，无法查询 ChatGPT 套餐额度。"
        case .invalidAuthFile:
            return "auth.json 格式无效，请重新运行 codex login。"
        case .refreshFailed(let detail):
            return "登录已过期，刷新失败：\(detail)。请重新运行 codex login。"
        }
    }
}

final class CodexAuthStore: @unchecked Sendable {
    static let shared = CodexAuthStore()

    private let oauthClientID = "app_EMoamEEZ73f0CkXaXp7hrann"
    private let tokenURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let lock = NSLock()

    private init() {}

    func authFileURL() -> URL {
        if let home = ProcessInfo.processInfo.environment["CODEX_HOME"], !home.isEmpty {
            return URL(fileURLWithPath: home, isDirectory: true).appendingPathComponent("auth.json")
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    func loadTokens() throws -> CodexTokens {
        lock.lock()
        defer { lock.unlock() }

        let url = authFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CodexAuthError.missingAuthFile
        }

        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CodexAuthError.invalidAuthFile
        }

        if let tokens = root["tokens"] as? [String: Any],
           let access = tokens["access_token"] as? String,
           !access.isEmpty {
            let refresh = tokens["refresh_token"] as? String
            let accountID = (tokens["account_id"] as? String) ?? (root["account_id"] as? String)
            return CodexTokens(accessToken: access, refreshToken: refresh, accountID: accountID)
        }

        if root["OPENAI_API_KEY"] != nil {
            throw CodexAuthError.apiKeyOnly
        }

        throw CodexAuthError.invalidAuthFile
    }

    @discardableResult
    func refreshIfPossible() async throws -> CodexTokens {
        let current = try loadTokens()
        guard let refreshToken = current.refreshToken, !refreshToken.isEmpty else {
            throw CodexAuthError.refreshFailed("缺少 refresh_token")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
        ]
        request.httpBody = body
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
            }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexAuthError.refreshFailed("无响应")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw CodexAuthError.refreshFailed(message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let access = json["access_token"] as? String,
              !access.isEmpty else {
            throw CodexAuthError.refreshFailed("响应缺少 access_token")
        }

        let newRefresh = (json["refresh_token"] as? String) ?? refreshToken
        let updated = CodexTokens(
            accessToken: access,
            refreshToken: newRefresh,
            accountID: current.accountID
        )
        try writeTokens(updated)
        return updated
    }

    private func writeTokens(_ tokens: CodexTokens) throws {
        lock.lock()
        defer { lock.unlock() }

        let url = authFileURL()
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            root = existing
        }

        var tokenDict = (root["tokens"] as? [String: Any]) ?? [:]
        tokenDict["access_token"] = tokens.accessToken
        if let refresh = tokens.refreshToken {
            tokenDict["refresh_token"] = refresh
        }
        if let accountID = tokens.accountID {
            tokenDict["account_id"] = accountID
            root["account_id"] = accountID
        }
        root["tokens"] = tokenDict
        root["last_refresh"] = ISO8601DateFormatter().string(from: Date())

        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
