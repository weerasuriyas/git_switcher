import AppKit
import Combine

@MainActor
final class GHCLIService: ObservableObject {
    @Published var accounts: [GHAccount] = []
    @Published var ghError: GHError?

    var activeAccount: GHAccount? { accounts.first { $0.active } }

    // Locate gh at app launch once; nil means not installed.
    private static let ghPath: String? = {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            .first { FileManager.default.fileExists(atPath: $0) }
    }()

    init() {
        // Refresh every time any NSMenu opens (includes our menu bar extra).
        NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    func refresh() {
        Task {
            do {
                let json = try await runGH(["auth", "status", "--json", "hosts"])
                accounts = try GHAccountParser.parse(json)
                ghError = nil
            } catch let e as GHError {
                ghError = e
                accounts = []
            } catch {
                ghError = .commandFailed(error.localizedDescription)
                accounts = []
            }
        }
    }

    func switchTo(_ account: GHAccount) {
        Task {
            do {
                try await runGHVoid(["auth", "switch", "--user", account.login, "--hostname", account.host])
                refresh()
            } catch let e as GHError {
                ghError = e
            }
        }
    }

    /// Opens Terminal and runs `gh auth login` interactively.
    /// The user closes Terminal when done; next menu open auto-refreshes.
    func addAccount() {
        let src = "tell application \"Terminal\" to do script \"gh auth login\""
        let script = NSAppleScript(source: src)
        script?.executeAndReturnError(nil)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }

    func remove(_ account: GHAccount) {
        Task {
            do {
                try await runGHVoid(["auth", "logout", "--user", account.login, "--hostname", account.host])
                refresh()
            } catch let e as GHError {
                ghError = e
            }
        }
    }

    // MARK: - Private

    @discardableResult
    private func runGH(_ args: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let ghPath = GHCLIService.ghPath else { throw GHError.notInstalled }
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: ghPath)
            process.arguments = args
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            try process.run()
            process.waitUntilExit()
            let output = String(
                data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            guard process.terminationStatus == 0 else {
                let errOutput = String(
                    data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                    encoding: .utf8
                ) ?? ""
                throw GHError.commandFailed(errOutput.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            return output
        }.value
    }

    private func runGHVoid(_ args: [String]) async throws {
        _ = try await runGH(args)
    }
}

enum GHError: LocalizedError, Equatable {
    case notInstalled
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "GitHub CLI (gh) not found. Install with: brew install gh"
        case .commandFailed(let msg):
            return msg.isEmpty ? "gh command failed" : msg
        }
    }
}
