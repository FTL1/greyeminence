import Foundation

/// Whether this process is hosting an XCTest bundle.
///
/// The unit tests run with the real app as their test host, so launching them
/// starts the app for real — including every side effect `ContentView.onAppear`
/// kicks off against the *live* SwiftData store: startup maintenance, orphan
/// pruning, frame recovery, meeting auto-detection. Tests should never mutate
/// the developer's own data, and a killed test run should never leave a
/// half-finished maintenance pass behind.
///
/// Detected via `XCTestConfigurationFilePath`, which XCTest sets in the host
/// process environment before the app's code runs. Computed once — the
/// environment cannot change under us, and this is read from view lifecycle.
enum TestEnvironment {
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()
}
