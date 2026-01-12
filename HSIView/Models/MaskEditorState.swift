import Foundation
import AppKit

final class MaskEditorState: ObservableObject {
    @Published var layers: [any MaskLayerProtocol] = []
    @Published var activeLayerID: UUID?
    @Published var currentTool: MaskDrawingTool = .brush
    @Published var brushSize: Int = 10
    @Published var isShiftPressed: Bool = false
    
    private var undoStacks: [UUID: [[UInt8]]] = [:]
    private let maxUndoCount = 20
    
    var maskLayers: [MaskLayer] { layers.compactMap { $0 as? MaskLayer } }
    var referenceLayers: [ReferenceLayer] { layers.compactMap { $0 as? ReferenceLayer } }
    var activeLayer: MaskLayer? {
        guard let id = activeLayerID else { return nil }
        return maskLayers.first { $0.id == id }
    }
    
    var drawableLayerIDs: Set<UUID> {
        Set(maskLayers.filter { $0.activeForDrawing && !$0.locked }.map { $0.id })
    }
    
    func initialize(width: Int, height: Int, rgbImage: NSImage? = nil) {
        layers.removeAll()
        undoStacks.removeAll()
        
        let refLayer = ReferenceLayer(
            id: UUID(),
            name: "Референс",
            width: width,
            height: height,
            visible: true,
            rgbImage: rgbImage
        )
        layers.append(refLayer)
        
        let maskLayer = MaskLayer(
            id: UUID(),
            name: "Класс 1",
            width: width,
            height: height,
            classValue: 1,
            color: MaskClassColor.palette[0]
        )
        layers.append(maskLayer)
        activeLayerID = maskLayer.id
        undoStacks[maskLayer.id] = []
    }
    
    func addMaskLayer(name: String? = nil) {
        guard let firstMask = maskLayers.first else { return }
        let nextClassValue = Int(maskLayers.map { $0.classValue }.max() ?? 0) + 1
        let colorIndex = (nextClassValue - 1) % MaskClassColor.palette.count
        let layer = MaskLayer(
            id: UUID(),
            name: name ?? "Класс \(nextClassValue)",
            width: firstMask.width,
            height: firstMask.height,
            classValue: UInt8(nextClassValue),
            color: MaskClassColor.palette[colorIndex]
        )
        layers.append(layer)
        undoStacks[layer.id] = []
        activeLayerID = layer.id
    }
    
    func removeMaskLayer(id: UUID) {
        guard maskLayers.count > 1 else { return }
        layers.removeAll { $0.id == id }
        undoStacks.removeValue(forKey: id)
        if activeLayerID == id {
            activeLayerID = maskLayers.first?.id
        }
    }
    
    func moveLayer(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < layers.count,
              destination >= 0, destination < layers.count else { return }
        let layer = layers.remove(at: source)
        layers.insert(layer, at: destination)
    }
    
