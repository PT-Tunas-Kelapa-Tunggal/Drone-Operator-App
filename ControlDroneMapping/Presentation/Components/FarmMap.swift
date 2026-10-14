import MapKit
import SwiftUI

struct FarmMap: NSViewRepresentable {
    var areas: [FarmArea]
    @Binding var selected: UUID?
    var operatorLocation: OperatorLocationSample? = nil
    var focusRequest: UUID? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.showsZoomControls = true
        map.showsCompass = true
        map.showsScale = true
        map.delegate = context.coordinator
        map.setRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: -2, longitude: 118),
                span: MKCoordinateSpan(latitudeDelta: 20, longitudeDelta: 30)), animated: false)
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        let previous = context.coordinator.parent
        context.coordinator.parent = self
        let ids = areas.map(\.id)
        if context.coordinator.ids != ids {
            context.coordinator.ids = ids
            map.removeOverlays(map.overlays)
            map.removeAnnotations(map.annotations)
            context.coordinator.lastOperatorLocation = nil
            context.coordinator.operatorCircle = nil
            for area in areas {
                let polygon = MKPolygon(coordinates: area.coordinates, count: area.points.count)
                polygon.title = area.id.uuidString
                map.addOverlay(polygon)
                let marker = AreaMarker()
                marker.id = area.id
                marker.title = area.name
                marker.coordinate = polygon.coordinate
                map.addAnnotation(marker)
            }
            if let first = map.overlays.first {
                let rect = map.overlays.dropFirst().reduce(first.boundingMapRect) {
                    $0.union($1.boundingMapRect)
                }
                map.setVisibleMapRect(
                    rect, edgePadding: NSEdgeInsets(top: 50, left: 50, bottom: 150, right: 50),
                    animated: false)
            }
        }
        if context.coordinator.lastOperatorLocation != operatorLocation {
            context.coordinator.lastOperatorLocation = operatorLocation
            map.removeAnnotations(map.annotations.filter { $0 is OperatorMarker })
            if let circle = context.coordinator.operatorCircle { map.removeOverlay(circle) }
            context.coordinator.operatorCircle = nil
            if let operatorLocation {
                let marker = OperatorMarker()
                marker.coordinate = operatorLocation.coordinate.clCoordinate
                map.addAnnotation(marker)
                let circle = MKCircle(center: marker.coordinate, radius: operatorLocation.accuracy)
                context.coordinator.operatorCircle = circle
                map.addOverlay(circle)
            }
        }
        if let focusRequest, context.coordinator.lastFocusRequest != focusRequest, let operatorLocation {
            context.coordinator.lastFocusRequest = focusRequest
            map.setRegion(
                MKCoordinateRegion(
                    center: operatorLocation.coordinate.clCoordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.06, longitudeDelta: 0.06)), animated: true)
        }
        if previous.selected != selected {
            for overlay in map.overlays {
                if let renderer = map.renderer(for: overlay) as? MKPolygonRenderer {
                    context.coordinator.style(renderer)
                }
            }
        }
    }
    final class OperatorMarker: NSObject, MKAnnotation {
        var title: String? = "Lokasi Mac (perkiraan)"
        @objc dynamic var coordinate = CLLocationCoordinate2D()
    }
    final class AreaMarker: NSObject, MKAnnotation {
        var id = UUID()
        var title: String?
        @objc dynamic var coordinate = CLLocationCoordinate2D()
    }
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: FarmMap
        var ids = [UUID]()
        var lastOperatorLocation: OperatorLocationSample?
        var operatorCircle: MKCircle?
        var lastFocusRequest: UUID?
        init(_ parent: FarmMap) { self.parent = parent }
        func style(_ renderer: MKPolygonRenderer) {
            let chosen = renderer.polygon.title == parent.selected?.uuidString
            renderer.strokeColor = chosen ? NSColor.systemGreen : NSColor.white
            renderer.fillColor = NSColor.systemGreen.withAlphaComponent(chosen ? 0.22 : 0.06)
            renderer.lineWidth = chosen ? 3 : 2
            renderer.setNeedsDisplay()
        }
        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let circle = overlay as? MKCircle {
                let renderer = MKCircleRenderer(circle: circle)
                renderer.strokeColor = .systemBlue
                renderer.fillColor = NSColor.systemBlue.withAlphaComponent(0.12)
                renderer.lineWidth = 1
                return renderer
            }
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            style(renderer)
            return renderer
        }
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is OperatorMarker {
                let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)
                view.canShowCallout = true
                return view
            }
            guard annotation is AreaMarker else { return nil }
            let view = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: nil)
            view.markerTintColor = .systemGreen
            view.glyphImage = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: nil)
            view.canShowCallout = true
            return view
        }
        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let marker = view.annotation as? AreaMarker { parent.selected = marker.id }
        }
    }
}

extension FarmArea {
    var coordinates: [CLLocationCoordinate2D] {
        points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }
}
