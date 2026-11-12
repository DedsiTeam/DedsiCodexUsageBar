import Foundation

enum CodexUsageClientError: LocalizedError {
    case unauthorized
    case http(Int, String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登录已过期"
        case .http(let code, let body):
            return "请求失败（\(code)）：\(body)"
        case .decoding(let error):
            return "解析额度数据失败：\(error.localizedDescription)"
        }
    }
}

final class CodexUsageClient: @unchecked Sendable {
    static let shared = CodexUsageClient()

    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    func fetchUsage(tokens: CodexTokens) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("DedsiCodexUsageBar/1.0", forHTTPHeaderField: "User-Agent")
        if let accountID = tokens.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw CodexUsageClientError.http(-1, "无响应")
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            throw CodexUsageClientError.unauthorized
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CodexUsageClientError.http(http.statusCode, String(body.prefix(200)))
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw CodexUsageClientError.decoding(error)
        }
    }
}
