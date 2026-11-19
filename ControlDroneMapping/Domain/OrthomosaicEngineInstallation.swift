import Foundation

struct EngineInstallationProgress {
    let message: String
    /// Download progress for the current file; compilation has no reliable percentage.
    var fraction: Double? = nil
    var detail: String? = nil
}

protocol OrthomosaicEngineInstalling {
    var directory: URL { get }
    func install(progress: @escaping (EngineInstallationProgress) -> Void) async throws -> URL
}

struct EngineDownloadFailure: LocalizedError {
    let url: URL
    let cause: URLError

    var errorDescription: String? {
        let host = url.host ?? "layanan unduhan"
        switch cause.code {
        case .cannotFindHost, .dnsLookupFailed:
            return
                "Alamat \(host) tidak dapat ditemukan (DNS). Coba koneksi internet lain atau hotspot, lalu pasang lagi."
        case .notConnectedToInternet:
            return "Mac belum terhubung ke internet. Sambungkan koneksi lalu pasang lagi."
        case .cannotConnectToHost:
            return "\(host) tidak dapat dihubungi. Periksa akses layanan ini pada jaringan yang dipakai."
        case .timedOut:
            return
                "Koneksi ke \(host) melewati batas waktu. Periksa koneksi internet atau DNS lalu coba lagi."
        default:
            return "Unduhan dari \(host) gagal: \(cause.localizedDescription)"
        }
    }
}
