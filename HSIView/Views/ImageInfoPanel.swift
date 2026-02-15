import SwiftUI

struct ImageInfoPanel: View {
    @EnvironmentObject var state: AppState
    let cube: HyperCube
    let layout: CubeLayout
    @State private var isExpanded: Bool = true
    @State private var cachedStats: HyperCube.Statistics?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text(state.localized("imageinfo.title"))
                    .font(.system(size: 11, weight: .semibold))
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }
            
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow(title: state.localized("imageinfo.format"), value: cube.sourceFormat)
                    infoRow(title: state.localized("imageinfo.data_type"), value: cube.originalDataType.rawValue)
                    
                    if cube.is2D {
                        infoRow(title: state.localized("imageinfo.kind"), value: state.localized("imageinfo.kind.2d"))
                        if let dims2D = cube.dims2D {
                            infoRow(title: state.localized("imageinfo.size"), value: "\(dims2D.width) × \(dims2D.height)")
                        }
                    } else {
                        infoRow(title: state.localized("imageinfo.resolution"), value: cube.resolution)
                        infoRow(title: state.localized("imageinfo.channels"), value: "\(cube.channelCount(for: layout))")
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    if let stats = cachedStats {
                        infoRow(title: state.localized("imageinfo.min_value"), value: String(format: "%.4g", stats.min))
                        infoRow(title: state.localized("imageinfo.max_value"), value: String(format: "%.4g", stats.max))
                        infoRow(title: state.localized("imageinfo.mean_value"), value: String(format: "%.4g", stats.mean))
                        infoRow(title: state.localized("imageinfo.std_dev"), value: String(format: "%.4g", stats.stdDev))
                    }
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    infoRow(title: state.localized("imageinfo.memory_size"), value: formatMemorySize(bytes: cube.storage.sizeInBytes))
                }
                .padding(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onAppear {
            if cachedStats == nil {
                cachedStats = cube.statistics()
            }
        }
        .onChange(of: cube.id) { _ in
            cachedStats = cube.statistics()
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        HStack {
            Text(title + ":")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .textSelection(.enabled)
        }
    }
    
    private func formatMemorySize(bytes: Int) -> String {
        let sizeInMB = Double(bytes) / (1024 * 1024)
        let sizeInGB = Double(bytes) / (1024 * 1024 * 1024)
        
        if sizeInGB >= 1.0 {
            return state.localizedFormat("units.size.gb", sizeInGB)
        } else {
            return state.localizedFormat("units.size.mb", sizeInMB)
        }
    }
}

