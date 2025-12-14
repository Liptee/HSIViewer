import Foundation

struct MatSelectionRequest: Identifiable {
    let id = UUID()
    let fileURL: URL
    let options: [MatVariableOption]
}
