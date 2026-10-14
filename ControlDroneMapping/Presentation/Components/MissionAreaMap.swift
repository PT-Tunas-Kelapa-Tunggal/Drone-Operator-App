import AppKit
import MapKit
import SwiftUI

struct MissionAreaMap: NSViewRepresentable {
    var points: [FarmArea.Point]
    var drawing: Bool
    var focus: UUID
    var location: OperatorLocationSample?
    var addPoint: (MapCoordinate) -> Void
    var movePoint: (Int, MapCoordinate) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.showsZoomControls = true
        map.showsCompass = true
        map.delegate = context.coordinator
        map.addGestureRecognizer(
            NSClickGestureRecognizer(
                target: context.coordinator, action: #selector(Coordinator.click(_:))))
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.points != points || coordinator.drawing != drawing {
            coordinator.points = points
            coordinator.drawing = drawing
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            let coordinates = points.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            }
            if coordinates.count >= 3 {
                map.addOverlay(MKPolygon(coordinates: coordinates, count: coordinates.count))
            } else if coordinates.count == 2 {
                map.addOverlay(MKPolyline(coordinates: coordinates, count: coordinates.count))
            }
            for (index, coordinate) in coordinates.enumerated() {
                let vertex = Vertex()
                vertex.index = index
                vertex.coordinate = coordinate
                vertex.title = "Titik \(index + 1)"
                map.addAnnotation(vertex)
            }
        }
        if coordinator.focus != focus {
            coordinator.focus = focus
            if !points.isEmpty {
                var rect = MKMapRect.null
                for point in points {
                    let coordinate = MKMapPoint(
                        CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude))
                    rect = rect.union(MKMapRect(x: coordinate.x, y: coordinate.y, width: 1, height: 1))
                }
                if rect.width < 500 { rect = rect.insetBy(dx: -500, dy: -500) }
                map.setVisibleMapRect(
                    rect, edgePadding: NSEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: false
                )
            } else {
                map.setRegion(
                    MKCoordinateRegion(
                        center: location?.coordinate.clCoordinate
                            ?? CLLocationCoordinate2D(latitude: -2, longitude: 118),
                        span: MKCoordinateSpan(
                            latitudeDelta: location == nil ? 20 : 0.02,
                            longitudeDelta: location == nil ? 30 : 0.02)), animated: false)
            }
        }
    }
    final class Vertex: NSObject, MKAnnotation {
        var index = 0
        var title: String?
        @objc dynamic var coordinate = CLLocationCoordinate2D()
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MissionAreaMap
        var points: [FarmArea.Point]?
        var drawing: Bool?
        var focus: UUID?
        init(_ parent: MissionAreaMap) { self.parent = parent }
        @objc func click(_ gesture: NSClickGestureRecognizer) {
            guard parent.drawing, let map = gesture.view as? MKMapView else { return }
            let position = gesture.location(in: map)
            var hit = map.hitTest(map.convert(position, to: map.superview))
            while let view = hit, view !== map {
                if view is NSControl || view is MKAnnotationView { return }
                hit = view.superview
            }
            let coordinate = map.convert(position, toCoordinateFrom: map)
            parent.addPoint(MapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .systemGreen
                renderer.fillColor = NSColor.systemGreen.withAlphaComponent(0.2)
                renderer.lineWidth = 2
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = .systemGreen
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let vertex = annotation as? Vertex else { return nil }
            let view = MKMarkerAnnotationView(annotation: vertex, reuseIdentifier: nil)
            view.glyphText = "\(vertex.index + 1)"
            view.markerTintColor = .systemGreen
            view.canShowCallout = true
            view.isDraggable = parent.drawing
            return view
        }
        func mapView(
            _ map: MKMapView, annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState
        ) {
            guard newState == .ending, let vertex = view.annotation as? Vertex else { return }
            parent.movePoint(
                vertex.index,
                MapCoordinate(latitude: vertex.coordinate.latitude, longitude: vertex.coordinate.longitude))
            view.dragState = .none
        }
    }
}
