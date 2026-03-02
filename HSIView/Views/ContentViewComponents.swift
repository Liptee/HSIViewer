import SwiftUI
import AppKit

struct LibraryExportToastView: View {
    let state: LibraryExportProgressState
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(iconColor)
                Text(titleText)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            
            switch state.phase {
            case .running:
                ProgressView(value: state.progress)
                    .progressViewStyle(.linear)
                Text("\(state.completed) / \(state.total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            case .success, .failure:
                Text(AppLocalizer.localized(state.message ?? defaultMessage))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 6)
    }
    
    private var titleText: String {
        switch state.phase {
        case .running:
            return AppLocalizer.localized("Экспорт библиотеки")
        case .success:
            return AppLocalizer.localized("Готово")
        case .failure:
            return AppLocalizer.localized("Ошибка экспорта")
        }
    }
    
    private var iconName: String {
        switch state.phase {
        case .running:
            return "tray.full"
        case .success:
            return "checkmark.circle.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var iconColor: Color {
        switch state.phase {
        case .running:
            return .accentColor
        case .success:
            return .green
        case .failure:
            return .orange
        }
    }
    
    private var defaultMessage: String {
        switch state.phase {
        case .success:
            return AppLocalizer.localized("Все файлы успешно экспортированы")
        case .failure:
            return AppLocalizer.localized("При экспорте возникли ошибки")
        case .running:
            return ""
        }
    }
}

struct AlignmentProcessingToastView: View {
    let title: String
    let progress: Double
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)

            Text(message)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

struct PipelineProcessingToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
    }
}

struct SpectrumPointsOverlay: View {
    let samples: [SpectrumSample]
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                let position = position(for: sample)
                Circle()
                    .fill(sample.displayColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.9), lineWidth: 1)
                    )
                    .frame(width: 10, height: 10)
                    .position(x: position.x, y: position.y)
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func position(for sample: SpectrumSample) -> CGPoint {
        let width = max(originalSize.width - 1, 1)
        let height = max(originalSize.height - 1, 1)
        let xRatio = CGFloat(sample.pixelX) / width
        let yRatio = CGFloat(sample.pixelY) / height
        let x = xRatio * displaySize.width
        let y = yRatio * displaySize.height
        return CGPoint(x: x, y: y)
    }
}

struct SpectrumROIsOverlay: View {
    let samples: [SpectrumROISample]
    let temporaryRect: SpectrumROIRect?
    let temporaryColor: Color
    let originalSize: CGSize
    let displaySize: CGSize
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(samples) { sample in
                roiPath(for: sample.rect)
                    .stroke(sample.displayColor, lineWidth: 1.5)
                    .background(
                        roiPath(for: sample.rect)
                            .fill(sample.displayColor.opacity(0.08))
                    )
            }
            
