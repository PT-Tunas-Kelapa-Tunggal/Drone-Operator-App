import Foundation

/// Adapter implementing WaypointGenerator by communicating with the embedded QGroundControl HTTP API.
final class QGCWaypointGenerator: WaypointGenerator {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = URL(string: "http://127.0.0.1:18080")!, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func generateWaypoints(
        boundary: [MapCoordinate],
        parameters: SurveyScanParameters
    ) async throws -> SurveyScanResult {
        guard boundary.count >= 3 else {
            throw MappingError.invalid("Batas survei memerlukan minimal 3 titik koordinat.")
        }

        let url = baseURL.appendingPathComponent("api/v1/plan/survey")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = QGCSurveyRequestDTO(boundary: boundary, parameters: parameters)
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            if let errObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = errObj["message"] as? String {
                throw MappingError.invalid(message)
            }
            throw MappingError.invalid("Gagal membuat jalur survei dari mesin QGC.")
        }

        return try QGCSurveyResponseParser.parse(data: data)
    }
}
