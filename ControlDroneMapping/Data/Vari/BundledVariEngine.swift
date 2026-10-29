import Foundation
import Security

/// Resolves and validates the embedded VariEngine and VariPython helper binary.
public struct BundledVariEngine {
    public struct Manifest: Decodable {
        public let formatVersion: Int
        public let sha256: String
        public let folder: String
        public let teamIdentifier: String
        public let pythonIdentifier: String
        public let architecture: String
        public let version: String
    }

    public static var embeddedDirectory: URL? {
        Bundle.main.url(forResource: "VariEngine", withExtension: nil)
    }

    public static var helperExecutable: URL? {
        Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("VariPython")
    }

    public static func validateEmbedded() throws {
        guard let _ = embeddedDirectory,
              let manifest = Bundle.main.url(forResource: "vari-engine", withExtension: "json")
        else {
            throw MappingError.invalid("Build aplikasi belum menyertakan VariEngine siap pakai.")
        }
        let metadata = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
        guard metadata.formatVersion == 1,
              metadata.architecture == "arm64",
              metadata.pythonIdentifier == "com.hata.ControlDroneMapping.engine.vari"
        else {
            throw MappingError.invalid("Metadata paket VariEngine tidak sesuai.")
        }

        if let teamID = signingInformation()?[kSecCodeInfoTeamIdentifier as String] as? String {
            guard teamID == metadata.teamIdentifier else {
                throw MappingError.invalid("Identitas paket VariEngine tidak sesuai dengan aplikasi (Team ID mismatch).")
            }
        }

        guard let helper = helperExecutable, FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw MappingError.invalid("Helper binary VariPython belum disertakan atau belum dapat dieksekusi.")
        }
    }

    public static func check() throws -> String {
        try validateEmbedded()
        guard let helper = helperExecutable else {
            throw MappingError.invalid("Helper VariPython tidak ditemukan.")
        }

        let process = Process()
        process.executableURL = helper
        process.arguments = ["-m", "krops_vari.main", "--check"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw MappingError.invalid("VariEngine check gagal (status \(process.terminationStatus)): \(output)")
        }

        return output.isEmpty ? "VARI engine siap" : output
    }

    private static func signingInformation() -> [String: Any]? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess
        else { return nil }
        return information as? [String: Any]
    }
}