            if let temp = temporaryRect {
                roiPath(for: temp)
                    .stroke(temporaryColor, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(
                        roiPath(for: temp)
                            .fill(temporaryColor.opacity(0.05))
                    )
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
    
    private func roiPath(for rect: SpectrumROIRect) -> Path {
        Path { path in
            path.addRoundedRect(in: frame(for: rect), cornerSize: CGSize(width: 4, height: 4))
        }
    }
    
    private func frame(for rect: SpectrumROIRect) -> CGRect {
        guard originalSize.width > 0, originalSize.height > 0 else { return .zero }
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        let x = CGFloat(rect.minX) * scaleX
        let y = CGFloat(rect.minY) * scaleY
        let width = CGFloat(rect.width) * scaleX
        let height = CGFloat(rect.height) * scaleY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct RulerOverlay: View {
    let points: [RulerPoint]
    let hoverPixel: PixelCoordinate?
    let mode: RulerMode
    let selectedPointID: UUID?
    let geoReference: MapGeoReference?
    let originalSize: CGSize
    let displaySize: CGSize
    let onMovePoint: (UUID, Int, Int) -> Void
    let onSelectPoint: (UUID?) -> Void

    @State private var dragStartPositions: [UUID: CGPoint] = [:]

    private struct Segment: Identifiable {
        let id: String
        let startX: Int
        let startY: Int
        let endX: Int
        let endY: Int
        let isTemporary: Bool
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(committedSegments) { segment in
                segmentView(segment)
            }

            if let temp = temporarySegment {
                segmentView(temp)
            }

            ForEach(points) { point in
                let position = displayPosition(x: point.pixelX, y: point.pixelY)
                let isSelected = selectedPointID == point.id
                Circle()
                    .fill(isSelected ? Color.orange : Color.accentColor)
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.95), lineWidth: isSelected ? 2.0 : 1.5)
                    )
                    .frame(width: isSelected ? 14 : 12, height: isSelected ? 14 : 12)
                    .position(x: position.x, y: position.y)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                if dragStartPositions[point.id] == nil {
                                    dragStartPositions[point.id] = displayPosition(x: point.pixelX, y: point.pixelY)
                                }
                                let start = dragStartPositions[point.id] ?? displayPosition(x: point.pixelX, y: point.pixelY)
                                let candidate = CGPoint(
                                    x: start.x + value.translation.width,
                                    y: start.y + value.translation.height
                                )
                                let pixel = pixelCoordinate(fromDisplay: candidate)
                                onMovePoint(point.id, pixel.x, pixel.y)
                            }
                            .onEnded { _ in
                                dragStartPositions.removeValue(forKey: point.id)
                            }
                    )
                    .onTapGesture {
                        guard mode == .edit else { return }
                        let newValue: UUID? = (selectedPointID == point.id) ? nil : point.id
                        onSelectPoint(newValue)
                    }
            }
        }
        .frame(width: displaySize.width, height: displaySize.height, alignment: .topLeading)
    }

    private var committedSegments: [Segment] {
        guard points.count > 1 else { return [] }
        return (0..<(points.count - 1)).map { index in
            Segment(
                id: "\(points[index].id.uuidString)-\(points[index + 1].id.uuidString)",
                startX: points[index].pixelX,
                startY: points[index].pixelY,
                endX: points[index + 1].pixelX,
                endY: points[index + 1].pixelY,
                isTemporary: false
            )
        }
    }

    private var temporarySegment: Segment? {
        guard mode == .measure else { return nil }
        guard let start = points.last, let hoverPixel else { return nil }
        guard start.pixelX != hoverPixel.x || start.pixelY != hoverPixel.y else { return nil }
        return Segment(
            id: "temp-\(start.id.uuidString)-\(hoverPixel.x)-\(hoverPixel.y)",
            startX: start.pixelX,
            startY: start.pixelY,
            endX: hoverPixel.x,
            endY: hoverPixel.y,
            isTemporary: true
        )
    }

    @ViewBuilder
    private func segmentView(_ segment: Segment) -> some View {
        let start = displayPosition(x: segment.startX, y: segment.startY)
        let end = displayPosition(x: segment.endX, y: segment.endY)
        let label = segmentLabel(segment)
        let midPoint = CGPoint(
            x: (start.x + end.x) / 2 + 8,
            y: (start.y + end.y) / 2 - 8
        )

        Path { path in
            path.move(to: start)
            path.addLine(to: end)
        }
        .stroke(
            segment.isTemporary ? Color.accentColor.opacity(0.8) : Color.accentColor,
            style: StrokeStyle(lineWidth: 2.0, lineCap: .round, dash: segment.isTemporary ? [5, 4] : [])
        )

        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .position(x: midPoint.x, y: midPoint.y)
    }

    private func segmentLabel(_ segment: Segment) -> String {
        let pixelDistance = hypot(
            Double(segment.endX - segment.startX),
            Double(segment.endY - segment.startY)
        )
        var lines: [String] = [
            LF("ruler.overlay.pixels", compactNumber(pixelDistance))
        ]

        if let geoDistance = geoDistanceLabel(segment) {
            lines.append(geoDistance)
        }

        return lines.joined(separator: "\n")
    }

    private func geoDistanceLabel(_ segment: Segment) -> String? {
        guard let geoReference else { return nil }

        let start = geoReference.mapCoordinate(forPixelX: segment.startX, pixelY: segment.startY)
        let end = geoReference.mapCoordinate(forPixelX: segment.endX, pixelY: segment.endY)

        if geoReference.isGeographic {
            let meters = haversineMeters(
                lat1: start.y,
                lon1: start.x,
                lat2: end.y,
                lon2: end.x
            )
            let value = meters >= 1000 ? meters / 1000 : meters
            let unit = meters >= 1000 ? L("ruler.unit.km") : L("ruler.unit.m")
            return LF("ruler.overlay.distance_unit", compactNumber(value), unit)
        }

        let distance = hypot(end.x - start.x, end.y - start.y)
        if let units = geoReference.units?.trimmingCharacters(in: .whitespacesAndNewlines), !units.isEmpty {
            return LF("ruler.overlay.distance_unit", compactNumber(distance), units)
        }
        return LF("ruler.overlay.distance", compactNumber(distance))
    }

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let phi1 = lat1 * .pi / 180.0
        let phi2 = lat2 * .pi / 180.0
        let dPhi = (lat2 - lat1) * .pi / 180.0
        let dLambda = (lon2 - lon1) * .pi / 180.0

        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(max(1e-12, 1 - a)))
        return earthRadius * c
    }

    private func compactNumber(_ value: Double) -> String {
        let number = String(format: "%.2f", value)
        return number.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func displayPosition(x: Int, y: Int) -> CGPoint {
        let width = max(originalSize.width - 1, 1)
        let height = max(originalSize.height - 1, 1)
        let xRatio = CGFloat(x) / width
        let yRatio = CGFloat(y) / height
        return CGPoint(
            x: xRatio * displaySize.width,
            y: yRatio * displaySize.height
        )
    }

    private func pixelCoordinate(fromDisplay point: CGPoint) -> PixelCoordinate {
        let clampedX = max(0, min(point.x, displaySize.width))
        let clampedY = max(0, min(point.y, displaySize.height))
        let maxX = max(Int(originalSize.width) - 1, 0)
        let maxY = max(Int(originalSize.height) - 1, 0)
        let rawX = Int((clampedX / max(displaySize.width, 1)) * originalSize.width)
        let rawY = Int((clampedY / max(displaySize.height, 1)) * originalSize.height)
        return PixelCoordinate(
            x: max(0, min(rawX, maxX)),
            y: max(0, min(rawY, maxY))
        )
    }
}

