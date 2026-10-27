import AppKit
import MapKit
import SwiftUI

struct WaypointMap: NSViewRepresentable {
    let route: FlightRoute
    let farm: FarmArea?
    let operatorLocation: OperatorLocationSample?
    let mode: FlightMapEditMode
    let fitRequest: UUID
    @Binding var selectedWaypoint: UUID?
    var onClick: (MapCoordinate) -> Void
    var onMove: (UUID, MapCoordinate) -> Void
    var drawingBoundary = false
    var editingEnabled = true
    var dragWhileAdding = false
    var focusOperator = false
    var planningStep: FlightPlanningStep = .flight
    var onBoundaryClick: ((MapCoordinate) -> Void)? = nil
    var onBoundaryMove: ((Int, MapCoordinate) -> Void)? = nil
    var onHomeMove: ((MapCoordinate) -> Void)? = nil
    var onEntryMove: ((MapCoordinate) -> Void)? = nil
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.mapType = .satellite
        map.showsZoomControls = true
        map.showsCompass = true
        map.delegate = context.coordinator
        let gesture = NSClickGestureRecognizer(
            target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        gesture.numberOfClicksRequired = 1
        gesture.delegate = context.coordinator
        gesture.delaysPrimaryMouseButtonEvents = false
        map.addGestureRecognizer(gesture)
        return map
    }
    func updateNSView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        // A one-second dashboard heartbeat must not interrupt an annotation drag.
        let key = MapState(
            route: route, farm: farm, sample: operatorLocation, mode: mode,
            drawingBoundary: drawingBoundary, editingEnabled: editingEnabled,
            planningStep: planningStep)
        if coordinator.lastState != key {
            coordinator.lastState = key
            map.removeAnnotations(map.annotations)
            map.removeOverlays(map.overlays)
            let boundaryCoords: [CLLocationCoordinate2D] = {
                if route.waypoints.count >= 3 {
                    return route.waypoints.filter { $0.coordinate.isValid }.map { $0.coordinate.clCoordinate }
                } else if let farm = farm, farm.points.count >= 3 {
                    return farm.coordinates
                }
                return []
            }()
            if boundaryCoords.count >= 3 {
                map.addOverlay(MKPolygon(coordinates: boundaryCoords, count: boundaryCoords.count))
            } else if boundaryCoords.count == 2 {
                map.addOverlay(MKPolyline(coordinates: boundaryCoords, count: boundaryCoords.count))
            }
            if let farm, drawingBoundary {
                for (index, coordinate) in farm.coordinates.enumerated() {
                    let marker = RouteMarker()
                    marker.kind = .boundary
                    marker.number = index + 1
                    marker.title = "Batas \(index + 1)"
                    marker.coordinate = coordinate
                    map.addAnnotation(marker)
                }
            }

            if planningStep == .boundary {
                // In Step 1: Batas Area
                // Only boundary vertex pins are shown and editable. Home, Entry, Exit, and transect lines are strictly hidden.
                for (index, point) in route.waypoints.enumerated() where point.coordinate.isValid {
                    let marker = RouteMarker()
                    marker.id = point.id
                    marker.kind = .waypoint
                    marker.title = "Titik Batas \(index + 1)"
                    marker.number = index + 1
                    marker.coordinate = point.coordinate.clCoordinate
                    map.addAnnotation(marker)
                }
            } else {
                // In Step 2: Parameter & Jalur Terbang
                // Boundary vertex markers are hidden so operator cannot alter or drag the boundary.
                // Home (H) and Entry (E) pins, Exit marker, and QGC survey transect lines are shown.
                if let home = route.home, home.isValid {
                    let marker = RouteMarker()
                    marker.kind = .home
                    marker.title = "Home (Lepas Landas & Mendarat)"
                    marker.coordinate = home.clCoordinate
                    map.addAnnotation(marker)
                }
                let effectiveEntry = route.surveyEntry ?? route.visualTransects.first
                if let entry = effectiveEntry, entry.isValid {
                    let entryMarker = RouteMarker()
                    entryMarker.kind = .surveyEntry
                    entryMarker.title = "Titik Masuk Survei (Entry)"
                    entryMarker.coordinate = entry.clCoordinate
                    map.addAnnotation(entryMarker)
                }
                if !route.visualTransects.isEmpty {
                    if let last = route.visualTransects.last, last.isValid, route.visualTransects.count > 1 {
                        let exitMarker = RouteMarker()
                        exitMarker.kind = .surveyExit
                        exitMarker.title = "Titik Selesai Survei (Exit)"
                        exitMarker.coordinate = last.clCoordinate
                        map.addAnnotation(exitMarker)
                    }
                    let transectCoords = route.visualTransects.map(\.clCoordinate)
                    let transectLine = SurveyTransectPolyline(coordinates: transectCoords, count: transectCoords.count)
                    map.addOverlay(transectLine)

                    if let home = route.home, home.isValid {
                        if let entry = effectiveEntry {
                            let ingressCoords = [home.clCoordinate, entry.clCoordinate]
                            map.addOverlay(SurveyTransitPolyline(coordinates: ingressCoords, count: 2))
                            if let first = route.visualTransects.first, entry != first {
                                let connectCoords = [entry.clCoordinate, first.clCoordinate]
                                map.addOverlay(SurveyTransitPolyline(coordinates: connectCoords, count: 2))
                            }
                        }
                        if let last = route.visualTransects.last, route.returnToHome {
                            let egressCoords = [last.clCoordinate, home.clCoordinate]
                            map.addOverlay(SurveyTransitPolyline(coordinates: egressCoords, count: 2))
                        }
                    }
                } else if let home = route.home, home.isValid, let entry = effectiveEntry {
                    let ingressCoords = [home.clCoordinate, entry.clCoordinate]
                    map.addOverlay(SurveyTransitPolyline(coordinates: ingressCoords, count: 2))
                }
            }

            if let operatorLocation {
                let marker = RouteMarker()
                marker.kind = .operatorLocation
                marker.title = "Lokasi Mac (perkiraan)"
                marker.coordinate = operatorLocation.coordinate.clCoordinate
                map.addAnnotation(marker)
            }
        }
        if dragWhileAdding {
            for case let marker as RouteMarker in map.annotations where marker.kind == .waypoint {
                if let view = map.view(for: marker) as? MKMarkerAnnotationView {
                    view.markerTintColor = marker.id == selectedWaypoint ? .systemBlue : .systemOrange
                }
            }
        }
        if coordinator.lastFit != fitRequest {
            coordinator.lastFit = fitRequest
            let coordinates =
                (route.home.flatMap { $0.isValid ? [$0.clCoordinate] : nil } ?? [])
                + route.waypoints.filter { $0.coordinate.isValid }.map { $0.coordinate.clCoordinate }
                + (farm?.coordinates ?? [])
                + route.visualTransects.map(\.clCoordinate)
            if focusOperator, let operatorLocation {
                map.setRegion(
                    MKCoordinateRegion(
                        center: operatorLocation.coordinate.clCoordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)), animated: true)
            } else if !coordinates.isEmpty {
                var rect = MKMapRect.null
                for coordinate in coordinates {
                    let p = MKMapPoint(coordinate)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
                }
                if rect.size.width < 1000 { rect = rect.insetBy(dx: -1000, dy: -1000) }
                map.setVisibleMapRect(
                    rect, edgePadding: NSEdgeInsets(top: 60, left: 50, bottom: 60, right: 50), animated: false
                )
            } else {
                let center =
                    operatorLocation?.coordinate.clCoordinate
                    ?? CLLocationCoordinate2D(latitude: -2, longitude: 118)
                map.setRegion(
                    MKCoordinateRegion(
                        center: center,
                        span: MKCoordinateSpan(
                            latitudeDelta: operatorLocation == nil ? 20 : 0.015,
                            longitudeDelta: operatorLocation == nil ? 30 : 0.015)), animated: false)
            }
        }
    }
    struct MapState: Equatable {
        var route: FlightRoute
        var farm: FarmArea?
        var sample: OperatorLocationSample?
        var mode: FlightMapEditMode
        var drawingBoundary: Bool
        var editingEnabled: Bool
        var planningStep: FlightPlanningStep
    }
