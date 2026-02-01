import Foundation
import AppKit

struct SecurityScopedBookmarkEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var path: String
    var data: Data
    
    init(id: UUID = UUID(), path: String, data: Data) {
        self.id = id
        self.path = path
        self.data = data
    }
}

final class SecurityScopedBookmarkStore: ObservableObject {
    static let shared = SecurityScopedBookmarkStore()
    
    @Published private(set) var entries: [SecurityScopedBookmarkEntry] = []
    
    private let storageKey = "securityScopedBookmarks"
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    
    private init() {
        load()
    }
    
    func addFolder(url: URL) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        do {
            let data = try canonical.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            let path = canonical.path
            if let index = entries.firstIndex(where: { $0.path == path }) {
                entries[index].data = data
            } else {
                entries.append(SecurityScopedBookmarkEntry(path: path, data: data))
            }
            save()
            return true
        } catch {
            return false
        }
    }
    
    func remove(_ entry: SecurityScopedBookmarkEntry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }
    
    func resolvedURL(for entry: SecurityScopedBookmarkEntry) -> URL? {
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: entry.data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale)
            if stale {
                refreshEntry(entry, resolvedURL: url)
            }
            return url
        } catch {
            return nil
        }
    }
    
    func startAccessingIfPossible(url: URL) -> Bool {
        let canonical = url.standardizedFileURL.resolvingSymlinksInPath()
        let targetPath = canonical.path
        for entry in entries {
            guard let scopedURL = resolvedURL(for: entry) else { continue }
            let basePath = scopedURL.standardizedFileURL.path
            if targetPath == basePath || targetPath.hasPrefix(basePath + "/") {
                return scopedURL.startAccessingSecurityScopedResource()
            }
        }
        return false
    }
    
    private func refreshEntry(_ entry: SecurityScopedBookmarkEntry, resolvedURL: URL) {
        do {
            let data = try resolvedURL.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[index].data = data
                entries[index].path = resolvedURL.standardizedFileURL.path
                save()
            }
        } catch {
            // Ignore refresh failures; user can re-add entry.
        }
    }
    
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        if let decoded = try? decoder.decode([SecurityScopedBookmarkEntry].self, from: data) {
            entries = decoded
        }
    }
    
    private func save() {
        if let data = try? encoder.encode(entries) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
