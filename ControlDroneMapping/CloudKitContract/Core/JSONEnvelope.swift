import Foundation

/// Standard envelope wrapping JSON payload fields stored as CloudKit strings.
/// Provides semver tracking and tolerant additive evolution.
nonisolated public struct JSONEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let version: String
    public let payload: Payload

    public init(version: String = "1.0.0", payload: Payload) {
        self.version = version
        self.payload = payload
    }

    /// Encodes the envelope and its payload into a JSON UTF-8 string.
    public static func encodeToString(_ payload: Payload, version: String = "1.0.0") throws -> String {
        let envelope = JSONEnvelope(version: version, payload: payload)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(envelope)
        guard let string = String(data: data, encoding: .utf8) else {
            throw FieldError.decodingError(key: "envelope", errorDescription: "Failed to convert encoded JSON to UTF-8 string")
        }
        return string
    }

    /// Inspects the version tag inside a raw JSON string without decoding the entire payload.
    public static func inspectVersion(from rawJSON: String) -> String? {
        guard let data = rawJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let version = json["version"] as? String else {
            return nil
        }
        return version
    }

    /// Decodes an envelope string into its payload, optionally tagging errors with a field key.
    public static func decodeFromString(
        _ rawJSON: String,
        key: String = "envelope"
    ) -> Result<Payload, FieldError> {
        guard let data = rawJSON.data(using: .utf8) else {
            return .failure(.decodingError(key: key, errorDescription: "Invalid UTF-8 string data"))
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let envelope = try decoder.decode(JSONEnvelope<Payload>.self, from: data)
            return .success(envelope.payload)
        } catch {
            return .failure(.decodingError(key: key, errorDescription: error.localizedDescription))
        }
    }
}
