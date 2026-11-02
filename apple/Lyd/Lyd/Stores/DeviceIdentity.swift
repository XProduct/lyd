import Foundation
#if os(iOS) || os(tvOS)
import UIKit
#endif

enum DeviceIdentity {
    private static let idKey = "lyd.deviceId"

    static var deviceId: String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: idKey), !existing.isEmpty {
            return existing
        }
        let created = UUID().uuidString
        defaults.set(created, forKey: idKey)
        return created
    }

    static var displayName: String {
        #if os(tvOS)
        return UIDevice.current.name
        #elseif os(iOS)
        return UIDevice.current.name
        #else
        return "This device"
        #endif
    }
}
