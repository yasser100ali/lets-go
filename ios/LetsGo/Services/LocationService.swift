import Foundation
import CoreLocation
import Observation
import OSLog

/// Where you are. Falls back to a fixed neighborhood when location is off,
/// so the map is never empty.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    /// Mission Dolores Park, San Francisco. Used until a real fix arrives.
    static let fallback = CLLocationCoordinate2D(latitude: 37.7596, longitude: -122.4269)

    private(set) var coordinate: CLLocationCoordinate2D?
    private(set) var authorization: CLAuthorizationStatus
    private(set) var lastError: String?
    /// Meters moved since launch, from good fixes only. The night out reads its walk from this.
    private(set) var odometer: Double = 0
    @ObservationIgnored private var lastFix: CLLocation?

    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private let log = Logger(subsystem: "com.yasser100ali.letsgo", category: "location")

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 25
    }

    /// The best center we have: your fix, or the fallback.
    var center: CLLocationCoordinate2D { coordinate ?? Self.fallback }
    var isUsingFallback: Bool { coordinate == nil }
    var isDenied: Bool { authorization == .denied || authorization == .restricted }

    /// Fine-grained fixes while a walk is guiding you turn by turn; coarse the rest of the time.
    func setPrecise(_ on: Bool) {
        manager.desiredAccuracy = on ? kCLLocationAccuracyBest : kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = on ? 4 : 25
    }

    func start() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        default:
            log.info("Location not authorized; using fallback center")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        let c = latest.coordinate
        let accuracy = latest.horizontalAccuracy
        let lat = c.latitude, lon = c.longitude
        Task { @MainActor in
            self.coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            self.lastError = nil
            guard accuracy >= 0, accuracy < 50 else { return }
            let fix = CLLocation(latitude: lat, longitude: lon)
            if let last = self.lastFix {
                let step = fix.distance(from: last)
                // Ignore jitter, and jumps no one walks.
                if step >= 5 && step < 400 { self.odometer += step }
                if step >= 5 { self.lastFix = fix }
            } else {
                self.lastFix = fix
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.manager.startUpdatingLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
            self.log.error("Location failed: \(message, privacy: .public)")
        }
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// A point `east` and `north` meters away. Good enough at neighborhood scale.
    func offset(east: Double, north: Double) -> CLLocationCoordinate2D {
        let dLat = north / 111_320
        let dLon = east / (111_320 * cos(latitude * .pi / 180))
        return .init(latitude: latitude + dLat, longitude: longitude + dLon)
    }

    /// Rounded to ~1 km, so small moves don't re-trigger work keyed on location.
    var roundedKey: String {
        String(format: "%.2f,%.2f", latitude, longitude)
    }
}

enum Walk {
    /// About 80 m a minute.
    static func minutes(_ meters: CLLocationDistance) -> Int {
        max(1, Int((meters / 80).rounded()))
    }

    static func label(_ meters: CLLocationDistance) -> String {
        let m = minutes(meters)
        return m > 30 ? String(format: "%.1f mi", meters / 1609.34) : "\(m) min walk"
    }
}
