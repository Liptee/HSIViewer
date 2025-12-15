import Foundation

struct CubeLibraryEntry: Identifiable, Equatable {
    let url: URL
    
    var id: String { canonicalPath }
    
    var fileName: String {
        url.lastPathComponent
    }
    
    var canonicalPath: String {
        url.standardizedFileURL.path
    }
}
