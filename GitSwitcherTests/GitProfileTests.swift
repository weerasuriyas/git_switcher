import XCTest
@testable import GitSwitcher

final class GitProfileTests: XCTestCase {
    func test_encode_decode_roundtrip() throws {
        let profile = GitProfile(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Work",
            gitName: "Jane Doe",
            gitEmail: "jane@corp.com",
            sshKeyPath: "/Users/jane/.ssh/id_work",
            signingKey: nil,
            signingFormat: nil
        )
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
    }

    func test_default_values() {
        let profile = GitProfile(name: "Personal", gitName: "Jane", gitEmail: "jane@home.com")
        let profile2 = GitProfile(name: "Personal", gitName: "Jane", gitEmail: "jane@home.com")
        XCTAssertNotEqual(profile.id, profile2.id)
        XCTAssertNil(profile.sshKeyPath)
        XCTAssertNil(profile.signingKey)
        XCTAssertNil(profile.signingFormat)
    }

    func test_decode_json_with_missing_optional_keys() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000002","name":"Work","gitName":"Bob","gitEmail":"bob@work.com"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GitProfile.self, from: json)
        XCTAssertEqual(decoded.name, "Work")
        XCTAssertNil(decoded.sshKeyPath)
        XCTAssertNil(decoded.signingKey)
        XCTAssertNil(decoded.signingFormat)
    }

    func test_new_fields_default_to_empty() {
        let profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        XCTAssertNil(profile.githubLogin)
        XCTAssertTrue(profile.directoryRules.isEmpty)
        XCTAssertTrue(profile.repoOverrides.isEmpty)
    }

    func test_new_fields_roundtrip() throws {
        var profile = GitProfile(name: "Work", gitName: "Bob", gitEmail: "bob@work.com")
        profile.githubLogin = "bobwork"
        profile.directoryRules = ["/Users/bob/work"]
        profile.repoOverrides = ["/Users/bob/personal/dotfiles"]
        let data = try JSONEncoder().encode(profile)
        let decoded = try JSONDecoder().decode(GitProfile.self, from: data)
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(decoded.directoryRules, ["/Users/bob/work"])
        XCTAssertEqual(decoded.repoOverrides, ["/Users/bob/personal/dotfiles"])
    }

    func test_old_json_without_new_fields_still_decodes() throws {
        let json = """
        {"id":"00000000-0000-0000-0000-000000000003","name":"Work","gitName":"Bob","gitEmail":"bob@work.com"}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(GitProfile.self, from: json)
        XCTAssertTrue(decoded.directoryRules.isEmpty)
        XCTAssertTrue(decoded.repoOverrides.isEmpty)
        XCTAssertNil(decoded.githubLogin)
    }
}
