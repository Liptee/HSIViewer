import SwiftUI

struct ColorSynthesisRangeSliderView: View {
    let channelCount: Int
    let cube: HyperCube?
    let layout: CubeLayout
    let rangeMapping: RGBChannelRangeMapping
    let onRangeChange: (RGBChannelRangeMapping) -> Void
    
    @State private var channelPreviews: [Color] = []
    @State private var activeHandle: RangeHandle?
    
    private let sliderHeight: CGFloat = 60
    private let handleWidth: CGFloat = 8
    
    enum RangeHandle: CaseIterable {
        case redStart, redEnd
        case greenStart, greenEnd
        case blueStart, blueEnd
        
        var color: Color {
            switch self {
            case .redStart, .redEnd: return .red
            case .greenStart, .greenEnd: return .green
            case .blueStart, .blueEnd: return .blue
            }
        }
        
        var isStart: Bool {
            switch self {
            case .redStart, .greenStart, .blueStart:
                return true
            case .redEnd, .greenEnd, .blueEnd:
                return false
            }
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                channelPreviewTrack(width: geometry.size.width)
                rangeOverlays(width: geometry.size.width)
                handles(width: geometry.size.width)
            }
            .frame(height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
        .frame(height: sliderHeight)
        .onAppear {
            generateChannelPreviews()
        }
        .onChange(of: cube?.id) { _ in
            generateChannelPreviews()
        }
        .onChange(of: layout) { _ in
            generateChannelPreviews()
        }
    }
    
    private func channelPreviewTrack(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<max(channelCount, 1), id: \.self) { index in
                Rectangle()
                    .fill(channelPreviews.indices.contains(index) ? channelPreviews[index] : Color.gray)
                    .frame(width: width / CGFloat(max(channelCount, 1)))
            }
        }
        .frame(height: sliderHeight - 8)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func rangeOverlays(width: CGFloat) -> some View {
        let clamped = rangeMapping.clamped(maxChannelCount: max(channelCount, 0))
        return ZStack {
            rangeOverlay(for: clamped.red, color: .red, width: width)
            rangeOverlay(for: clamped.green, color: .green, width: width)
            rangeOverlay(for: clamped.blue, color: .blue, width: width)
        }
    }
    
    private func rangeOverlay(for range: RGBChannelRange, color: Color, width: CGFloat) -> some View {
        let normalized = range.normalized
        let startX = position(for: normalized.start, width: width)
        let endX = position(for: normalized.end, width: width)
        let overlayWidth = max(endX - startX, 0)
        
        return Rectangle()
            .fill(color.opacity(0.18))
            .frame(width: overlayWidth, height: sliderHeight - 14)
            .position(x: startX + overlayWidth / 2, y: sliderHeight / 2)
    }
    
    private func handles(width: CGFloat) -> some View {
        let clamped = rangeMapping.clamped(maxChannelCount: max(channelCount, 0))
        return ZStack(alignment: .topLeading) {
            handleView(color: .red, channel: clamped.red.start, handle: .redStart, width: width)
            handleView(color: .red, channel: clamped.red.end, handle: .redEnd, width: width)
            handleView(color: .green, channel: clamped.green.start, handle: .greenStart, width: width)
            handleView(color: .green, channel: clamped.green.end, handle: .greenEnd, width: width)
            handleView(color: .blue, channel: clamped.blue.start, handle: .blueStart, width: width)
            handleView(color: .blue, channel: clamped.blue.end, handle: .blueEnd, width: width)
        }
    }
    
    private func handleView(color: Color, channel: Int, handle: RangeHandle, width: CGFloat) -> some View {
        let xPosition = position(for: channel, width: width)
        let isActive = activeHandle == handle
        
        return VStack(spacing: 4) {
            Text("\(channel)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .cornerRadius(4)
            
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: handleWidth, height: sliderHeight - 12)
                .shadow(color: isActive ? color.opacity(0.7) : .clear, radius: 3, x: 0, y: 1)
        }
        .position(x: xPosition, y: sliderHeight / 2)
        .animation(.easeInOut(duration: 0.15), value: channel)
    }
    
    private func position(for channel: Int, width: CGFloat) -> CGFloat {
        guard channelCount > 1 else { return width / 2 }
        return CGFloat(channel) / CGFloat(channelCount - 1) * width
    }
    
