import SwiftUI
import AppKit

struct MaskEditorView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var maskState: MaskEditorState
    
    @State private var isDrawing: Bool = false
    @State private var lastDrawPoint: CGPoint?
    @State private var currentGeoSize: CGSize = .zero
    @State private var tempZoomScale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    
    var body: some View {
        HStack(spacing: 0) {
            MaskLayersPanelView(maskState: maskState)
                .frame(width: 240)
            
            Divider()
            
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
                .gesture(drawingGesture(geoSize: geo.size))
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.crosshair.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onAppear {
                    currentGeoSize = geo.size
                    setupShiftKeyMonitor()
                }
                .onDisappear {
                    removeShiftKeyMonitor()
                }
                .onChange(of: geo.size) { newSize in
                    currentGeoSize = newSize
                }
            }
            
            Divider()
            
            MaskToolsPanelView(maskState: maskState)
                .frame(width: 200)
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
    
    private func drawingGesture(geoSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !isDrawing {
                    isDrawing = true
                    lastDrawPoint = nil
                }
                
                handleDrawing(at: value.location, geoSize: geoSize)
            }
            .onEnded { _ in
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
        }
        .frame(width: fittedSize.width, height: fittedSize.height)
        .background(Color.black.opacity(0.02))
    }
}

struct MaskOverlayView: View {
    @ObservedObject var maskState: MaskEditorState
    let displaySize: CGSize
    
    var body: some View {
        Canvas { context, size in
            let visibleMasks = maskState.maskLayers.filter { $0.visible }
            
            for mask in visibleMasks {
                let opacity = maskState.isShiftPressed
                    ? (mask.id == maskState.activeLayerID ? 0.7 : 0.0)
                    : mask.opacity
                
                guard opacity > 0 else { continue }
                
                drawMask(mask, in: context, size: size, opacity: opacity)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height)
    }
    
    private func drawMask(_ mask: MaskLayer, in context: GraphicsContext, size: CGSize, opacity: Double) {
        guard mask.width > 0, mask.height > 0 else { return }
        
        let scaleX = size.width / CGFloat(mask.width)
        let scaleY = size.height / CGFloat(mask.height)
        
        let color = Color(mask.color).opacity(opacity)
        
        for y in 0..<mask.height {
            for x in 0..<mask.width {
                let idx = y * mask.width + x
                if mask.data[idx] != 0 {
                    let rect = CGRect(
                        x: CGFloat(x) * scaleX,
                        y: CGFloat(y) * scaleY,
                        width: scaleX + 0.5,
                        height: scaleY + 0.5
                    )
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
    }
}

struct MaskLayersPanelView: View {
    @ObservedObject var maskState: MaskEditorState
    @State private var editingLayerID: UUID?
    @State private var editingName: String = ""
    @State private var draggedLayerID: UUID?
    
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
    
    @State private var showOpacityPopover: Bool = false
    
    private var maskLayer: MaskLayer? { layer as? MaskLayer }
    private var isReference: Bool { layer is ReferenceLayer }
    
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
                    ColorPicker("", selection: Binding(
                        get: { Color(mask.color) },
                        set: { onColorChange(NSColor($0)) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 18, height: 18)
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
                } else {
                    Text(layer.name)
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .onTapGesture(count: 2, perform: onStartEditing)
                }
                
                Spacer()
                
                if let mask = maskLayer {
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
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
                        Button("\(size)") {
                            maskState.brushSize = size
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
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
    }
}
