import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MaskEditorView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var maskState: MaskEditorState
    
    @State private var isDrawing: Bool = false
    @State private var lastDrawPoint: CGPoint?
    @State private var currentGeoSize: CGSize = .zero
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var roiDragStartPixel: PixelCoordinate?
    @State private var roiPreviewRect: SpectrumROIRect?
    @State private var rulerHoverPixel: PixelCoordinate?
    @FocusState private var isImageFocused: Bool
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let cube = state.cube {
                    maskCanvas(cube: cube, geoSize: geo.size)
                        .scaleEffect(state.zoomScale * tempZoomScale)
                        .offset(
                            x: state.imageOffset.width + dragOffset.width,
                            y: state.imageOffset.height + dragOffset.height
                        )
                } else {
                    Text(AppLocalizer.localized("Нет данных"))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .gesture(magnificationGesture)
            .gesture(interactionGesture(geoSize: geo.size))
            .background(
                ContentView.TrackpadScrollCatcher { delta in
                    guard state.cube != nil else { return }
                    state.moveImage(by: delta)
                }
                .allowsHitTesting(false)
            )
            .onTapGesture { location in
                if state.activeAnalysisTool == .spectrumGraph {
                    handleSpectrumClick(at: location, geoSize: geo.size)
                } else if state.activeAnalysisTool == .ruler,
                          state.rulerMode == .measure {
                    handleRulerClick(at: location, geoSize: geo.size)
                }
            }
            .onHover { isHovering in
                if (state.activeAnalysisTool == .none
                    || state.activeAnalysisTool == .spectrumGraph
                    || state.activeAnalysisTool == .spectrumGraphROI
                    || state.activeAnalysisTool == .ruler),
                   state.cube != nil {
                    if isHovering {
                        NSCursor.crosshair.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let location):
                    guard let pixel = pixelCoordinate(for: location, geoSize: geo.size) else {
                        rulerHoverPixel = nil
                        state.clearCursorGeoCoordinate()
                        return
                    }
                    if state.activeAnalysisTool == .ruler,
                       state.rulerMode == .measure {
                        rulerHoverPixel = pixel
                    } else {
                        rulerHoverPixel = nil
                    }
                    if state.cube?.geoReference != nil {
                        state.updateCursorGeoCoordinate(pixelX: pixel.x, pixelY: pixel.y)
                    } else {
                        state.clearCursorGeoCoordinate()
                    }
                case .ended:
                    rulerHoverPixel = nil
                    state.clearCursorGeoCoordinate()
                }
            }
            .focusable()
            .focusEffectDisabled()
            .focused($isImageFocused)
            .onAppear {
                currentGeoSize = geo.size
                setupShiftKeyMonitor()
                isImageFocused = true
            }
            .onDisappear {
                removeShiftKeyMonitor()
            }
            .onKeyPress(.delete) {
                guard state.activeAnalysisTool == .ruler,
                      state.rulerMode == .edit else { return .ignored }
                state.deleteSelectedRulerPoint()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                guard state.activeAnalysisTool == .ruler,
                      state.rulerMode == .edit else { return .ignored }
                state.deleteSelectedRulerPoint()
                return .handled
            }
            .onDeleteCommand {
                guard state.activeAnalysisTool == .ruler,
                      state.rulerMode == .edit else { return }
                state.deleteSelectedRulerPoint()
            }
            .onChange(of: state.activeAnalysisTool) { _ in
                NSCursor.pop()
                roiPreviewRect = nil
                roiDragStartPixel = nil
                rulerHoverPixel = nil
            }
            .onChange(of: state.rulerMode) { mode in
                if mode != .measure {
                    rulerHoverPixel = nil
                }
            }
            .onChange(of: state.cubeURL) { _ in
                roiPreviewRect = nil
                roiDragStartPixel = nil
                rulerHoverPixel = nil
                state.clearCursorGeoCoordinate()
            }
            .onChange(of: geo.size) { newSize in
                currentGeoSize = newSize
            }
            .background(
                ContentView.RulerDeleteKeyCatcher(
                    isActive: Binding(
                        get: {
                            state.activeAnalysisTool == .ruler
                                && state.rulerMode == .edit
                                && state.selectedRulerPointID != nil
                        },
                        set: { _ in }
                    ),
                    onDelete: {
                        state.deleteSelectedRulerPoint()
                    }
                )
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            )
        }
    }
    
    private func setupShiftKeyMonitor() {
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            maskState.isShiftPressed = event.modifierFlags.contains(.shift)
            return event
        }
    }
    
    private func removeShiftKeyMonitor() {
        maskState.isShiftPressed = false
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                tempZoomScale = value
            }
            .onEnded { value in
                state.zoomScale *= value
                state.zoomScale = max(0.5, min(state.zoomScale, 10.0))
                tempZoomScale = 1.0
            }
    }
    
    private func interactionGesture(geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if state.activeAnalysisTool == .spectrumGraphROI {
                    handleROIDrag(value: value, geoSize: geoSize)
                    return
                }
                guard state.activeAnalysisTool == .none else { return }
                if !isDrawing {
                    isDrawing = true
                    lastDrawPoint = nil
                }
                
                handleDrawing(at: value.location, geoSize: geoSize)
            }
            .onEnded { value in
                if state.activeAnalysisTool == .spectrumGraphROI {
                    handleROIDragEnd(value: value, geoSize: geoSize)
                } else if state.activeAnalysisTool == .none, !isDrawing {
                    // Preserve single-click behavior for mask tools (brush/fill/eraser).
                    handleDrawing(at: value.location, geoSize: geoSize)
                }
                isDrawing = false
                lastDrawPoint = nil
            }
    }
    
    private func handleDrawing(at location: CGPoint, geoSize: CGSize) {
        guard let imagePoint = convertToImageCoordinates(point: location, geoSize: geoSize) else { return }
        
        let imageSize = currentImageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        
        switch maskState.currentTool {
        case .brush:
            if let last = lastDrawPoint {
                interpolateDrawing(from: last, to: imagePoint, size: imageSize) { pt in
                    maskState.applyBrush(at: pt, in: imageSize)
                }
            } else {
                maskState.applyBrush(at: imagePoint, in: imageSize)
            }
        case .eraser:
            if let last = lastDrawPoint {
                interpolateDrawing(from: last, to: imagePoint, size: imageSize) { pt in
                    maskState.applyEraser(at: pt, in: imageSize)
                }
            } else {
                maskState.applyEraser(at: imagePoint, in: imageSize)
            }
        case .fill:
            if lastDrawPoint == nil {
                maskState.applyFill(at: imagePoint, in: imageSize)
            }
        }
        
        lastDrawPoint = imagePoint
    }
    
    private func interpolateDrawing(from: CGPoint, to: CGPoint, size: CGSize, action: (CGPoint) -> Void) {
        let distance = hypot(to.x - from.x, to.y - from.y)
        let steps = max(1, Int(distance / 2))
        
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let x = from.x + (to.x - from.x) * t
            let y = from.y + (to.y - from.y) * t
            action(CGPoint(x: x, y: y))
        }
    }
    
    private var currentImageSize: CGSize {
        guard let first = maskState.maskLayers.first else { return .zero }
        return CGSize(width: first.width, height: first.height)
    }
    
    private func convertToImageCoordinates(point: CGPoint, geoSize: CGSize) -> CGPoint? {
        let imageSize = currentImageSize
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }
        
        let fittedSize = fittingSize(imageSize: imageSize, in: geoSize)
        let totalZoom = state.zoomScale * tempZoomScale
        let scaledImageSize = CGSize(
            width: fittedSize.width * totalZoom,
            height: fittedSize.height * totalZoom
        )
        
        let centerX = geoSize.width / 2
        let centerY = geoSize.height / 2
        
        let imageOriginX = centerX - scaledImageSize.width / 2 + state.imageOffset.width + dragOffset.width
        let imageOriginY = centerY - scaledImageSize.height / 2 + state.imageOffset.height + dragOffset.height
        
        let relativeX = point.x - imageOriginX
        let relativeY = point.y - imageOriginY
        
        guard relativeX >= 0, relativeX < scaledImageSize.width,
              relativeY >= 0, relativeY < scaledImageSize.height else {
            return nil
        }
        
        let normalizedX = relativeX / scaledImageSize.width * imageSize.width
        let normalizedY = relativeY / scaledImageSize.height * imageSize.height
        
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    private func pixelCoordinate(for location: CGPoint, geoSize: CGSize) -> PixelCoordinate? {
        guard let imagePoint = convertToImageCoordinates(point: location, geoSize: geoSize) else { return nil }
        let maxX = max(Int(currentImageSize.width) - 1, 0)
        let maxY = max(Int(currentImageSize.height) - 1, 0)
        let pixelX = max(0, min(Int(imagePoint.x), maxX))
        let pixelY = max(0, min(Int(imagePoint.y), maxY))
        return PixelCoordinate(x: pixelX, y: pixelY)
    }

    private func handleSpectrumClick(at location: CGPoint, geoSize: CGSize) {
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.extractSpectrum(at: pixel.x, pixelY: pixel.y)
    }

    private func handleRulerClick(at location: CGPoint, geoSize: CGSize) {
        guard let pixel = pixelCoordinate(for: location, geoSize: geoSize) else { return }
        state.addRulerPoint(pixelX: pixel.x, pixelY: pixel.y)
    }

    private func roiRect(from start: PixelCoordinate, to end: PixelCoordinate) -> SpectrumROIRect {
        let minX = min(start.x, end.x)
        let minY = min(start.y, end.y)
        let width = abs(end.x - start.x) + 1
        let height = abs(end.y - start.y) + 1
        return SpectrumROIRect(minX: minX, minY: minY, width: width, height: height)
    }

    private func handleROIDrag(value: DragGesture.Value, geoSize: CGSize) {
        guard let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize) else { return }
        guard let currentPixel = pixelCoordinate(for: value.location, geoSize: geoSize) else { return }
        roiDragStartPixel = startPixel
        roiPreviewRect = roiRect(from: startPixel, to: currentPixel)
    }

    private func handleROIDragEnd(value: DragGesture.Value, geoSize: CGSize) {
        defer {
            roiDragStartPixel = nil
            roiPreviewRect = nil
        }
        guard
            let startPixel = roiDragStartPixel ?? pixelCoordinate(for: value.startLocation, geoSize: geoSize),
            let endPixel = pixelCoordinate(for: value.location, geoSize: geoSize)
        else { return }
        state.extractROISpectrum(for: roiRect(from: startPixel, to: endPixel))
    }
    
    private func fittingSize(imageSize: CGSize, in containerSize: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return containerSize }
        let widthScale = containerSize.width / imageSize.width
        let heightScale = containerSize.height / imageSize.height
        let scale = min(widthScale, heightScale, 1.0)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
    
    @ViewBuilder
    private func maskCanvas(cube: HyperCube, geoSize: CGSize) -> some View {
        let imageSize = currentImageSize
        let fittedSize = fittingSize(imageSize: imageSize, in: geoSize)
        
        ZStack(alignment: .topLeading) {
            if let refLayer = maskState.referenceLayers.first,
               refLayer.visible,
               let rgbImage = refLayer.rgbImage {
                Image(nsImage: rgbImage)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fittedSize.width, height: fittedSize.height)
            }
            
            MaskOverlayView(
                maskState: maskState,
                displaySize: fittedSize
            )
            .allowsHitTesting(false)

            if state.activeAnalysisTool == .spectrumGraph {
                ContentView.SpectrumPointsOverlay(
                    samples: state.activeSpectrumSamples,
                    originalSize: imageSize,
                    displaySize: fittedSize
                )
            } else if state.activeAnalysisTool == .spectrumGraphROI {
                ContentView.SpectrumROIsOverlay(
                    samples: state.activeROISamples,
                    temporaryRect: roiPreviewRect,
                    originalSize: imageSize,
                    displaySize: fittedSize
                )
            } else if state.activeAnalysisTool == .ruler {
                ContentView.RulerOverlay(
                    points: state.rulerPoints,
                    hoverPixel: state.rulerMode == .measure ? rulerHoverPixel : nil,
                    mode: state.rulerMode,
                    selectedPointID: state.selectedRulerPointID,
                    geoReference: state.cube?.geoReference,
                    originalSize: imageSize,
                    displaySize: fittedSize
                ) { id, x, y in
                    state.updateRulerPoint(id: id, pixelX: x, pixelY: y)
                } onSelectPoint: { id in
                    state.selectRulerPoint(id: id)
                    isImageFocused = true
                }
            }
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .background(Color.black.opacity(0.02))
    }
}