    private func channel(for position: CGFloat, width: CGFloat) -> Int {
        guard channelCount > 1 else { return 0 }
        let clampedX = max(0, min(width, position))
        let ratio = clampedX / width
        let channel = Int(round(ratio * CGFloat(channelCount - 1)))
        return max(0, min(channel, max(channelCount - 1, 0)))
    }
    
    private func handleDrag(at x: CGFloat, width: CGFloat) {
        guard channelCount > 0 else { return }
        
        if activeHandle == nil {
            activeHandle = nearestHandle(to: x, width: width)
        }
        
        guard let handle = activeHandle else { return }
        let newChannel = channel(for: x, width: width)
        var newMapping = rangeMapping
        
        switch handle {
        case .redStart:
            newMapping.red.start = min(newChannel, newMapping.red.end)
        case .redEnd:
            newMapping.red.end = max(newChannel, newMapping.red.start)
        case .greenStart:
            newMapping.green.start = min(newChannel, newMapping.green.end)
        case .greenEnd:
            newMapping.green.end = max(newChannel, newMapping.green.start)
        case .blueStart:
            newMapping.blue.start = min(newChannel, newMapping.blue.end)
        case .blueEnd:
            newMapping.blue.end = max(newChannel, newMapping.blue.start)
        }
        
        onRangeChange(newMapping)
    }
    
    private func nearestHandle(to x: CGFloat, width: CGFloat) -> RangeHandle {
        let mapping = rangeMapping
        let positions: [(RangeHandle, CGFloat)] = [
            (.redStart, position(for: mapping.red.start, width: width)),
            (.redEnd, position(for: mapping.red.end, width: width)),
            (.greenStart, position(for: mapping.green.start, width: width)),
            (.greenEnd, position(for: mapping.green.end, width: width)),
            (.blueStart, position(for: mapping.blue.start, width: width)),
            (.blueEnd, position(for: mapping.blue.end, width: width))
        ]
        
        return positions.min { abs($0.1 - x) < abs($1.1 - x) }?.0 ?? .redStart
    }
    
    private func generateChannelPreviews() {
        guard let cube = cube else {
            channelPreviews = Array(repeating: Color.gray, count: channelCount)
            return
        }
        
        let currentLayout = layout
        
        DispatchQueue.global(qos: .userInitiated).async {
            var previews: [Color] = []
            
            guard let axes = cube.axes(for: currentLayout) else {
                DispatchQueue.main.async {
                    channelPreviews = Array(repeating: Color.gray, count: channelCount)
                }
                return
            }
            
            let (d0, d1, d2) = cube.dims
            let dimsArray = [d0, d1, d2]
            
            let channels = dimsArray[axes.channel]
            let height = dimsArray[axes.height]
            let width = dimsArray[axes.width]
            
            let sampleSize = min(height * width, 10000)
            let step = max(1, (height * width) / sampleSize)
            
            var globalMin = Double.infinity
            var globalMax = -Double.infinity
            var channelAverages: [Double] = []
            
            for ch in 0..<channels {
                var sum: Double = 0.0
                var count = 0
                
                for h in stride(from: 0, to: height, by: step) {
                    for w in stride(from: 0, to: width, by: step) {
                        var idx3 = [0, 0, 0]
                        idx3[axes.channel] = ch
                        idx3[axes.height] = h
                        idx3[axes.width] = w
                        
                        let idx = cube.linearIndex(i0: idx3[0], i1: idx3[1], i2: idx3[2])
                        let value = cube.getValue(at: idx)
                        sum += value
                        count += 1
                        
                        globalMin = min(globalMin, value)
                        globalMax = max(globalMax, value)
                    }
                }
                
                let average = count > 0 ? sum / Double(count) : 0.0
                channelAverages.append(average)
            }
            
            let range = globalMax - globalMin
            let safeRange = range > 1e-10 ? range : 1.0
            
            for average in channelAverages {
                let normalizedValue = (average - globalMin) / safeRange
                let grayValue = min(max(normalizedValue, 0.0), 1.0)
                previews.append(Color(white: grayValue))
            }
            
            DispatchQueue.main.async {
                channelPreviews = previews
            }
        }
    }
}

