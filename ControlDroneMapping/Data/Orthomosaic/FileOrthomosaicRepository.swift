import Foundation
import ImageIO

struct FileOrthomosaicRepository: OrthomosaicRepository {
    let root: URL
    func projectDirectory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString) }
    func load() throws -> [OrthomosaicProject] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ).filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("project.json").path) }
            .map { folder in
                var project = try JSONDecoder().decode(
                    OrthomosaicProject.self,
                    from: Data(contentsOf: folder.appendingPathComponent("project.json")))
                if project.state.isRunning {
                    project.state = .failed
                    project.message = "Pengolahan terinterupsi saat aplikasi ditutup. Jalankan ulang."
                    project.fraction = 0
                    try save(project)
                }
                return project
            }.sorted { $0.createdAt > $1.createdAt }
    }
    func save(_ project: OrthomosaicProject) throws {
        let folder = projectDirectory(project.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(project).write(to: folder.appendingPathComponent("project.json"), options: .atomic)
    }
    func importPhotos(_ urls: [URL], into project: OrthomosaicProject, reference: Bool) throws
        -> OrthomosaicProject
    {
        guard !urls.isEmpty else { throw MappingError.invalid("Pilih foto terlebih dahulu.") }
        let fm = FileManager.default
        let directory = projectDirectory(project.id)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let transaction = UUID().uuidString
        let staging = directory.appendingPathComponent(".import-" + transaction)
        let originals = directory.appendingPathComponent("Originals/" + transaction)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer {
            try? fm.removeItem(at: staging)
            if !committed { try? fm.removeItem(at: originals) }
        }
        var updated = project
        var hashes = Set((reference ? updated.references : updated.photos).map(\.sha256))
        var selectedReferenceID: UUID?
        for (index, url) in urls.enumerated() {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                CGImageSourceGetCount(source) > 0,
                CGImageSourceCopyPropertiesAtIndex(source, 0, nil) != nil
            else { throw MappingError.invalid("Foto tidak dapat dibaca: " + url.lastPathComponent) }
            let hash = try DatasetStore.hashFile(url)
            if !hashes.insert(hash).inserted {
                if reference { selectedReferenceID = updated.references.first { $0.sha256 == hash }?.id }
                continue
            }
            // Unique names also handle duplicate filenames from different Finder directories.
            let name = String(format: "%05d_", index + 1) + url.lastPathComponent
            let temporary = staging.appendingPathComponent(name)
            try fm.copyItem(at: url, to: temporary)
            guard try DatasetStore.hashFile(temporary) == hash else {
                throw MappingError.invalid("Salinan foto tidak cocok: " + url.lastPathComponent)
            }
            let photo = OrthomosaicPhoto(url: originals.appendingPathComponent(name), sha256: hash)
            if reference {
                updated.references.append(photo)
                selectedReferenceID = photo.id
            } else {
                updated.photos.append(photo)
            }
        }
        if reference {
            updated.referenceID = selectedReferenceID
            updated.confirmed = false
            updated.patch = GrayPatch()
        }
        updated.state = .ready
        updated.fraction = 0
        updated.message =
            updated.referenceID == nil
            ? "Foto tersimpan di Mac. Siap diolah tanpa normalisasi warna."
            : "Foto tersimpan di Mac. Konfirmasi area gray card untuk normalisasi."
        try fm.createDirectory(at: originals.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.moveItem(at: staging, to: originals)
        try save(updated)
        committed = true
        return updated
    }
}
