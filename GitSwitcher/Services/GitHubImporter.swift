import Foundation

struct GitHubUserInfo {
    let login: String
    let name: String
    let email: String?
}

enum GitHubImportError: LocalizedError {
    case ghNotAvailable
    case commandFailed(String)
    case userNotFound(String)
    case networkError(Error)
    case parseError(String)

    var errorDescription: String? {
        switch self {
        case .ghNotAvailable:
            return "GitHub CLI (gh) is not installed. Install it with: brew install gh"
        case .commandFailed(let msg):
            return "GitHub CLI failed: \(msg)"
        case .userNotFound(let username):
            return "GitHub user '\(username)' not found"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .parseError(let msg):
            return "Could not parse GitHub response: \(msg)"
        }
    }
}

struct GitHubImporter {
    let ghPath: String

    init(ghPath: String? = nil) {
        if let path = ghPath {
            self.ghPath = path
        } else {
            let candidates = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
            self.ghPath = candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/local/bin/gh"
        }
    }

    // MARK: - Pure parsing (static — testable without I/O)

    static func parseUserJSON(_ jsonString: String) throws -> GitHubUserInfo {
        guard let data = jsonString.data(using: .utf8) else {
            throw GitHubImportError.parseError("Invalid string encoding")
        }
        struct Response: Decodable {
            let login: String
            let name: String?
            let email: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        return GitHubUserInfo(
            login: response.login,
            name: response.name ?? response.login,
            email: response.email
        )
    }

    // MARK: - Strategy A: gh CLI

    func isGHAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: ghPath)
    }

    func importViaGHCLI() async throws -> GitHubUserInfo {
        guard isGHAvailable() else { throw GitHubImportError.ghNotAvailable }

        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let process = Process()
                    let pipe = Pipe()
                    let errPipe = Pipe()
                    process.executableURL = URL(fileURLWithPath: self.ghPath)
                    process.arguments = ["api", "user"]
                    process.standardOutput = pipe
                    process.standardError = errPipe
                    try process.run()
                    process.waitUntilExit()

                    guard process.terminationStatus == 0 else {
                        let errMsg = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                        cont.resume(throwing: GitHubImportError.commandFailed(errMsg.trimmingCharacters(in: .whitespacesAndNewlines)))
                        return
                    }

                    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    do {
                        let info = try Self.parseUserJSON(output)
                        cont.resume(returning: info)
                    } catch {
                        cont.resume(throwing: error)
                    }
                } catch {
                    cont.resume(throwing: GitHubImportError.commandFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Strategy B: Public GitHub API (unauthenticated)

    func importViaUsername(_ username: String) async throws -> GitHubUserInfo {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubImportError.userNotFound(username)
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.github.com"
        components.path = "/users/\(trimmed)"
        guard let url = components.url else {
            throw GitHubImportError.userNotFound(trimmed)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("GitSwitcher/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw GitHubImportError.networkError(error)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GitHubImportError.userNotFound(trimmed)
        }

        let json = String(data: data, encoding: .utf8) ?? ""
        return try Self.parseUserJSON(json)
    }
}