    func toggleLayerVisibility(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].visible.toggle()
    }
    
    func toggleLayerLocked(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              var mask = layers[index] as? MaskLayer else { return }
        mask.locked.toggle()
        layers[index] = mask
    }
    
    func toggleLayerActiveForDrawing(id: UUID) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              var mask = layers[index] as? MaskLayer else { return }
        mask.activeForDrawing.toggle()
        layers[index] = mask
    }
    
    func renameLayer(id: UUID, to name: String) {
        guard let index = layers.firstIndex(where: { $0.id == id }) else { return }
        layers[index].name = name
    }
    
    func setLayerColor(id: UUID, color: NSColor) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              var mask = layers[index] as? MaskLayer else { return }
        mask.color = color
        layers[index] = mask
    }
    
    func setLayerOpacity(id: UUID, opacity: Double) {
        guard let index = layers.firstIndex(where: { $0.id == id }),
              var mask = layers[index] as? MaskLayer else { return }
        mask.opacity = max(0, min(1, opacity))
        layers[index] = mask
    }
    
    func setActiveLayer(id: UUID) {
        guard maskLayers.contains(where: { $0.id == id }) else { return }
        activeLayerID = id
    }
    
    func applyBrush(at point: CGPoint, in imageSize: CGSize) {
        let drawableIDs = drawableLayerIDs
        guard !drawableIDs.isEmpty else { return }
        
        for id in drawableIDs {
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  var mask = layers[index] as? MaskLayer else { continue }
            
            pushUndo(for: id, data: mask.data)
            mask.applyBrush(at: point, size: brushSize, in: imageSize)
            layers[index] = mask
        }
    }
    
    func applyEraser(at point: CGPoint, in imageSize: CGSize) {
        let drawableIDs = drawableLayerIDs
        guard !drawableIDs.isEmpty else { return }
        
        for id in drawableIDs {
            guard let index = layers.firstIndex(where: { $0.id == id }),
                  var mask = layers[index] as? MaskLayer else { continue }
            
            pushUndo(for: id, data: mask.data)
            mask.applyEraser(at: point, size: brushSize, in: imageSize)
            layers[index] = mask
        }
    }
    
    func applyFill(at point: CGPoint, in imageSize: CGSize) {
        guard let activeID = activeLayerID,
              drawableLayerIDs.contains(activeID),
              let index = layers.firstIndex(where: { $0.id == activeID }),
              var mask = layers[index] as? MaskLayer else { return }
        
        pushUndo(for: activeID, data: mask.data)
        mask.applyFill(at: point, in: imageSize)
        layers[index] = mask
    }
    
    func undo(for layerID: UUID) {
        guard var stack = undoStacks[layerID], !stack.isEmpty else { return }
        let previous = stack.removeLast()
        undoStacks[layerID] = stack
        
        guard let index = layers.firstIndex(where: { $0.id == layerID }),
              var mask = layers[index] as? MaskLayer else { return }
        mask.data = previous
        layers[index] = mask
    }
    
    func canUndo(for layerID: UUID) -> Bool {
        guard let stack = undoStacks[layerID] else { return false }
        return !stack.isEmpty
    }
    
    private func pushUndo(for layerID: UUID, data: [UInt8]) {
        var stack = undoStacks[layerID] ?? []
        stack.append(data)
        if stack.count > maxUndoCount {
            stack.removeFirst()
        }
        undoStacks[layerID] = stack
    }
    
    func syncWithImageSize(width: Int, height: Int, rotationTurns: Int = 0) {
        for i in layers.indices {
            if var mask = layers[i] as? MaskLayer {
                mask.resizeNearestNeighbor(to: width, height: height)
                if rotationTurns != 0 {
                    mask.rotate(turns: rotationTurns)
                }
                layers[i] = mask
            } else if var ref = layers[i] as? ReferenceLayer {
                ref.width = width
                ref.height = height
                layers[i] = ref
            }
        }
    }
    
    func computeMergedMask() -> [UInt8] {
        guard let first = maskLayers.first else { return [] }
        let totalPixels = first.width * first.height
        var result = [UInt8](repeating: 0, count: totalPixels)
        
        let visibleMasks = maskLayers.filter { $0.visible }.reversed()
        for mask in visibleMasks {
            for i in 0..<min(totalPixels, mask.data.count) {
                if mask.data[i] != 0 && result[i] == 0 {
                    result[i] = mask.classValue
                }
            }
        }
        
        return result
    }
    
    func classMetadata() -> [MaskClassMetadata] {
        maskLayers.map {
            MaskClassMetadata(id: Int($0.classValue), name: $0.name, color: $0.color)
        }
    }
}

protocol MaskLayerProtocol: Identifiable {
    var id: UUID { get }
    var name: String { get set }
    var visible: Bool { get set }
    var width: Int { get }
    var height: Int { get }
}

struct ReferenceLayer: MaskLayerProtocol {
    let id: UUID
    var name: String
    var width: Int
    var height: Int
    var visible: Bool
    var rgbImage: NSImage?
    var displayMode: ReferenceDisplayMode = .rgbSynthesis
}

enum ReferenceDisplayMode: String, CaseIterable, Identifiable {
    case rgbSynthesis = "RGB синтез"
    case singleChannel = "Канал"
    
    var id: String { rawValue }
}

struct MaskLayer: MaskLayerProtocol {
    let id: UUID
    var name: String
    var width: Int
    var height: Int
    var classValue: UInt8
    var color: NSColor
    var opacity: Double = 0.5
    var visible: Bool = true
    var locked: Bool = false
    var activeForDrawing: Bool = true
    var data: [UInt8]
    
    init(id: UUID, name: String, width: Int, height: Int, classValue: UInt8, color: NSColor, opacity: Double = 0.5) {
        self.id = id
        self.name = name
        self.width = width
        self.height = height
        self.classValue = classValue
        self.color = color
        self.opacity = opacity
        self.data = [UInt8](repeating: 0, count: width * height)
    }
    
    mutating func applyBrush(at point: CGPoint, size: Int, in imageSize: CGSize) {
        let scaleX = CGFloat(width) / imageSize.width
        let scaleY = CGFloat(height) / imageSize.height
        let cx = Int(point.x * scaleX)
        let cy = Int(point.y * scaleY)
        let radius = max(1, size / 2)
        
        for dy in -radius...radius {
            for dx in -radius...radius {
                if dx * dx + dy * dy <= radius * radius {
                    let px = cx + dx
                    let py = cy + dy
                    if px >= 0, px < width, py >= 0, py < height {
                        let idx = py * width + px
                        data[idx] = classValue
                    }
                }
            }
        }
    }
    
