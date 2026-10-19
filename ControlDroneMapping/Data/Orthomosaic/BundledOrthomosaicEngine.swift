import Foundation
import Security

/// Installs a release-built runtime. No developer tools or code compilation run inside the app.
struct BundledOrthomosaicEngine {
    let archive: URL
    let manifest: URL

    struct Manifest: Decodable {
        let formatVersion: Int
        let sha256: String
        let folder: String
        let teamIdentifier: String
        let pythonIdentifier: String
        let architecture: String
    }

    static var available: Self? {
        guard let archive = Bundle.main.url(forResource: "orthomosaic-engine", withExtension: "zip"),
            let manifest = Bundle.main.url(forResource: "orthomosaic-engine", withExtension: "json")
        else { return nil }
        return Self(archive: archive, manifest: manifest)
    }

    static var embeddedDirectory: URL? {
        Bundle.main.url(forResource: "OrthomosaicEngine", withExtension: nil)
    }

    static func validateEmbedded() throws {
        guard let directory = embeddedDirectory,
            let manifest = Bundle.main.url(forResource: "orthomosaic-engine", withExtension: "json")
        else { throw MappingError.invalid("Build aplikasi belum menyertakan engine siap pakai.") }
        let metadata = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
        guard metadata.formatVersion == 1, metadata.architecture == "arm64",
            metadata.teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
            metadata.pythonIdentifier == "com.hata.ControlDroneMapping.engine.python",
            signingInformation()?[kSecCodeInfoTeamIdentifier as String] as? String == metadata.teamIdentifier
        else { throw MappingError.invalid("Identitas paket engine tidak sesuai dengan aplikasi.") }
        let package = Self(archive: directory, manifest: manifest)
        guard let helper = Bundle.main.executableURL?.deletingLastPathComponent()
            .appendingPathComponent("OrthomosaicPython")
        else { throw MappingError.invalid("Helper engine belum disertakan dalam aplikasi.") }
        try package.validatePython(helper, metadata: metadata)
    }

    static var isSandboxed: Bool {
        let info = signingInformation()
        let entitlements = info?[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        return entitlements?["com.apple.security.app-sandbox"] as? Bool == true
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

    func install(
        at directory: URL, log: URL, progress: @escaping (EngineInstallationProgress) -> Void
    ) async throws {
        let fm = FileManager.default
        progress(.init(message: "Memeriksa paket engine…"))
        let metadata = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifest))
        guard metadata.formatVersion == 1, metadata.folder == "OpenSfM-engine",
            metadata.architecture == "arm64",
            metadata.teamIdentifier.range(of: "^[A-Z0-9]{10}$", options: .regularExpression) != nil,
            metadata.pythonIdentifier == "com.hata.ControlDroneMapping.engine.python",
            try DatasetStore.hashFile(archive) == metadata.sha256
        else { throw MappingError.invalid("Paket engine tidak lolos pemeriksaan. Build ulang paket engine.") }
        guard Self.signingInformation()?[kSecCodeInfoTeamIdentifier as String] as? String
            == metadata.teamIdentifier
        else { throw MappingError.invalid("Paket engine harus ditandatangani oleh pembuat aplikasi yang sama.") }
        try Task.checkCancellation()
        // The current directory also contains the installation lock and diagnostic log.
        // Publish only the validated runtime's two subdirectories, keeping those files intact.
        let staging = directory.appendingPathComponent("Unpack-" + UUID().uuidString)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        progress(.init(message: "Memasang engine…", detail: "Menyiapkan pengolahan lokal di Mac ini."))
        try await EngineInstallProcess().run(
            URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, staging.path],
            environment: ProcessInfo.processInfo.environment, log: log)
        try Task.checkCancellation()
        let unpacked = staging.appendingPathComponent(metadata.folder)
        try validatePython(LocalOrthomosaicProcessor.python(in: unpacked), metadata: metadata)
        for name in ["environment", "OpenSfM", "engine.json"] {
            let input = unpacked.appendingPathComponent(name)
            guard fm.fileExists(atPath: input.path) else {
                throw MappingError.invalid("Isi paket engine belum lengkap: " + name)
            }
        }
        let readyMarker = directory.appendingPathComponent("engine.json")
        if fm.fileExists(atPath: readyMarker.path) { try fm.removeItem(at: readyMarker) }
        for name in ["environment", "OpenSfM", "engine.json"] {
            try Task.checkCancellation()
            let destination = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: unpacked.appendingPathComponent(name), to: destination)
        }
    }

    private func validatePython(_ python: URL, metadata: Manifest) throws {
        var code: SecStaticCode?
        let resolved = python.resolvingSymlinksInPath()
        guard SecStaticCodeCreateWithPath(resolved as CFURL, [], &code) == errSecSuccess, let code else {
            throw MappingError.invalid("Tanda tangan Python engine tidak dapat dibaca.")
        }
        let expression = "anchor apple generic and certificate leaf[subject.OU] = \""
            + metadata.teamIdentifier + "\" and identifier \"" + metadata.pythonIdentifier + "\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(expression as CFString, [], &requirement) == errSecSuccess,
            SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSStrictValidate), requirement)
                == errSecSuccess
        else { throw MappingError.invalid("Tanda tangan Python engine tidak valid.") }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let info = information as? [String: Any],
            let entitlements = info[kSecCodeInfoEntitlementsDict as String] as? [String: Any],
            entitlements["com.apple.security.app-sandbox"] as? Bool == true,
            entitlements["com.apple.security.inherit"] as? Bool == true,
            entitlements.count == 2
        else { throw MappingError.invalid("Python engine harus mewarisi pembatasan sandbox aplikasi.") }
    }
}