struct RulerDeleteKeyCatcher: NSViewRepresentable {
    @Binding var isActive: Bool
    let onDelete: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onDelete = onDelete
        return view
    }

    func updateNSView(_ nsView: KeyView, context: Context) {
        nsView.onDelete = onDelete
        guard isActive else { return }
        if nsView.window?.firstResponder !== nsView {
            nsView.window?.makeFirstResponder(nsView)
        }
    }

    final class KeyView: NSView {
        var onDelete: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            switch event.keyCode {
            case 51, 117:
                onDelete?()
            default:
                super.keyDown(with: event)
            }
        }
    }
}

struct TrackpadScrollCatcher: NSViewRepresentable {
    let onScroll: (CGSize) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScroll: onScroll)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        context.coordinator.onScroll = onScroll
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class TrackingView: NSView {}

    final class Coordinator {
        private weak var view: NSView?
        private var monitor: Any?
        var onScroll: (CGSize) -> Void

        init(onScroll: @escaping (CGSize) -> Void) {
            self.onScroll = onScroll
        }

        func attach(to view: NSView) {
            self.view = view
            installMonitorIfNeeded()
        }

        func detach() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        deinit {
            detach()
        }

        private func installMonitorIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard event.hasPreciseScrollingDeltas else { return event }
                guard let view = self.view,
                      let window = view.window,
                      event.window === window else {
                    return event
                }

                let location = view.convert(event.locationInWindow, from: nil)
                guard view.bounds.contains(location) else { return event }

                let delta = CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY)
                guard delta.width != 0 || delta.height != 0 else { return event }
                self.onScroll(delta)
                return event
            }
        }
    }
}

