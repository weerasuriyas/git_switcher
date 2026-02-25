import XCTest
@testable import GitSwitcher

final class GHAccountParserTests: XCTestCase {

    func test_parse_single_active_account() throws {
        let json = """
        {"hosts":{"github.com":[{
            "login":"alice","active":true,"host":"github.com",
            "state":"success","tokenSource":"keyring",
            "scopes":"repo","gitProtocol":"https"
        }]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].login, "alice")
        XCTAssertEqual(accounts[0].host, "github.com")
        XCTAssertTrue(accounts[0].active)
    }

    func test_parse_two_accounts_same_host_one_active() throws {
        let json = """
        {"hosts":{"github.com":[
            {"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"},
            {"login":"bob","active":false,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}
        ]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts.filter { $0.active }.count, 1)
        let bob = accounts.first { $0.login == "bob" }
        XCTAssertNotNil(bob)
        XCTAssertFalse(bob!.active)
    }

    func test_parse_accounts_across_multiple_hosts() throws {
        let json = """
        {"hosts":{
            "github.com":[{"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}],
            "enterprise.internal":[{"login":"corp-alice","active":false,"host":"enterprise.internal","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]
        }}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts.count, 2)
        let hosts = Set(accounts.map { $0.host })
        XCTAssertTrue(hosts.contains("github.com"))
        XCTAssertTrue(hosts.contains("enterprise.internal"))
    }

    func test_parse_empty_hosts_returns_empty_array() throws {
        let accounts = try GHAccountParser.parse(#"{"hosts":{}}"#)
        XCTAssertTrue(accounts.isEmpty)
    }

    func test_parse_invalid_json_throws() {
        XCTAssertThrowsError(try GHAccountParser.parse("not json"))
    }

    func test_display_name_github_com_is_just_login() throws {
        let json = """
        {"hosts":{"github.com":[{"login":"alice","active":true,"host":"github.com","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts[0].displayName, "alice")
    }

    func test_display_name_enterprise_host_includes_hostname() throws {
        let json = """
        {"hosts":{"enterprise.internal":[{"login":"alice","active":false,"host":"enterprise.internal","state":"success","tokenSource":"keyring","scopes":"repo","gitProtocol":"https"}]}}
        """
        let accounts = try GHAccountParser.parse(json)
        XCTAssertEqual(accounts[0].displayName, "alice (enterprise.internal)")
    }
}
