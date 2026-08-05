import SwiftUI
import SwiftData

@Observable
@MainActor
final class AppEnvironment {
    let storageManager: StorageManager
    var meetingStore: MeetingStore?

    init() {
        self.storageManager = .shared
    }

    func configure(modelContext: ModelContext) {
        self.meetingStore = MeetingStore(modelContext: modelContext)
        // Register the call-prompt category and delegate before the detector
        // can raise a prompt.
        CallPromptService.shared.configure()
        Task {
            await StalledNotificationService.shared.requestAuthorization()
            StalledNotificationService.shared.refresh(in: modelContext)
        }
    }
}

struct AppEnvironmentKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue = AppEnvironment()
}

extension EnvironmentValues {
    var appEnvironment: AppEnvironment {
        get { self[AppEnvironmentKey.self] }
        set { self[AppEnvironmentKey.self] = newValue }
    }
}
