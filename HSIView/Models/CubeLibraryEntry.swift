import Foundation

struct CubeLibraryEntry: Identifiable, Equatable {
    let url: URL
    var customName: String? = nil
    
    var id: String { canonicalPath }
    
    var fileName: String {
        url.lastPathComponent
    }
    
    var canonicalPath: String {
        url.standardizedFileURL.path
    }

    var displayName: String {
        let trimmed = customName?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed! : fileName
    }
    
    var exportBaseName: String {
        let fallback = url.deletingPathExtension().lastPathComponent
        let trimmedDisplay = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmedDisplay.isEmpty ? fallback : trimmedDisplay
        let ext = url.pathExtension
        if !ext.isEmpty {
            let lowerExt = ".\(ext.lowercased())"
            if candidate.lowercased().hasSuffix(lowerExt) {
                candidate = String(candidate.dropLast(lowerExt.count))
            }
        }
        candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.isEmpty {
            return fallback.isEmpty ? "hypercube" : fallback
        }
        return candidate
    }
}
