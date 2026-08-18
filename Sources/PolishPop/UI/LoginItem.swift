import Foundation
import ServiceManagement

/// Wraps the login-item registration so the settings toggle can report failures instead of
/// silently disagreeing with what macOS actually did.
enum LoginItem {
    enum RegistrationError: Error {
        case refused
    }

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True when macOS is waiting for the user to approve PolishPop in Login Items.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            throw RegistrationError.refused
        }
    }
}
