import Foundation

final class UsageViewModel {
    static let shared = UsageViewModel()

    private(set) var windows: [DisplayWindow] = []
    private(set) var statusMessage: String?
    private(set) var lastUpdated: Date?
    private(set) var isLoading = false
    var launchAtLogin: Bool {
        get { LaunchAtLogin.isEnabled }
        set { LaunchAtLogin.isEnabled = newValue }
    }

    var onChange: (() -> Void)?

    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(60)

    private init() {}

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            await self?.refresh()
            while let self, !Task.isCancelled {
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { break }
                await self.refresh()
            }
        }
    }

    func refresh() async {
        if isLoading { return }
        isLoading = true
        notify()
        defer {
            isLoading = false
            notify()
        }

        do {
            var tokens = try CodexAuthStore.shared.loadTokens()
            do {
                let response = try await CodexUsageClient.shared.fetchUsage(tokens: tokens)
                apply(response: response)
            } catch CodexUsageClientError.unauthorized {
                tokens = try await CodexAuthStore.shared.refreshIfPossible()
                let response = try await CodexUsageClient.shared.fetchUsage(tokens: tokens)
                apply(response: response)
            }
        } catch {
            windows = []
            statusMessage = error.localizedDescription
        }
    }

    private func apply(response: UsageResponse) {
        windows = UsageFormatting.windows(from: response)
        lastUpdated = Date()

        if let allowed = response.rateLimit?.allowed, allowed == false {
            statusMessage = "当前账号额度不可用"
        } else if windows.isEmpty {
            statusMessage = "当前套餐未返回额度窗口"
        } else {
            statusMessage = nil
        }
    }

    var menuBarTitle: String {
        UsageFormatting.menuBarTitle(windows: windows, error: statusMessage)
    }

    var updatedText: String {
        UsageFormatting.relativeUpdated(lastUpdated)
    }

    private func notify() {
        if Thread.isMainThread {
            onChange?()
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.onChange?()
            }
        }
    }
}
