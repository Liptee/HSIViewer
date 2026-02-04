import Foundation

struct LibrarySpectrumEntry: Identifiable, Equatable {
    let libraryID: String
    var displayName: String
    var spectrumSamples: [CachedSpectrumSample]
    var roiSamples: [CachedROISample]
    
    var id: String { libraryID }
    
    var isEmpty: Bool {
        spectrumSamples.isEmpty && roiSamples.isEmpty
    }
    
    var totalSamples: Int {
        spectrumSamples.count + roiSamples.count
    }
}

struct CachedSpectrumSample: Identifiable, Equatable {
    let id: UUID
    let sourceLibraryID: String
    let pixelX: Int
    let pixelY: Int
    let values: [Double]
    let wavelengths: [Double]?
    let colorIndex: Int
    var displayName: String?
    
    var effectiveName: String {
        displayName ?? "(\(pixelX), \(pixelY))"
    }
}

struct CachedROISample: Identifiable, Equatable {
    let id: UUID
    let sourceLibraryID: String
    let minX: Int
    let minY: Int
    let width: Int
    let height: Int
    let values: [Double]
    let wavelengths: [Double]?
    let colorIndex: Int
    var displayName: String?
    
    var effectiveName: String {
        displayName ?? "ROI (\(minX), \(minY))"
    }
}

class LibrarySpectrumCache: ObservableObject {
    @Published var entries: [String: LibrarySpectrumEntry] = [:]
    @Published var visibleEntries: Set<String> = []
    
    func updateEntry(libraryID: String, displayName: String, spectrumSamples: [SpectrumSampleDescriptor], roiSamples: [SpectrumROISampleDescriptor]) {
        let cachedSpectrumSamples = spectrumSamples.map { descriptor in
            CachedSpectrumSample(
                id: descriptor.id,
                sourceLibraryID: libraryID,
                pixelX: descriptor.pixelX,
                pixelY: descriptor.pixelY,
                values: descriptor.values,
                wavelengths: descriptor.wavelengths,
                colorIndex: descriptor.colorIndex,
                displayName: descriptor.displayName
            )
        }
        
        let cachedROISamples = roiSamples.map { descriptor in
            CachedROISample(
                id: descriptor.id,
                sourceLibraryID: libraryID,
                minX: descriptor.minX,
                minY: descriptor.minY,
                width: descriptor.width,
                height: descriptor.height,
                values: descriptor.values,
                wavelengths: descriptor.wavelengths,
                colorIndex: descriptor.colorIndex,
                displayName: descriptor.displayName
            )
        }
        
        let entry = LibrarySpectrumEntry(
            libraryID: libraryID,
            displayName: displayName,
            spectrumSamples: cachedSpectrumSamples,
            roiSamples: cachedROISamples
        )
        
        entries[libraryID] = entry
        
        if !entry.isEmpty && !visibleEntries.contains(libraryID) {
        }
    }
    
    func removeEntry(libraryID: String) {
        entries.removeValue(forKey: libraryID)
        visibleEntries.remove(libraryID)
    }

    func renameEntry(libraryID: String, displayName: String) {
        guard var entry = entries[libraryID] else { return }
        entry.displayName = displayName
        entries[libraryID] = entry
    }
    
    func toggleVisibility(libraryID: String) {
        if visibleEntries.contains(libraryID) {
            visibleEntries.remove(libraryID)
        } else {
            visibleEntries.insert(libraryID)
        }
    }
    
    func setVisibility(libraryID: String, visible: Bool) {
        if visible {
            visibleEntries.insert(libraryID)
        } else {
            visibleEntries.remove(libraryID)
        }
    }
    
    func showAll() {
        visibleEntries = Set(entries.keys.filter { !entries[$0]!.isEmpty })
    }
    
    func hideAll() {
        visibleEntries.removeAll()
    }
    
    func visibleSpectrumSamples() -> [CachedSpectrumSample] {
        visibleEntries.flatMap { entries[$0]?.spectrumSamples ?? [] }
    }
    
    func visibleROISamples() -> [CachedROISample] {
        visibleEntries.flatMap { entries[$0]?.roiSamples ?? [] }
    }
    
    var nonEmptyEntries: [LibrarySpectrumEntry] {
        entries.values.filter { !$0.isEmpty }.sorted { $0.displayName < $1.displayName }
    }
}
