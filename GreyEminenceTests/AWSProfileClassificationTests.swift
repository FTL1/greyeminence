import XCTest
@testable import Grey_Eminence

/// Which AWS profiles this app can actually authenticate as.
///
/// The listing used to return every section of ~/.aws/config, so the picker
/// offered profiles that could never work — selecting one failed with
/// "profile not found" at the first request, which reads as a bug in the app
/// rather than a property of the profile.
final class AWSProfileClassificationTests: XCTestCase {
    private typealias Kind = AWSCredentialLoader.ProfileKind

    func testSSOAndAccessKeyProfilesAreUsable() {
        XCTAssertTrue(Kind.sso.isSupported)
        XCTAssertTrue(Kind.staticCredentials.isSupported)
    }

    func testBlockedHelperErrorNamesTheSandboxAndTheWayForward() {
        // No amount of reconfiguring the AWS profile fixes a sandbox refusal,
        // so the message must not send the user there — it has to name the
        // restriction and the one action that can lift it.
        let message = AWSCredentialError.credentialProcessBlocked("gitf").errorDescription ?? ""
        XCTAssertTrue(message.lowercased().contains("sandbox"), "got: \(message)")
        XCTAssertTrue(message.contains("Locate credential helper"), "must offer the grant, got: \(message)")
    }

    func testAssumeRoleIsNotUsableYet() {
        // role_arn + source_profile needs an STS AssumeRole call that doesn't
        // exist yet. Implementable — unlike credential_process.
        XCTAssertFalse(Kind.assumeRole(source: "org").isSupported)
    }

    func testCredentialProcessIsOffered() {
        // Whether the sandbox permits launching the helper is decided at run
        // time, so the profile is offered and the connection test reports what
        // actually happened — rather than being refused on a guess.
        XCTAssertTrue(Kind.credentialProcess.isSupported)
    }

    // MARK: - Parsing the helper command

    func testQuotedHelperPathSurvivesSpaces() {
        // The real config quotes the path; splitting on whitespace would
        // launch "/Users/mp/Projects/sleipnir" and drop the rest.
        let tokens = AWSCredentialLoader.tokenizeCommand(
            "\"/Applications/My Tools/helper\" creds --profile gitf"
        )
        XCTAssertEqual(tokens, ["/Applications/My Tools/helper", "creds", "--profile", "gitf"])
    }

    func testUnquotedCommandSplitsOnWhitespace() {
        XCTAssertEqual(
            AWSCredentialLoader.tokenizeCommand("/usr/local/bin/helper creds --profile gitf"),
            ["/usr/local/bin/helper", "creds", "--profile", "gitf"]
        )
    }

    func testSingleQuotesWorkToo() {
        XCTAssertEqual(
            AWSCredentialLoader.tokenizeCommand("'/opt/a b/helper' --json"),
            ["/opt/a b/helper", "--json"]
        )
    }

    func testRepeatedWhitespaceDoesNotProduceEmptyArguments() {
        XCTAssertEqual(
            AWSCredentialLoader.tokenizeCommand("  helper   creds  "),
            ["helper", "creds"]
        )
    }

    func testEmptyCommandYieldsNoTokens() {
        XCTAssertTrue(AWSCredentialLoader.tokenizeCommand("   ").isEmpty)
    }

    func testProfileWithNoCredentialsIsNotUsable() {
        XCTAssertFalse(Kind.noCredentials.isSupported)
    }

    func testEveryKindExplainsItself() {
        let kinds: [Kind] = [.sso, .staticCredentials, .assumeRole(source: "org"), .assumeRole(source: nil), .credentialProcess, .noCredentials]
        for kind in kinds {
            XCTAssertFalse(kind.reason.isEmpty, "a profile the user can't pick must say why")
        }
    }

    func testAssumeRoleNamesItsSourceProfile() {
        XCTAssertTrue(Kind.assumeRole(source: "org").reason.contains("org"))
    }

    func testAssumeRoleWithoutASourceStillReads() {
        XCTAssertFalse(Kind.assumeRole(source: nil).reason.contains("nil"))
    }

    func testUsableProfilesIsASubsetOfDescribed() {
        // Reads the developer's real ~/.aws if present; the invariant holds
        // either way, including when both are empty.
        let described = AWSCredentialLoader.describedProfiles()
        let usable = AWSCredentialLoader.usableProfiles()
        XCTAssertLessThanOrEqual(usable.count, described.count)
        XCTAssertTrue(usable.allSatisfy { $0.isSupported })
        XCTAssertTrue(usable.allSatisfy { profile in described.contains { $0.name == profile.name } })
    }

    func testDescribedProfilesAreUniqueAndSorted() {
        let names = AWSCredentialLoader.describedProfiles().map(\.name)
        XCTAssertEqual(names, names.sorted(), "picker order must be stable")
        XCTAssertEqual(Set(names).count, names.count, "a profile in both config and credentials must appear once")
    }
}