struct MaskOverlayView: View {
    @ObservedObject var maskState: MaskEditorState
    let displaySize: CGSize
    @StateObject private var imageCache = MaskLayerImageCache()

    var body: some View {
        let masksToRender: [MaskLayer] = {
            if maskState.isShiftPressed, let activeID = maskState.activeLayerID {
                return maskState.maskLayers.filter { $0.visible && $0.id == activeID }
            }
            return maskState.maskLayers.filter { $0.visible }
        }()

        ZStack(alignment: .topLeading) {
            ForEach(masksToRender, id: \.id) { mask in
                let opacity = maskState.isShiftPressed ? 0.7 : mask.opacity
                if opacity > 0, let cgImage = imageCache.image(for: mask) {
                    Image(decorative: cgImage, scale: 1.0)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .opacity(opacity)
                }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }
}

private final class MaskLayerImageCache: ObservableObject {
    private struct CacheKey: Hashable {
        let layerID: UUID
        let renderVersion: UInt64
        let width: Int
        let height: Int
        let red: UInt8
        let green: UInt8
        let blue: UInt8
    }

    private var images: [CacheKey: CGImage] = [:]
    private var lruKeys: [CacheKey] = []
    private let maxEntries: Int = 48

    func image(for layer: MaskLayer) -> CGImage? {
        guard layer.width > 0, layer.height > 0 else { return nil }
        let key = cacheKey(for: layer)

        if let cached = images[key] {
            touch(key)
            return cached
        }

        guard let built = buildImage(for: layer, key: key) else { return nil }
        images[key] = built
        lruKeys.append(key)
        trimCacheIfNeeded()
        return built
    }

    private func cacheKey(for layer: MaskLayer) -> CacheKey {
        let rgb = layer.color.usingColorSpace(.sRGB) ?? layer.color
        return CacheKey(
            layerID: layer.id,
            renderVersion: layer.renderVersion,
            width: layer.width,
            height: layer.height,
            red: byte(from: rgb.redComponent),
            green: byte(from: rgb.greenComponent),
            blue: byte(from: rgb.blueComponent)
        )
    }

    private func buildImage(for layer: MaskLayer, key: CacheKey) -> CGImage? {
        let pixelCount = layer.width * layer.height
        guard pixelCount > 0, layer.data.count >= pixelCount else { return nil }

        var rgba = [UInt8](repeating: 0, count: pixelCount * 4)
        layer.data.withUnsafeBufferPointer { dataPtr in
            rgba.withUnsafeMutableBufferPointer { rgbaPtr in
                guard let dataBase = dataPtr.baseAddress,
                      let rgbaBase = rgbaPtr.baseAddress else {
                    return
                }

                for i in 0..<pixelCount where dataBase[i] != 0 {
                    let offset = i * 4
                    rgbaBase[offset] = key.red
                    rgbaBase[offset + 1] = key.green
                    rgbaBase[offset + 2] = key.blue
                    rgbaBase[offset + 3] = 255
                }
            }
        }

        let data = Data(rgba)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        return CGImage(
            width: layer.width,
            height: layer.height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: layer.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    private func touch(_ key: CacheKey) {
        guard let index = lruKeys.firstIndex(of: key) else { return }
        let moved = lruKeys.remove(at: index)
        lruKeys.append(moved)
    }

    private func trimCacheIfNeeded() {
        while lruKeys.count > maxEntries {
            let oldest = lruKeys.removeFirst()
            images.removeValue(forKey: oldest)
        }
    }

    private func byte(from component: CGFloat) -> UInt8 {
        UInt8(clamping: Int((component * 255.0).rounded()))
    }
}

struct MaskLayersPanelView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var maskState: MaskEditorState
    @State private var editingLayerID: UUID?
    @State private var editingName: String = ""
    @State private var draggedLayerID: UUID?
    @State private var isDropTargeted: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(AppLocalizer.localized("Слои"))
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: { maskState.addMaskLayer() }) {
                    Image(systemName: "plus")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help(AppLocalizer.localized("Добавить слой маски"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(maskState.layers.enumerated()), id: \.element.id) { index, layer in
                        LayerRowView(
                            layer: layer,
                            isActive: layer.id == maskState.activeLayerID,
                            isEditing: editingLayerID == layer.id,
                            editingName: $editingName,
                            onSelect: {
                                if let _ = layer as? MaskLayer {
                                    maskState.setActiveLayer(id: layer.id)
                                }
                            },
                            onToggleVisibility: {
                                maskState.toggleLayerVisibility(id: layer.id)
                            },
                            onToggleLock: {
                                maskState.toggleLayerLocked(id: layer.id)
                            },
                            onToggleDrawing: {
                                maskState.toggleLayerActiveForDrawing(id: layer.id)
                            },
                            onStartEditing: {
                                editingLayerID = layer.id
                                editingName = layer.name
                            },
                            onFinishEditing: {
                                if !editingName.isEmpty {
                                    maskState.renameLayer(id: layer.id, to: editingName)
                                }
                                editingLayerID = nil
                            },
                            onDelete: {
                                if layer is MaskLayer {
                                    maskState.removeMaskLayer(id: layer.id)
                                }
                            },
                            onColorChange: { newColor in
                                maskState.setLayerColor(id: layer.id, color: newColor)
                            },
                            onOpacityChange: { newOpacity in
                                maskState.setLayerOpacity(id: layer.id, opacity: newOpacity)
                            },
                            onMoveUp: index > 0 ? {
                                maskState.moveLayer(from: index, to: index - 1)
                            } : nil,
                            onMoveDown: index < maskState.layers.count - 1 ? {
                                maskState.moveLayer(from: index, to: index + 1)
                            } : nil
                        )
                    }
                }
                .padding(8)
            }
            
            Divider()
            
            Text(AppLocalizer.localized("↑↓ для изменения порядка слоёв"))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(8)
        }
        .background(.ultraThinMaterial)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isDropTargeted ? Color.accentColor : Color.clear, lineWidth: 2)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted, perform: handleMetadataDrop(providers:))
    }

    private func handleMetadataDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let url = object as? URL else { return }
                DispatchQueue.main.async {
                    state.importMaskMetadata(url: url)
                }
            }
            handled = true
        }
        return handled
    }
}

