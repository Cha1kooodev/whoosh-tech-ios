import SwiftUI
import UIKit
import MapKit

// MARK: - Аннотация

final class ScooterAnnotation: NSObject, MKAnnotation {
    let scooterID: String
    var code: String
    var status: ScooterStatus
    var dimmed: Bool
    @objc dynamic var coordinate: CLLocationCoordinate2D

    init(scooterID: String, code: String, status: ScooterStatus,
         dimmed: Bool, coordinate: CLLocationCoordinate2D) {
        self.scooterID = scooterID
        self.code = code
        self.status = status
        self.dimmed = dimmed
        self.coordinate = coordinate
        super.init()
    }

    var title: String? { code }
}

// MARK: - Вид пина

final class ScooterAnnotationView: MKAnnotationView {
    static let reuseID = "scooter-tag"

    private let tag = UIView()
    private let label = UILabel()
    private let dot = UIView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)

        isOpaque = false
        backgroundColor = .clear
        clipsToBounds = false
        canShowCallout = false
        collisionMode = .none
        frame = CGRect(x: 0, y: 0, width: 110, height: 44)
        centerOffset = CGPoint(x: 0, y: -9.5)

        tag.layer.cornerRadius = 6
        tag.layer.borderWidth = 1
        tag.backgroundColor = UIColor(red: 0.043, green: 0.055, blue: 0.075, alpha: 1)
        tag.layer.shadowColor = UIColor.black.cgColor
        tag.layer.shadowOpacity = 0.55
        tag.layer.shadowRadius = 4
        tag.layer.shadowOffset = CGSize(width: 0, height: 2)

        label.font = UIFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)
        label.textAlignment = .center
        label.backgroundColor = .clear

        dot.layer.cornerRadius = 6.5
        dot.layer.borderWidth = 1.5
        dot.layer.borderColor = UIColor(red: 0.043, green: 0.055, blue: 0.075, alpha: 1).cgColor

        addSubview(tag)
        tag.addSubview(label)
        addSubview(dot)
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    func apply(annotation: ScooterAnnotation) {
        let color = annotation.status.uiColor
        let code = annotation.code

        label.text = code
        label.textColor = color
        tag.layer.borderColor = color.withAlphaComponent(0.75).cgColor

        let font = label.font ?? UIFont.monospacedSystemFont(ofSize: 10.5, weight: .bold)
        let textWidth = ceil((code as NSString).size(withAttributes: [.font: font]).width)
        let tagWidth = max(34, textWidth + 14)
        let tagHeight: CGFloat = 20

        tag.frame = CGRect(x: (bounds.width - tagWidth) / 2, y: 0, width: tagWidth, height: tagHeight)
        label.frame = tag.bounds
        dot.frame = CGRect(x: (bounds.width - 13) / 2, y: 25, width: 13, height: 13)

        dot.backgroundColor = color
        dot.layer.shadowColor = color.cgColor
        dot.layer.shadowOpacity = 0.9
        dot.layer.shadowRadius = 6
        dot.layer.shadowOffset = .zero

        alpha = annotation.dimmed ? 0.15 : 1
        isUserInteractionEnabled = !annotation.dimmed
    }
}

// MARK: - Карта

struct ScooterMap: UIViewRepresentable {
    @ObservedObject var model: AppModel

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.overrideUserInterfaceStyle = .dark
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = false
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.pointOfInterestFilter = .excludingAll
        map.register(ScooterAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: ScooterAnnotationView.reuseID)

        let region = MKCoordinateRegion(center: AppModel.defaultAnchor,
                                        latitudinalMeters: 2200,
                                        longitudinalMeters: 2200)
        map.setRegion(region, animated: false)

        context.coordinator.mapView = map
        context.coordinator.sync(model: model)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(model: model)
        context.coordinator.updateCamera(model: model, map: map)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: ScooterMap
        weak var mapView: MKMapView?

        private var lastCenterID: UUID?
        private var lastSelectedID: String?
        private var programmatic = false

