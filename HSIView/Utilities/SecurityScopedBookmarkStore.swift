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

final class AppWorkingDirectory {
    static let shared = AppWorkingDirectory()

    private let fileManager = FileManager.default
    private let workingFolderName = "HSIView"
    private let tempFolderName = "tmp"
    private let storedPathKey = "hsiviewWorkingDirectoryPath"
    private let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private init() {}

    func derivedCubeURL(baseName: String, allowPrompt: Bool) -> URL? {
        guard let tempFolder = temporaryDirectoryURL(allowPrompt: allowPrompt, createIfNeeded: true) else {
            return nil
        }

        let safeBase = sanitizeFileName(baseName)
        let timestamp = timestampFormatter.string(from: Date())
        let baseFilename = "\(safeBase)_derived_\(timestamp)"

        var candidate = tempFolder
            .appendingPathComponent(baseFilename)
            .appendingPathExtension("npy")

        var counter = 1
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = tempFolder
                .appendingPathComponent("\(baseFilename)_\(counter)")
                .appendingPathExtension("npy")
            counter += 1
        }

        return candidate
    }

    func temporaryDirectoryURL(allowPrompt: Bool, createIfNeeded: Bool) -> URL? {
        guard let workingDir = workingDirectoryURL(allowPrompt: allowPrompt, createIfNeeded: createIfNeeded) else {
            return nil
        }

        let tempDir = workingDir.appendingPathComponent(tempFolderName, isDirectory: true)
        if createIfNeeded {
            if !ensureDirectoryExists(at: tempDir) {
                return nil
            }
        } else if !fileManager.fileExists(atPath: tempDir.path) {
            return nil
        }

        return tempDir
    }

    func clearTemporaryDirectory() {
        guard let tempDir = temporaryDirectoryURL(allowPrompt: false, createIfNeeded: false) else { return }
        guard let items = try? fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else { return }

        for item in items {
            try? fileManager.removeItem(at: item)
        }
    }

    func isTemporaryURL(_ url: URL) -> Bool {
        guard let tempDir = temporaryDirectoryURL(allowPrompt: false, createIfNeeded: false) else { return false }
        let tempPath = tempDir.standardizedFileURL.path
        let targetPath = url.standardizedFileURL.path
        return targetPath == tempPath || targetPath.hasPrefix(tempPath + "/")
    }

    private func workingDirectoryURL(allowPrompt: Bool, createIfNeeded: Bool) -> URL? {
        if let stored = storedWorkingDirectoryURL() {
            _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: stored)
            if ensureDirectoryExists(at: stored, createIfNeeded: createIfNeeded) {
                return stored
            } else {
                clearStoredWorkingDirectory()
            }
        }

        if let defaultURL = defaultWorkingDirectoryURL() {
            if createIfNeeded {
                if ensureDirectoryExists(at: defaultURL, createIfNeeded: true) {
                    storeWorkingDirectory(defaultURL)
                    return defaultURL
                }
            } else if fileManager.fileExists(atPath: defaultURL.path) {
                return defaultURL
            }
        }

        guard allowPrompt else { return nil }
        guard let selectedBase = requestWorkingDirectoryFromUser() else { return nil }

        let workingURL = selectedBase.appendingPathComponent(workingFolderName, isDirectory: true)
        _ = selectedBase.startAccessingSecurityScopedResource()
        if ensureDirectoryExists(at: workingURL, createIfNeeded: true) {
            _ = SecurityScopedBookmarkStore.shared.addFolder(url: workingURL)
            _ = SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: workingURL)
            storeWorkingDirectory(workingURL)
            return workingURL
        }

        return nil
    }

    private func defaultWorkingDirectoryURL() -> URL? {
        guard let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return base.appendingPathComponent(workingFolderName, isDirectory: true)
    }

    private func storedWorkingDirectoryURL() -> URL? {
        guard let storedPath = UserDefaults.standard.string(forKey: storedPathKey) else { return nil }
        return URL(fileURLWithPath: storedPath)
    }

    private func storeWorkingDirectory(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: storedPathKey)
    }

    private func clearStoredWorkingDirectory() {
        UserDefaults.standard.removeObject(forKey: storedPathKey)
    }

    private func ensureDirectoryExists(at url: URL, createIfNeeded: Bool = true) -> Bool {
        if fileManager.fileExists(atPath: url.path) {
            return fileManager.isWritableFile(atPath: url.path) || SecurityScopedBookmarkStore.shared.startAccessingIfPossible(url: url)
        }

        guard createIfNeeded else { return false }
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            return true
        } catch {
            return false
        }
    }

    private func sanitizeFileName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:\\?%*|\"<>")
        let parts = name.components(separatedBy: invalidCharacters)
        let cleaned = parts.joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "hypercube" : cleaned
    }

    private func requestWorkingDirectoryFromUser() -> URL? {
        var selectedURL: URL?

        let promptBlock = {
            let panel = NSOpenPanel()
            panel.message = L("Выберите папку для служебных файлов HSIView. Внутри будет создана папка HSIView.")
            panel.prompt = L("Выбрать")
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = true
            panel.canChooseFiles = false

            if panel.runModal() == .OK {
                selectedURL = panel.url
            }
        }

        if Thread.isMainThread {
            promptBlock()
        } else {
            DispatchQueue.main.sync {
                promptBlock()
            }
        }

        return selectedURL
    }
}
