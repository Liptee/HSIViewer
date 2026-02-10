import Foundation

struct GridLibraryAxisItem: Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct GridLibraryCellPosition: Hashable {
    let rowID: UUID
    let columnID: UUID
}