        init(_ parent: ScooterMap) {
            self.parent = parent
        }

        func sync(model: AppModel) {
            guard let map = mapView else { return }

            var existing: [String: ScooterAnnotation] = [:]
            for annotation in map.annotations {
                if let a = annotation as? ScooterAnnotation {
                    existing[a.scooterID] = a
                }
            }

            var toAdd: [ScooterAnnotation] = []

            for sc in model.scooters {
                let coordinate = model.coordinate(for: sc)
                let dimmed = !model.matchesSearch(sc)

                if let ann = existing[sc.id] {
                    if ann.code != sc.code { ann.code = sc.code }
                    if ann.status != sc.status { ann.status = sc.status }
                    if ann.dimmed != dimmed { ann.dimmed = dimmed }
                    if ann.coordinate.latitude != coordinate.latitude ||
                       ann.coordinate.longitude != coordinate.longitude {
                        ann.coordinate = coordinate
                    }
                } else {
                    toAdd.append(ScooterAnnotation(scooterID: sc.id,
                                                   code: sc.code,
                                                   status: sc.status,
                                                   dimmed: dimmed,
                                                   coordinate: coordinate))
                }
            }

            let modelIDs = Set(model.scooters.map { $0.id })
            let toRemove = existing.values.filter { !modelIDs.contains($0.scooterID) }

            if !toRemove.isEmpty {
                map.removeAnnotations(Array(toRemove))
            }
            if !toAdd.isEmpty {
                map.addAnnotations(toAdd)
            }

            for annotation in map.annotations {
                guard let a = annotation as? ScooterAnnotation,
                      let view = map.view(for: a) as? ScooterAnnotationView else { continue }
                view.apply(annotation: a)
            }
        }

        func updateCamera(model: AppModel, map: MKMapView) {
            if let request = model.centerRequest, request.id != lastCenterID {
                lastCenterID = request.id
                programmatic = true
                let region = MKCoordinateRegion(center: request.coordinate,
                                                latitudinalMeters: request.meters,
                                                longitudinalMeters: request.meters)
                map.setRegion(region, animated: true)
            }

            if model.followUser, let user = model.userLocation?.coordinate {
                let center = map.centerCoordinate
                let distance = CLLocation(latitude: center.latitude, longitude: center.longitude)
                    .distance(from: CLLocation(latitude: user.latitude, longitude: user.longitude))
                if distance > 35 {
                    programmatic = true
                    map.setCenter(user, animated: false)
                }
            }

            if model.selectedID != lastSelectedID {
                lastSelectedID = model.selectedID
                guard let id = model.selectedID,
                      let sc = model.scooters.first(where: { $0.id == id }) else { return }

                let coordinate = model.coordinate(for: sc)
                let point = map.point(for: MKMapPoint(coordinate))
                programmatic = true

                if map.bounds.contains(point) {
                    let target = CGPoint(x: point.x, y: point.y + 120)
                    map.setCenter(map.convert(target, toCoordinateFrom: map), animated: true)
                } else {
                    let region = MKCoordinateRegion(center: coordinate,
                                                    latitudinalMeters: 900,
                                                    longitudinalMeters: 900)
                    map.setRegion(region, animated: true)
                }
            }
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let ann = annotation as? ScooterAnnotation else { return nil }

            let view = mapView.dequeueReusableAnnotationView(
                withIdentifier: ScooterAnnotationView.reuseID,
                for: ann
            ) as? ScooterAnnotationView
            let result = view ?? ScooterAnnotationView(annotation: ann,
                                                       reuseIdentifier: ScooterAnnotationView.reuseID)
            result.annotation = ann
            result.apply(annotation: ann)
            return result
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            guard let ann = annotation as? ScooterAnnotation else { return }
            mapView.deselectAnnotation(annotation, animated: false)
            parent.model.selectedID = ann.scooterID
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            if programmatic {
                programmatic = false
                return
            }
            if parent.model.followUser {
                parent.model.followUser = false
            }
        }
    }
}
