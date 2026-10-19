import Foundation

/// One folder grant covers the Python environment, its native libraries, and OpenSfM sources.
struct OrthomosaicRuntimeAccess {
    let defaults: UserDefaults
    var key = "orthomosaic-runtime-bookmark-v1"
    func remember(_ url: URL) throws {
        let data = try url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        defaults.set(data, forKey: key)
    }
    func resolve() throws -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(
            resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil,
            bookmarkDataIsStale: &stale)
        if stale { try remember(url) }
        return url
    }
}
