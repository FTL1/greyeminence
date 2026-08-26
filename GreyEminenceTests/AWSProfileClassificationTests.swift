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

    func testAssumeRoleIsNotUsableYet() {
        // role_arn + source_profile needs an STS AssumeRole call that doesn't
        // exist yet. Implementable — unlike credential_process.
        XCTAssertFalse(Kind.assumeRole(source: "org").isSupported)
    }

    func testCredentialProcessIsNotUsable() {
        // Shells out to an external helper; the app is sandboxed and cannot
        // spawn one. This is permanent, not pending.
        XCTAssertFalse(Kind.credentialProcess.isSupported)
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
