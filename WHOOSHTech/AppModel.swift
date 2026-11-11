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
    static let defaultCenter = CLLocationCoordinate2D(latitude: 55.7512, longitude: 37.6173)

    /// Предел области, которую держим в памяти. Дальше — только центр
    /// видимой части: так карта не пытается сгенерировать весь земной шар.
    static let maxSpanLat = 0.06      // ~6.7 км
    static let maxSpanLon = 0.10      // ~6.2 км на широте Москвы

    @Published private(set) var scooters: [Scooter] = []
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
    private var overrides: [String: ScooterStatus] = [:]
    private var generatedBox: ScooterWorld.Box?
    private var visibleBox: ScooterWorld.Box?
    private var pendingSelection: String?
    private var firstFixHandled = false
    private var toastWorkItem: DispatchWorkItem?
    private let statusKey = "whoosh-tech-ios-statuses-v1"

    init() {
        loadOverrides()

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

    // MARK: - Генерация по карте

    /// Вызывается картой: пересчитывает самокаты под видимую область.
    /// Пока видимая область помещается в уже сгенерированную — ничего не делает.
    func refreshVisible(_ box: ScooterWorld.Box) {
        guard box.spanLat > 0, box.spanLon > 0 else { return }
        visibleBox = box

        let clamped = box.limited(maxSpanLat: Self.maxSpanLat, maxSpanLon: Self.maxSpanLon)
        if let generated = generatedBox, generated.contains(clamped) { return }

        let target = clamped
            .expanded(1.3)
            .limited(maxSpanLat: Self.maxSpanLat, maxSpanLon: Self.maxSpanLon)
        generatedBox = target

        let list = ScooterWorld.scooters(in: target, overrides: overrides)
        scooters = list

        if let pending = pendingSelection, list.contains(where: { $0.id == pending }) {
            selectedID = pending
            pendingSelection = nil
        } else if let selected = selectedID, !list.contains(where: { $0.id == selected }) {
            selectedID = nil
        }
    }

    // MARK: - Геометрия

    func distance(to scooter: Scooter) -> CLLocationDistance? {
        guard let me = userLocation else { return nil }
        return me.distance(from: CLLocation(latitude: scooter.latitude,
                                            longitude: scooter.longitude))
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

    /// Ищет самокат на карте, а если рядом нет — сканирует область вокруг
    /// видимого участка и перелетает к найденному.
    func submitSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard q.count >= 2 else { return }

        if let found = scooters.first(where: {
            $0.code.contains(q) || $0.id.uppercased().contains(q)
        }) {
            selectedID = found.id
            centerRequest = CenterRequest(coordinate: found.coordinate, meters: 700)
            return
        }

        guard let visible = visibleBox else { return }
        let area = visible.expanded(3).limited(maxSpanLat: 0.12, maxSpanLon: 0.2)
        let scanned = ScooterWorld.scooters(in: area, overrides: overrides)

        guard let found = scanned.first(where: {
            $0.code.contains(q) || $0.id.uppercased().contains(q)
        }) else {
            showToast("Рядом нет самоката с таким номером")
            return
        }

        pendingSelection = found.id
        centerRequest = CenterRequest(coordinate: found.coordinate, meters: 700)
        showToast("Нашёл: \(found.code)")
    }

    // MARK: - Действия

    func setStatus(_ status: ScooterStatus, for id: String) {
        guard let index = scooters.firstIndex(where: { $0.id == id }) else { return }
        scooters[index].status = status
        if status == .stolen {
            scooters[index].iotOfflineMinutes = Int.random(in: 20...300)
        }
        overrides[id] = status
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

        guard !firstFixHandled else { return }
        firstFixHandled = true

        followUser = true
        centerRequest = CenterRequest(coordinate: loc.coordinate, meters: 1100)
    }

    private func loadOverrides() {
        guard let saved = UserDefaults.standard.dictionary(forKey: statusKey) as? [String: String] else {
            return
        }
        for (key, raw) in saved {
            if let status = ScooterStatus(rawValue: raw) {
                overrides[key] = status
            }
        }
    }

    private func persist() {
        let dict = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key, $0.value.rawValue) })
        UserDefaults.standard.set(dict, forKey: statusKey)
    }
}