struct TrimActionButton: View {
    let icon: String
    let color: Color
    let tooltip: String
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .shadow(color: isHovered ? color.opacity(0.3) : .clear, radius: 4, x: 0, y: 2)
                
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(isHovered ? 0.8 : 0.4), lineWidth: isHovered ? 2 : 1)
                
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isHovered ? .white : color)
            }
        }
        .buttonStyle(.plain)
        .frame(width: 30, height: 30)
        .scaleEffect(isPressed ? 0.92 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .help(tooltip)
    }
    
    private var backgroundColor: Color {
        if isPressed {
            return color.opacity(0.9)
        } else if isHovered {
            return color.opacity(0.75)
        } else {
            return color.opacity(0.15)
        }
    }
}

struct FastImportSheetView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDevice: FastImportDevice = .specimIQ
    @State private var selectedMode: FastImportDataMode = .reflectance

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(state.localized("fast_import.title"))
                .font(.title3.weight(.semibold))

            Text(state.localized("fast_import.description"))
                .font(.system(size: 13))
                .foregroundColor(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("fast_import.device"))
                    .font(.system(size: 13, weight: .semibold))
                Picker(state.localized("fast_import.device"), selection: $selectedDevice) {
                    ForEach(FastImportDevice.allCases) { device in
                        Text(device.localizedTitle).tag(device)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(state.localized("fast_import.mode"))
                    .font(.system(size: 13, weight: .semibold))
                Picker(state.localized("fast_import.mode"), selection: $selectedMode) {
                    ForEach(FastImportDataMode.allCases) { mode in
                        Text(mode.localizedTitle).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            HStack {
                Spacer()
                Button(state.localized("common.cancel")) {
                    dismiss()
                }
                Button(state.localized("fast_import.import_button")) {
                    let device = selectedDevice
                    let mode = selectedMode
                    dismiss()
                    DispatchQueue.main.async {
                        state.startFastImport(device: device, dataMode: mode)
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 460)
    }
}

struct BusyOverlayView: View {
    let message: String
    let progress: Double?
    
    var body: some View {
        VStack(spacing: 10) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 240)
                Text("\(Int((max(0, min(1, progress)) * 100).rounded()))%")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.1)
            }
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 32)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.25), radius: 20, x: 0, y: 10)
        )
    }
}

struct AlignmentPointsOverlay: View {
    @EnvironmentObject var state: AppState
    let result: SpectralAlignmentResult?
    let params: SpectralAlignmentParameters?
    let currentChannel: Int
    let originalSize: CGSize
    let displaySize: CGSize
    
    @State private var draggingIndex: Int? = nil
    
