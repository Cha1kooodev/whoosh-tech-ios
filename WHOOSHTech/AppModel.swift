import Foundation
import Combine
import CoreLocation

struct CenterRequest: Equatable {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let meters: Double

    init(coordinate: CLLocationCoordinate2D, meters: Double) {
        self.id = UUID()
        self.coordinate = coordinate
        self.meters = meters
    }

    static func == (lhs: CenterRequest, rhs: CenterRequest) -> Bool {
        lhs.id == rhs.id
    }
}

final class AppModel: ObservableObject {
    static let defaultAnchor = CLLocationCoordinate2D(latitude: 55.7512, longitude: 37.6173)

    @Published private(set) var scooters: [Scooter]
    @Published private(set) var anchor: CLLocationCoordinate2D = AppModel.defaultAnchor
    @Published var query: String = ""
    @Published var selectedID: String?
    @Published private(set) var userLocation: CLLocation?
    @Published private(set) var accuracy: CLLocationAccuracy = 0
    @Published var followUser = false
    @Published var centerRequest: CenterRequest?
    @Published private(set) var gps: LocationProvider.State = .idle
    @Published private(set) var toast: String?

    let location = LocationProvider()

    private var cancellables = Set<AnyCancellable>()
    private var anchoredToUser = false
    private var toastWorkItem: DispatchWorkItem?
    private let statusKey = "whoosh-tech-ios-statuses-v1"

    init() {
        scooters = ScooterCatalog.make()

        if let saved = UserDefaults.standard.dictionary(forKey: statusKey) as? [String: String] {
            for i in scooters.indices {
                if let raw = saved[scooters[i].id], let st = ScooterStatus(rawValue: raw) {
                    scooters[i].status = st
                }
            }
        }

        location.$location
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in self?.handleLocation(loc) }
            .store(in: &cancellables)

        location.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] st in self?.gps = st }
            .store(in: &cancellables)

        location.start()
    }

    // MARK: - Геометрия

    func coordinate(for scooter: Scooter) -> CLLocationCoordinate2D {
        let dLat = scooter.offsetY / 111_320.0
        let dLon = scooter.offsetX / (111_320.0 * cos(anchor.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: anchor.latitude + dLat,
                                      longitude: anchor.longitude + dLon)
    }

    func distance(to scooter: Scooter) -> CLLocationDistance? {
        guard let me = userLocation else { return nil }
        let c = coordinate(for: scooter)
        return me.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
    }

    // MARK: - Поиск и счётчики

    var selectedScooter: Scooter? {
        guard let id = selectedID else { return nil }
        return scooters.first { $0.id == id }
    }

    var searchActive: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matchesSearch(_ scooter: Scooter) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.isEmpty { return true }
        return scooter.code.uppercased().contains(q) || scooter.id.uppercased().contains(q)
    }

    func count(_ status: ScooterStatus) -> Int {
        scooters.filter { $0.status == status }.count
    }

    // MARK: - Действия

    func setStatus(_ status: ScooterStatus, for id: String) {
        guard let index = scooters.firstIndex(where: { $0.id == id }) else { return }
        scooters[index].status = status
        if status == .stolen {
            scooters[index].iotOfflineMinutes = Int.random(in: 20...300)
        }
        persist()
    }

    func closeCard() {
        selectedID = nil
    }

    func recenterOnUser() {
        if let loc = userLocation {
            followUser = true
            centerRequest = CenterRequest(coordinate: loc.coordinate, meters: 900)
        } else {
            location.start()
            showToast("Ищу GPS…")
        }
    }

    func showToast(_ text: String) {
        toastWorkItem?.cancel()
        toast = text
        let item = DispatchWorkItem { [weak self] in self?.toast = nil }
        toastWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: item)
    }

    // MARK: - Приватное

    private func handleLocation(_ loc: CLLocation) {
        userLocation = loc
        accuracy = loc.horizontalAccuracy

        if !anchoredToUser {
            anchoredToUser = true
            let base = CLLocation(latitude: anchor.latitude, longitude: anchor.longitude)
            if base.distance(from: loc) > 1200 {
                anchor = loc.coordinate
                showToast("Самокаты переставлены к вашему району")
            }
            followUser = true
            centerRequest = CenterRequest(coordinate: loc.coordinate, meters: 1100)
        }
    }

    private func persist() {
        let dict = Dictionary(uniqueKeysWithValues: scooters.map { ($0.id, $0.status.rawValue) })
        UserDefaults.standard.set(dict, forKey: statusKey)
    }
}