    mutating func applyEraser(at point: CGPoint, size: Int, in imageSize: CGSize) {
        let scaleX = CGFloat(width) / imageSize.width
        let scaleY = CGFloat(height) / imageSize.height
        let cx = Int(point.x * scaleX)
        let cy = Int(point.y * scaleY)
        let radius = max(1, size / 2)
        
        for dy in -radius...radius {
            for dx in -radius...radius {
                if dx * dx + dy * dy <= radius * radius {
                    let px = cx + dx
                    let py = cy + dy
                    if px >= 0, px < width, py >= 0, py < height {
                        let idx = py * width + px
                        data[idx] = 0
                    }
                }
            }
        }
    }
    
    mutating func applyFill(at point: CGPoint, in imageSize: CGSize) {
        let scaleX = CGFloat(width) / imageSize.width
        let scaleY = CGFloat(height) / imageSize.height
        let startX = Int(point.x * scaleX)
        let startY = Int(point.y * scaleY)
        
        guard startX >= 0, startX < width, startY >= 0, startY < height else { return }
        
        let startIdx = startY * width + startX
        let targetValue = data[startIdx]
        if targetValue == classValue { return }
        
        var visited = [Bool](repeating: false, count: width * height)
        var queue = [(startX, startY)]
        
        while !queue.isEmpty {
            let (x, y) = queue.removeFirst()
            let idx = y * width + x
            
            if visited[idx] { continue }
            if data[idx] != targetValue { continue }
            
            visited[idx] = true
            data[idx] = classValue
            
            if x > 0 { queue.append((x - 1, y)) }
            if x < width - 1 { queue.append((x + 1, y)) }
            if y > 0 { queue.append((x, y - 1)) }
            if y < height - 1 { queue.append((x, y + 1)) }
        }
    }
    
    mutating func resizeNearestNeighbor(to newWidth: Int, height newHeight: Int) {
        guard newWidth > 0, newHeight > 0 else { return }
        guard newWidth != width || newHeight != height else { return }
        
        var newData = [UInt8](repeating: 0, count: newWidth * newHeight)
        
        for y in 0..<newHeight {
            for x in 0..<newWidth {
                let srcX = Int((CGFloat(x) / CGFloat(newWidth)) * CGFloat(width))
                let srcY = Int((CGFloat(y) / CGFloat(newHeight)) * CGFloat(height))
                let srcIdx = min(srcY, height - 1) * width + min(srcX, width - 1)
                let dstIdx = y * newWidth + x
                newData[dstIdx] = data[srcIdx]
            }
        }
        
        self.width = newWidth
        self.height = newHeight
        self.data = newData
    }
    
    mutating func rotate(turns: Int) {
        let normalized = ((turns % 4) + 4) % 4
        guard normalized != 0 else { return }
        
        for _ in 0..<normalized {
            rotateOnce()
        }
    }
    
    private mutating func rotateOnce() {
        let newWidth = height
        let newHeight = width
        var newData = [UInt8](repeating: 0, count: newWidth * newHeight)
        
        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = y * width + x
                let newX = height - 1 - y
                let newY = x
                let dstIdx = newY * newWidth + newX
                newData[dstIdx] = data[srcIdx]
            }
        }
        
        self.width = newWidth
        self.height = newHeight
        self.data = newData
    }
}

enum MaskDrawingTool: String, CaseIterable, Identifiable {
    case brush = "Кисть"
    case eraser = "Ластик"
    case fill = "Заливка"
    
    var id: String { rawValue }
    
    var iconName: String {
        switch self {
        case .brush: return "paintbrush.pointed"
        case .eraser: return "eraser"
        case .fill: return "drop.fill"
        }
    }
}

enum MaskClassColor {
    static let palette: [NSColor] = [
        NSColor(red: 1.0, green: 0.2, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.2, green: 0.8, blue: 0.2, alpha: 1.0),
        NSColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1.0),
        NSColor(red: 1.0, green: 0.8, blue: 0.0, alpha: 1.0),
        NSColor(red: 0.8, green: 0.2, blue: 0.8, alpha: 1.0),
        NSColor(red: 0.0, green: 0.8, blue: 0.8, alpha: 1.0),
        NSColor(red: 1.0, green: 0.5, blue: 0.0, alpha: 1.0),
        NSColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1.0),
    ]
}

struct MaskClassMetadata: Codable {
    let id: Int
    let name: String
    let colorR: Double
    let colorG: Double
    let colorB: Double
    
    init(id: Int, name: String, color: NSColor) {
        self.id = id
        self.name = name
        let rgb = color.usingColorSpace(.sRGB) ?? color
        self.colorR = Double(rgb.redComponent)
        self.colorG = Double(rgb.greenComponent)
        self.colorB = Double(rgb.blueComponent)
    }
}

