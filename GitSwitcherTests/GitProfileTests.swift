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
}
