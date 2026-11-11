import Foundation
import CoreLocation

/// Реальный GPS устройства через CoreLocation.
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {

    enum State: Equatable {
        case idle
        case searching
        case ok
        case denied
        case unavailable
        case timeout

        var chipText: String {
            switch self {
            case .idle:        return "GPS"
            case .searching:   return "поиск…"
            case .ok:          return "GPS"
            case .denied:      return "нет доступа"
            case .unavailable: return "GPS недоступен"
            case .timeout:     return "таймаут"
            }
        }
    }

    @Published private(set) var location: CLLocation?
    @Published private(set) var state: State = .idle

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 2

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            state = .searching
        case .denied, .restricted:
            state = .denied
        default:
            state = .idle
        }
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            state = .searching
        }
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        DispatchQueue.main.async {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                self.state = .searching
                manager.startUpdatingLocation()
            case .denied, .restricted:
                self.state = .denied
            default:
                self.state = .idle
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last, loc.horizontalAccuracy > 0 else { return }
        DispatchQueue.main.async {
            self.location = loc
            self.state = .ok
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let ns = error as NSError
        DispatchQueue.main.async {
            guard ns.domain == kCLErrorDomain else {
                self.state = .unavailable
                return
            }
            switch ns.code {
            case 1:  self.state = .denied       // CLError.denied
            case 0:  self.state = .timeout      // CLError.locationUnknown
            default: self.state = .unavailable
            }
        }
    }
}