struct LayerRowView: View {
    let layer: any MaskLayerProtocol
    let isActive: Bool
    let isEditing: Bool
    @Binding var editingName: String
    let onSelect: () -> Void
    let onToggleVisibility: () -> Void
    let onToggleLock: () -> Void
    let onToggleDrawing: () -> Void
    let onStartEditing: () -> Void
    let onFinishEditing: () -> Void
    let onDelete: () -> Void
    let onColorChange: (NSColor) -> Void
    let onOpacityChange: (Double) -> Void
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    
    @State private var isHovered: Bool = false
    
    private var maskLayer: MaskLayer? { layer as? MaskLayer }
    private var isReference: Bool { layer is ReferenceLayer }
    private var hoverAccent: Color {
        if let mask = maskLayer {
            return Color(mask.color)
        }
        return Color.accentColor
    }
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Button(action: onToggleVisibility) {
                    Image(systemName: layer.visible ? "eye" : "eye.slash")
                        .font(.system(size: 10))
                        .foregroundColor(layer.visible ? .primary : .secondary)
                }
                .buttonStyle(.plain)
                .frame(width: 20)
                
                if let mask = maskLayer {
                    LayerColorSwatch(color: mask.color, onColorChange: onColorChange)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 18)
                }
                
                if isEditing {
                    TextField(AppLocalizer.localized("Имя"), text: $editingName, onCommit: onFinishEditing)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(layer.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .truncationMode(.tail)
                        .layoutPriority(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .onTapGesture(count: 2, perform: onStartEditing)
                }

                if let mask = maskLayer {
                    HStack(spacing: 8) {
                        Button(action: onToggleDrawing) {
                            Image(systemName: mask.activeForDrawing ? "pencil.circle.fill" : "pencil.circle")
                                .font(.system(size: 11))
                                .foregroundColor(mask.activeForDrawing ? .accentColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(mask.activeForDrawing ? "Отключить рисование" : "Включить рисование")

                        Button(action: onToggleLock) {
                            Image(systemName: mask.locked ? "lock.fill" : "lock.open")
                                .font(.system(size: 10))
                                .foregroundColor(mask.locked ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(mask.locked ? "Разблокировать" : "Заблокировать")

                        VStack(spacing: 2) {
                            Button(action: { onMoveUp?() }) {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(onMoveUp == nil)
                            .foregroundColor(onMoveUp != nil ? .primary : .secondary.opacity(0.3))

                            Button(action: { onMoveDown?() }) {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .buttonStyle(.plain)
                            .disabled(onMoveDown == nil)
                            .foregroundColor(onMoveDown != nil ? .primary : .secondary.opacity(0.3))
                        }
                        .frame(width: 16)
                    }
                    .frame(width: 62, alignment: .trailing)
                }
            }
            
            if let mask = maskLayer, isActive {
                HStack(spacing: 6) {
                    Text(AppLocalizer.localized("Прозрачность:"))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                    
                    Slider(value: Binding(
                        get: { mask.opacity },
                        set: { onOpacityChange($0) }
                    ), in: 0...1)
                    .frame(maxWidth: 120)
                    
                    Text("\(Int(mask.opacity * 100))%")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 32)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isActive ? Color.accentColor.opacity(0.4) : Color.clear, lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .shadow(color: hoverAccent.opacity(isHovered ? 0.28 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            if !isReference {
                Button("Переименовать", action: onStartEditing)
                if onMoveUp != nil {
                    Button("Переместить вверх", action: { onMoveUp?() })
                }
                if onMoveDown != nil {
                    Button("Переместить вниз", action: { onMoveDown?() })
                }
                Divider()
                Button("Удалить", role: .destructive, action: onDelete)
            }
        }
    }
}

private struct LayerColorSwatch: View {
    let color: NSColor
    let onColorChange: (NSColor) -> Void
    @State private var showPicker: Bool = false
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: { showPicker = true }) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(color))
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.08 : 1.0)
        .shadow(color: Color(color).opacity(isHovered ? 0.35 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: 3)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .popover(isPresented: $showPicker, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalizer.localized("Цвет"))
                    .font(.system(size: 11, weight: .semibold))
                ColorPicker(
                    "",
                    selection: Binding(
                        get: { Color(color) },
                        set: { onColorChange(NSColor($0)) }
                    ),
                    supportsOpacity: false
                )
                .labelsHidden()
            }
            .padding(10)
            .frame(width: 140)
        }
    }
}

struct MaskToolsPanelView: View {
    @ObservedObject var maskState: MaskEditorState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppLocalizer.localized("Инструменты"))
                    .font(.system(size: 12, weight: .semibold))
                
                HStack(spacing: 8) {
                    ForEach(MaskDrawingTool.allCases) { tool in
                        MaskToolButton(
                            tool: tool,
                            isSelected: maskState.currentTool == tool
                        ) {
                            maskState.currentTool = tool
                        }
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(LF("mask.brush_size_px", maskState.brushSize))
                    .font(.system(size: 11))
                
                Slider(value: Binding(
                    get: { Double(maskState.brushSize) },
                    set: { maskState.brushSize = Int($0) }
                ), in: 1...100, step: 1)
                
                HStack {
                    ForEach([1, 5, 10, 25, 50], id: \.self) { size in
                        MaskPresetSizeButton(
                            size: size,
                            isSelected: maskState.brushSize == size
                        ) {
                            maskState.brushSize = size
                        }
                    }
                }
            }
            
            Divider()
            
            if let activeID = maskState.activeLayerID {
                VStack(alignment: .leading, spacing: 8) {
                    Text(AppLocalizer.localized("Действия"))
                        .font(.system(size: 12, weight: .semibold))
                    
                    Button(action: { maskState.undo(for: activeID) }) {
                        Label("Отменить (⌘Z)", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(HoverLiftButtonStyle(accent: .accentColor))
                    .disabled(!maskState.canUndo(for: activeID))
                    .keyboardShortcut("z", modifiers: .command)
                }
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalizer.localized("Подсказки"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                Text(AppLocalizer.localized("• Shift — показать только активный слой"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(AppLocalizer.localized("• ⌘Z — отмена последнего действия"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(AppLocalizer.localized("• File → Экспорт для сохранения маски"))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(6)
        }
        .padding(12)
        .background(.ultraThinMaterial)
    }
}

private struct MaskToolButton: View {
    let tool: MaskDrawingTool
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: tool.iconName)
                    .font(.system(size: 16))
                Text(tool.localizedTitle)
                    .font(.system(size: 9))
            }
            .frame(width: 50, height: 44)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.05 : 1.0)
        .shadow(color: Color.accentColor.opacity(isHovered ? 0.35 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

private struct MaskPresetSizeButton: View {
    let size: Int
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered: Bool = false

    var body: some View {
        Button("\(size)", action: action)
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .scaleEffect(isHovered ? 1.08 : 1.0)
            .shadow(
                color: Color.accentColor.opacity(isHovered || isSelected ? 0.28 : 0.0),
                radius: isHovered || isSelected ? 6 : 0,
                x: 0,
                y: 3
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

private struct HoverLiftButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        HoverLiftButtonBody(
            label: configuration.label,
            accent: accent,
            isPressed: configuration.isPressed
        )
    }
}

private struct HoverLiftButtonBody<Label: View>: View {
    let label: Label
    let accent: Color
    let isPressed: Bool
    @State private var isHovered: Bool = false

    var body: some View {
        label
            .scaleEffect(isPressed ? 0.98 : (isHovered ? 1.03 : 1.0))
            .shadow(color: accent.opacity(isHovered ? 0.3 : 0.0), radius: isHovered ? 6 : 0, x: 0, y: 3)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}
