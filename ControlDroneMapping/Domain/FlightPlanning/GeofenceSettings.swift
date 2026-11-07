import Foundation

enum GeofenceType: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case polygon
    case circle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .polygon: return "Poligon (Batas)"
        case .circle: return "Lingkaran (Home)"
        }
    }
}

enum GeofenceBreachAction: String, CaseIterable, Identifiable, Codable, Equatable, Sendable {
    case rtl
    case hold
    case land
    case report

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rtl: return "Kembali ke Home (RTL)"
        case .hold: return "Berhenti & Melayang (Hold)"
        case .land: return "Mendarat di Tempat (Land)"
        case .report: return "Peringatan Saja"
        }
    }
}

/// Input parameters sent to the QGC engine to configure its GeoFenceController.
struct GeofenceSettings: Codable, Equatable, Sendable {
    var enabled: Bool = true
    var type: GeofenceType = .polygon
    var bufferMeters: Double = 20.0
    var radiusMeters: Double = 0.0
    var ceilingMeters: Double = 50.0
    var breachAction: GeofenceBreachAction = .rtl
}

struct SafetyIssue: Codable, Equatable, Identifiable, Sendable {
    var id: String { code + ":" + message }
    let code: String
    let message: String
}

/// Output produced by the QGC engine's GeoFenceController and safety evaluator.
/// The macOS app never computes geofence geometry or coverage locally; this struct
/// holds the authoritative state returned by QGC.
struct SurveySafetyResult: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var type: GeofenceType = .polygon
    var bufferMeters: Double = 0.0
    var radiusMeters: Double = 0.0
    var ceilingMeters: Double = 0.0
    var breachAction: GeofenceBreachAction = .rtl
    var coversMission: Bool = false
    var homeInside: Bool = false
    var uncoveredPointCount: Int = 0
    var ceilingOk: Bool = false
    var polygonCoordinates: [MapCoordinate] = []
    var circleCenter: MapCoordinate? = nil
    var circleRadiusMeters: Double = 0.0
    var breachReturnPoint: MapCoordinate? = nil
    var breachReturnAltitude: Double = 0.0
    var issues: [SafetyIssue] = []
}
