import ServiceManagement

/// Encapsulates Launch-at-Login registration logic so it can be unit-tested
/// without touching the real SMAppService on a real machine.
@Observable @MainActor
final class LaunchAtLoginManager {
    var isEnabled: Bool = SMAppService.mainApp.status == .enabled

    func setEnabled(_ newValue: Bool) {
        do {
            if newValue {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            isEnabled = newValue
        } catch {
            // Revert to actual service state on failure
            isEnabled = SMAppService.mainApp.status == .enabled
        }
    }
}