    var body: some View {
        let points = params?.referencePoints ?? AlignmentPoint.defaultCorners()
        let isEditable = state.alignmentPointsEditable
        
        let offset: (dx: Int, dy: Int) = {
            if let result = result, currentChannel < result.channelOffsets.count {
                return result.channelOffsets[currentChannel]
            }
            return (dx: 0, dy: 0)
        }()
        
        let isReference = result != nil && currentChannel == result!.referenceChannel
        let scaleX = displaySize.width / originalSize.width
        let scaleY = displaySize.height / originalSize.height
        let offsetDx = CGFloat(offset.dx) * scaleX
        let offsetDy = CGFloat(offset.dy) * scaleY
        
        return ZStack {
            if points.count == 4 {
                Path { path in
                    for i in 0..<4 {
                        let pt = points[i]
                        let x = CGFloat(pt.x) * displaySize.width
                        let y = CGFloat(pt.y) * displaySize.height
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                    path.closeSubpath()
                }
                .stroke(Color.cyan.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
            }
            
            ForEach(0..<points.count, id: \.self) { idx in
                let pt = points[idx]
                let baseX = CGFloat(pt.x) * displaySize.width
                let baseY = CGFloat(pt.y) * displaySize.height
                let targetX = baseX + offsetDx
                let targetY = baseY + offsetDy
                
                if result != nil && !isReference && (offset.dx != 0 || offset.dy != 0) {
                    Path { path in
                        path.move(to: CGPoint(x: baseX, y: baseY))
                        path.addLine(to: CGPoint(x: targetX, y: targetY))
                    }
                    .stroke(Color.orange.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [4, 2]))
                }
                
                if result != nil && !isReference {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .stroke(Color.white, lineWidth: 2)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                        .position(x: targetX, y: targetY)
                }
                
                DraggableAlignmentPoint(
                    index: idx,
                    position: CGPoint(x: baseX, y: baseY),
                    displaySize: displaySize,
                    isEditable: isEditable,
                    isDragging: draggingIndex == idx,
                    isReference: result != nil && isReference,
                    onDrag: { newPos in
                        draggingIndex = idx
                        let normalizedX = max(0.0, min(1.0, Double(newPos.x / displaySize.width)))
                        let normalizedY = max(0.0, min(1.0, Double(newPos.y / displaySize.height)))
                        state.updateAlignmentPoint(at: idx, to: AlignmentPoint(x: normalizedX, y: normalizedY))
                    },
                    onDragEnd: {
                        draggingIndex = nil
                    }
                )
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(LF("content.alignment.channel", currentChannel))
                    .font(.system(size: 10, weight: .semibold))
                if result != nil && isReference {
                    Text(AppLocalizer.localized("(эталон)"))
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                } else if result != nil {
                    Text("dx: \(offset.dx), dy: \(offset.dy)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.orange)
                }
                if isEditable {
                    Text(AppLocalizer.localized("Перетащите точки"))
                        .font(.system(size: 8))
                        .foregroundColor(.cyan)
                }
            }
            .padding(6)
            .background(Color.black.opacity(0.7))
            .cornerRadius(4)
            .foregroundColor(.white)
            .position(x: 70, y: 40)
            .allowsHitTesting(false)
        }
    }
}

struct DraggableAlignmentPoint: View {
    let index: Int
    let position: CGPoint
    let displaySize: CGSize
    let isEditable: Bool
    let isDragging: Bool
    let isReference: Bool
    let onDrag: (CGPoint) -> Void
    let onDragEnd: () -> Void
    
    @State private var isHovering: Bool = false
    @GestureState private var dragState: CGSize = .zero
    
    var body: some View {
        let pointColor: Color = isReference ? .blue : .cyan
        let size: CGFloat = isEditable ? 18 : 12
        let hitAreaSize: CGFloat = 40
        
        ZStack {
            Circle()
                .fill(Color.clear)
                .frame(width: hitAreaSize, height: hitAreaSize)
                .contentShape(Circle())
            
            if isEditable && (isHovering || isDragging) {
                Circle()
                    .fill(pointColor.opacity(0.3))
                    .frame(width: 32, height: 32)
            }
            
            Circle()
                .fill(pointColor)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                )
                .overlay(
                    Text("\(index + 1)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
        .scaleEffect(isDragging ? 1.2 : (isHovering && isEditable ? 1.1 : 1.0))
        .animation(.easeInOut(duration: 0.1), value: isDragging)
        .animation(.easeInOut(duration: 0.1), value: isHovering)
        .position(x: position.x, y: position.y)
        .onHover { hovering in
            isHovering = hovering
            if hovering && isEditable {
                NSCursor.openHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .highPriorityGesture(
            isEditable ?
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .updating($dragState) { value, state, _ in
                    state = value.translation
                }
                .onChanged { value in
                    let newX = position.x + value.translation.width
                    let newY = position.y + value.translation.height
                    onDrag(CGPoint(x: newX, y: newY))
                }
                .onEnded { value in
                    let newX = position.x + value.translation.width
                    let newY = position.y + value.translation.height
                    onDrag(CGPoint(x: newX, y: newY))
                    onDragEnd()
                }
            : nil
        )
    }
}
