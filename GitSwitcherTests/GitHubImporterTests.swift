import XCTest
@testable import GitSwitcher

final class GitHubImporterTests: XCTestCase {

    // MARK: - JSON parsing (pure, no I/O)

    func test_parse_gh_output_extracts_name_email_login() throws {
        let json = """
        {"login":"shanew","name":"Shane W","email":"shane@example.com","id":12345}
        """
        let result = try GitHubImporter.parseUserJSON(json)
        XCTAssertEqual(result.login, "shanew")
        XCTAssertEqual(result.name, "Shane W")
        XCTAssertEqual(result.email, "shane@example.com")
    }

    func test_parse_gh_output_nil_email_when_null() throws {
        let json = """
        {"login":"shanew","name":"Shane W","email":null,"id":12345}
        """
        let result = try GitHubImporter.parseUserJSON(json)
        XCTAssertNil(result.email)
    }

    func test_parse_gh_output_throws_on_invalid_json() {
        XCTAssertThrowsError(try GitHubImporter.parseUserJSON("not json"))
    }

    func test_parse_gh_output_throws_on_missing_login() {
        let json = "{\"name\":\"Shane W\"}"
        XCTAssertThrowsError(try GitHubImporter.parseUserJSON(json))
    }

    // MARK: - gh CLI detection

    func test_gh_not_available_when_path_nonexistent() {
        let importer = GitHubImporter(ghPath: "/nonexistent/gh")
        XCTAssertFalse(importer.isGHAvailable())
    }
}
