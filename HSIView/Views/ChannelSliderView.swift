import SwiftUI

struct ChannelSliderView: View {
    @Binding var currentChannel: Double
    let channelCount: Int
    let cube: HyperCube?
    
    @State private var channelPreviews: [Color] = []
    @State private var isDragging: Bool = false
    @GestureState private var dragOffset: CGFloat = 0
    
    private let sliderHeight: CGFloat = 60
    private let thumbSize: CGFloat = 4
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                channelPreviewTrack(width: geometry.size.width)
                
                thumbIndicator(width: geometry.size.width)
            }
            .frame(height: sliderHeight)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragOffset) { value, state, _ in
                        state = value.location.x
                    }
                    .onChanged { value in
                        isDragging = true
                        updateChannel(from: value.location.x, width: geometry.size.width)
                    }
                    .onEnded { _ in
                        isDragging = false
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
    }
    
    private func channelPreviewTrack(width: CGFloat) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<channelCount, id: \.self) { index in
                Rectangle()
                    .fill(channelPreviews.indices.contains(index) ? channelPreviews[index] : Color.gray)
                    .frame(width: width / CGFloat(channelCount))
            }
        }
        .frame(height: sliderHeight - 8)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private func thumbIndicator(width: CGFloat) -> some View {
        let thumbPosition = (CGFloat(currentChannel) / CGFloat(max(channelCount - 1, 1))) * width
        
        return Rectangle()
            .fill(Color.red)
            .frame(width: thumbSize, height: sliderHeight)
            .cornerRadius(thumbSize / 2)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
            .position(x: thumbPosition, y: sliderHeight / 2)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: currentChannel)
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
        
        DispatchQueue.global(qos: .userInitiated).async {
            var previews: [Color] = []
            
            let (height, width, channels) = cube.dims
            let sampleSize = min(height * width, 10000)
            
            for ch in 0..<channels {
                var sum: Double = 0.0
                var count = 0
                
                let step = max(1, (height * width) / sampleSize)
                
                for h in stride(from: 0, to: height, by: step) {
                    for w in stride(from: 0, to: width, by: step) {
                        let idx = cube.linearIndex(i0: h, i1: w, i2: ch)
                        let value = cube.getValue(at: idx)
                        sum += value
                        count += 1
                    }
                }
                
                let average = count > 0 ? sum / Double(count) : 0.0
                
                let normalizedValue: Double
                switch cube.originalDataType {
                case .uint8:
                    normalizedValue = average / 255.0
                case .uint16:
                    normalizedValue = average / 65535.0
                case .float32, .float64:
                    normalizedValue = min(max(average, 0.0), 1.0)
                default:
                    normalizedValue = min(max(average / 255.0, 0.0), 1.0)
                }
                
                let grayValue = min(max(normalizedValue, 0.0), 1.0)
                previews.append(Color(white: grayValue))
            }
            
            DispatchQueue.main.async {
                channelPreviews = previews
            }
        }
    }
}

struct ChannelSliderView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ChannelSliderView(
                currentChannel: .constant(50),
                channelCount: 100,
                cube: nil
            )
            .padding()
            
            Text("Channel: 50 / 99")
                .font(.system(size: 11))
        }
    }
}