final class SurveyTransectPolyline: MKPolyline {}
final class SurveyTransitPolyline: MKPolyline {}

    final class RouteMarker: NSObject, MKAnnotation {
        enum Kind { case home, waypoint, boundary, operatorLocation, surveyEntry, surveyExit }
        var kind = Kind.waypoint
        var id = UUID()
        var number = 0
        var title: String?
        @objc dynamic var coordinate = CLLocationCoordinate2D()
    }
    final class Coordinator: NSObject, MKMapViewDelegate, NSGestureRecognizerDelegate {
        var parent: WaypointMap
        var lastState: MapState?
        var lastFit: UUID?
        init(_ parent: WaypointMap) { self.parent = parent }
        func gestureRecognizer(
            _ gestureRecognizer: NSGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer
        ) -> Bool { true }
        @objc func clicked(_ gesture: NSClickGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let position = gesture.location(in: map)
            // Explicitly select markers before handling a blank-map click. This also
            // works when MapKit's own gestures consume the annotation's mouse event.
            for annotation in map.annotations {
                guard let marker = annotation as? RouteMarker,
                    let view = map.view(for: marker),
                    view.bounds.contains(view.convert(position, from: map))
                else { continue }
                if marker.kind == .waypoint { parent.selectedWaypoint = marker.id }
                map.selectAnnotation(marker, animated: false)
                return
            }
            guard parent.editingEnabled else { return }
            if parent.planningStep == .boundary {
                guard parent.mode == .waypoint || parent.drawingBoundary else { return }
            } else {
                guard parent.mode == .home || parent.mode == .entry else { return }
            }
            var hit = map.hitTest(map.convert(position, to: map.superview))
            while let view = hit, view !== map {
                if view is NSControl || view is MKAnnotationView { return }
                hit = view.superview
            }
            let coordinate = map.convert(position, toCoordinateFrom: map)
            let point = MapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
            if parent.drawingBoundary { parent.onBoundaryClick?(point) } else { parent.onClick(point) }
        }
        func mapView(_ map: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is SurveyTransectPolyline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = .systemCyan
                renderer.lineWidth = 3
                return renderer
            }
            if overlay is SurveyTransitPolyline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = .systemCyan
                renderer.lineWidth = 2
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            if let polygon = overlay as? MKPolygon {
                let renderer = MKPolygonRenderer(polygon: polygon)
                renderer.strokeColor = .systemGreen
                renderer.fillColor = NSColor.systemGreen.withAlphaComponent(0.2)
                renderer.lineWidth = 2
                return renderer
            }
            if let line = overlay as? MKPolyline {
                let renderer = MKPolylineRenderer(polyline: line)
                renderer.strokeColor = .systemOrange
                renderer.lineWidth = 3
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }
        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let marker = annotation as? RouteMarker else { return nil }
            let view = MKMarkerAnnotationView(annotation: marker, reuseIdentifier: nil)
            view.canShowCallout = !parent.dragWhileAdding
            if parent.dragWhileAdding { view.titleVisibility = .hidden }
            switch marker.kind {
            case .home:
                view.markerTintColor = .systemGreen
                view.glyphText = "H"
                view.isDraggable =
                    parent.editingEnabled && parent.planningStep == .flight
                    && (parent.mode == .inspect || parent.dragWhileAdding)
                    && !parent.drawingBoundary && parent.onHomeMove != nil
            case .surveyEntry:
                view.markerTintColor = .systemCyan
                view.glyphText = "E"
                view.isDraggable =
                    parent.editingEnabled && parent.planningStep == .flight
                    && !parent.drawingBoundary && parent.onEntryMove != nil
            case .surveyExit:
                view.markerTintColor = .systemCyan
                view.glyphText = "X"
                view.isDraggable = false
            case .waypoint:
                view.markerTintColor = .systemOrange
                view.glyphText = "\(marker.number)"
                view.isDraggable =
                    parent.editingEnabled && parent.planningStep == .boundary
                    && (parent.mode == .inspect || parent.dragWhileAdding)
                    && !parent.drawingBoundary
            case .boundary:
                view.markerTintColor = .systemGreen
                view.glyphText = "\(marker.number)"
                view.isDraggable = parent.editingEnabled && parent.drawingBoundary
            case .operatorLocation:
                view.markerTintColor = .systemBlue
                view.glyphImage = NSImage(systemSymbolName: "person.fill", accessibilityDescription: nil)
            }
            return view
        }
        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            if let marker = view.annotation as? RouteMarker, marker.kind == .waypoint {
                parent.selectedWaypoint = marker.id
            }
        }
        func mapView(
            _ map: MKMapView, annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState
        ) {
            switch newState {
            case .starting:
                view.dragState = .dragging
            case .ending:
                view.dragState = .none
                guard parent.editingEnabled,
                    let marker = view.annotation as? RouteMarker
                else { return }
                let coordinate = MapCoordinate(
                    latitude: marker.coordinate.latitude, longitude: marker.coordinate.longitude)
                switch marker.kind {
                case .waypoint: parent.onMove(marker.id, coordinate)
                case .boundary: parent.onBoundaryMove?(marker.number - 1, coordinate)
                case .home: parent.onHomeMove?(coordinate)
                case .surveyEntry: parent.onEntryMove?(coordinate)
                case .surveyExit, .operatorLocation: break
                }
            case .canceling:
                view.dragState = .none
            default:
                break
            }
        }
    }
}

extension MapCoordinate {
    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
