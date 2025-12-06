import SwiftUI

struct ChannelSliderView: View {
    @Binding var currentChannel: Double
    let channelCount: Int
    let cube: HyperCube?
    let layout: CubeLayout
    
    var isTrimMode: Bool = false
    @Binding var trimStart: Double
    @Binding var trimEnd: Double
    
    @State private var channelPreviews: [Color] = []
    @State private var isDragging: Bool = false
    @State private var draggingTrimHandle: TrimHandle? = nil
    @GestureState private var dragOffset: CGFloat = 0
    
    private let sliderHeight: CGFloat = 60
    private let thumbSize: CGFloat = 4
    private let trimHandleWidth: CGFloat = 12
    
    enum TrimHandle {
        case start, end
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                channelPreviewTrack(width: geometry.size.width)
                
                if isTrimMode {
                    trimOverlay(width: geometry.size.width)
                    trimHandles(width: geometry.size.width)
                }
                
                thumbIndicator(width: geometry.size.width)
            }
            .frame(height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if isTrimMode {
                            handleTrimDrag(value: value, width: geometry.size.width)
                        } else {
                            isDragging = true
                            updateChannel(from: value.location.x, width: geometry.size.width)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        draggingTrimHandle = nil
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
            ForEach(0..<channelCount, id: \.self) { index in
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
    
    private func trimOverlay(width: CGFloat) -> some View {
        let startX = positionForChannel(trimStart, width: width)
        let endX = positionForChannel(trimEnd, width: width)
        
        return ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: startX, height: sliderHeight - 8)
                .position(x: startX / 2, y: (sliderHeight - 8) / 2 + 4)
            
            Rectangle()
                .fill(Color.black.opacity(0.5))
                .frame(width: width - endX, height: sliderHeight - 8)
                .position(x: endX + (width - endX) / 2, y: (sliderHeight - 8) / 2 + 4)
            
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(endX - startX, 0), height: sliderHeight - 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 3)
                )
                .position(x: startX + (endX - startX) / 2, y: (sliderHeight - 8) / 2 + 4)
        }
    }
    
    private func trimHandles(width: CGFloat) -> some View {
        let startX = positionForChannel(trimStart, width: width)
        let endX = positionForChannel(trimEnd, width: width)
        
        return ZStack {
            TrimHandleView(isLeft: true)
                .position(x: startX, y: sliderHeight / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newChannel = channelForPosition(value.location.x, width: width)
                            trimStart = min(newChannel, trimEnd - 1)
                            trimStart = max(0, trimStart)
                        }
                )
            
            TrimHandleView(isLeft: false)
                .position(x: endX, y: sliderHeight / 2)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            let newChannel = channelForPosition(value.location.x, width: width)
                            trimEnd = max(newChannel, trimStart + 1)
                            trimEnd = min(Double(channelCount - 1), trimEnd)
                        }
                )
        }
    }
    
    private func thumbIndicator(width: CGFloat) -> some View {
        let thumbPosition = positionForChannel(currentChannel, width: width)
        
        return Rectangle()
            .fill(Color.red)
            .frame(width: thumbSize, height: sliderHeight)
            .cornerRadius(thumbSize / 2)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .position(x: thumbPosition, y: sliderHeight / 2)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: currentChannel)
    }
    
    private func positionForChannel(_ channel: Double, width: CGFloat) -> CGFloat {
        return (CGFloat(channel) / CGFloat(max(channelCount - 1, 1))) * width
    }
    
    private func channelForPosition(_ x: CGFloat, width: CGFloat) -> Double {
        let percentage = max(0, min(1, x / width))
        return round(percentage * Double(max(channelCount - 1, 0)))
    }
    
    private func handleTrimDrag(value: DragGesture.Value, width: CGFloat) {
        let x = value.location.x
        let startX = positionForChannel(trimStart, width: width)
        let endX = positionForChannel(trimEnd, width: width)
        
        if draggingTrimHandle == nil {
            let distToStart = abs(x - startX)
            let distToEnd = abs(x - endX)
            
            if distToStart < trimHandleWidth * 2 && distToStart <= distToEnd {
                draggingTrimHandle = .start
            } else if distToEnd < trimHandleWidth * 2 {
                draggingTrimHandle = .end
            }
        }
        
        switch draggingTrimHandle {
        case .start:
            let newChannel = channelForPosition(x, width: width)
            trimStart = min(newChannel, trimEnd - 1)
            trimStart = max(0, trimStart)
        case .end:
            let newChannel = channelForPosition(x, width: width)
            trimEnd = max(newChannel, trimStart + 1)
            trimEnd = min(Double(channelCount - 1), trimEnd)
        case .none:
            break
        }
    }
    
    private func updateChannel(from x: CGFloat, width: CGFloat) {
        let percentage = max(0, min(1, x / width))
        let newChannel = percentage * Double(max(channelCount - 1, 0))
        currentChannel = round(newChannel)
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

struct TrimHandleView: View {
    let isLeft: Bool
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.yellow)
                .frame(width: 14, height: 50)
                .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            
            VStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 6, height: 2)
                }
            }
        }
        .contentShape(Rectangle().size(width: 24, height: 60))
    }
}

struct ChannelSliderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChannelSliderView(
                currentChannel: .constant(50),
                channelCount: 100,
                cube: nil,
                layout: .auto,
                trimStart: .constant(0),
                trimEnd: .constant(99)
            )
            .padding()
            
            ChannelSliderView(
                currentChannel: .constant(50),
                channelCount: 100,
                cube: nil,
                layout: .auto,
                isTrimMode: true,
                trimStart: .constant(20),
                trimEnd: .constant(80)
            )
            .padding()
            
            Text("Channel: 50 / 99")
                .font(.system(size: 11))
        }
    }
}

