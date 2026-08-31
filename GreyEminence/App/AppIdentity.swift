import Foundation

/// Distinguishes Matt's shipping app from Grey Conseil (this fork).
enum AppIdentity {
    static let productionBundleID = "com.greyeminence.app"
    static let greyConseilBundleID = "com.ftl1.greyeminence"
    /// Dock / menu name. Bundle ID stays `com.ftl1.greyeminence` so the
    /// existing meeting library is not orphaned.
    static let productName = "Grey Conseil"
    /// GitHub repo that Check for Updates talks to. Bundle ID stays
    /// `com.ftl1.greyeminence` (library + TCC). The public repo is
    /// `FTL1/grey-conseil`.
    static let githubRepoPath = "FTL1/grey-conseil"
    static let updatesFeedURL = "https://github.com/FTL1/grey-conseil/releases/latest/download/appcast.xml"

    static var bundleID: String {
        Bundle.main.bundleIdentifier ?? productionBundleID
    }

    static var isProductionBuild: Bool {
        bundleID == productionBundleID
    }

    static var isGreyConseilBuild: Bool {
        !isProductionBuild
    }

    static var displayName: String {
        if isGreyConseilBuild { return productName }
        return (Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? "Grey Eminence"
    }

    /// Application Support folder. Production keeps the historical
    /// `GreyEminence` name so existing libraries stay put. Other bundle IDs
    /// get their own folder so a test build cannot touch production data.
    static var dataFolderName: String {
        isProductionBuild ? "GreyEminence" : bundleID
    }
}
