import SwiftUI

struct ColorSynthesisSliderView: View {
    let channelCount: Int
    let cube: HyperCube?
    let layout: CubeLayout
    let mapping: RGBChannelMapping
    let onMappingChange: (RGBChannelMapping) -> Void
    
    @State private var channelPreviews: [Color] = []
    @State private var activeThumb: Thumb?
    
    private let sliderHeight: CGFloat = 60
    private let thumbWidth: CGFloat = 10
    
    enum Thumb: CaseIterable {
        case red, green, blue
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                channelPreviewTrack(width: geometry.size.width)
                thumbs(width: geometry.size.width)
            }
            .frame(height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDrag(at: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { _ in
                        activeThumb = nil
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
    
    private func thumbs(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            thumbView(color: .red, channel: mapping.red, thumb: .red, width: width)
            thumbView(color: .green, channel: mapping.green, thumb: .green, width: width)
            thumbView(color: .blue, channel: mapping.blue, thumb: .blue, width: width)
        }
    }
    
    private func thumbView(color: Color, channel: Int, thumb: Thumb, width: CGFloat) -> some View {
        let xPosition = position(for: channel, width: width)
        let isActive = activeThumb == thumb
        
        return VStack(spacing: 4) {
            Text("\(channel)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
                .cornerRadius(4)
            
            Rectangle()
                .fill(color)
                .frame(width: thumbWidth, height: sliderHeight - 10)
                .cornerRadius(4)
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
        
        if activeThumb == nil {
            activeThumb = nearestThumb(to: x, width: width)
        }
        
        guard let thumb = activeThumb else { return }
        let newChannel = channel(for: x, width: width)
        var newMapping = mapping
        
        switch thumb {
        case .red:
            newMapping.red = newChannel
        case .green:
            newMapping.green = newChannel
        case .blue:
            newMapping.blue = newChannel
        }
        
        onMappingChange(newMapping)
    }
    
    private func nearestThumb(to x: CGFloat, width: CGFloat) -> Thumb {
        let positions: [(Thumb, CGFloat)] = [
            (.red, position(for: mapping.red, width: width)),
            (.green, position(for: mapping.green, width: width)),
            (.blue, position(for: mapping.blue, width: width))
        ]
        
        return positions.min { abs($0.1 - x) < abs($1.1 - x) }?.0 ?? .red
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
