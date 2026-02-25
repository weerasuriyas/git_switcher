import Foundation

struct GHAccount: Identifiable, Equatable {
    let login: String
    let host: String
    let active: Bool

    var id: String { "\(host)/\(login)" }

    var displayName: String {
        host == "github.com" ? login : "\(login) (\(host))"
    }
}

enum GHAccountParser {
    private struct RawAccount: Decodable {
        let login: String
        let host: String
        let active: Bool
    }

    private struct RawStatus: Decodable {
        let hosts: [String: [RawAccount]]
    }

    static func parse(_ json: String) throws -> [GHAccount] {
        let data = Data(json.utf8)
        let status = try JSONDecoder().decode(RawStatus.self, from: data)
        return status.hosts.values.flatMap { accounts in
            accounts.map { GHAccount(login: $0.login, host: $0.host, active: $0.active) }
        }
    }
}
