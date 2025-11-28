import SwiftUI

struct DataTypePanel: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded: Bool = true
    @State private var selectedDataType: DataType = .float64
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Тип данных")
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
                VStack(alignment: .leading, spacing: 12) {
                    if let cube = state.cube {
                        Text("Текущий тип: \(cube.originalDataType.rawValue)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Преобразовать в:")
                            .font(.system(size: 10, weight: .medium))
                        
                        Picker("", selection: $selectedDataType) {
                            Group {
                                Text("Float64 (Double)").tag(DataType.float64)
                                Text("Float32").tag(DataType.float32)
                            }
                            
                            Divider()
                            
                            Group {
                                Text("UInt8 (0-255)").tag(DataType.uint8)
                                Text("UInt16 (0-65535)").tag(DataType.uint16)
                            }
                            
                            Divider()
                            
                            Group {
                                Text("Int8 (-128...127)").tag(DataType.int8)
                                Text("Int16 (-32768...32767)").tag(DataType.int16)
                                Text("Int32").tag(DataType.int32)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Масштабирование:")
                            .font(.system(size: 10, weight: .medium))
                        
                        HStack(spacing: 12) {
                            Toggle("Автоматическое", isOn: $state.autoScaleOnTypeConversion)
                                .font(.system(size: 10))
                                .toggleStyle(.switch)
                                .controlSize(.mini)
                        }
                        
                        if state.autoScaleOnTypeConversion {
                            Text("Данные будут масштабированы в диапазон целевого типа")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("Значения будут обрезаны (clamped)")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    
                    Button(action: {
                        state.convertDataType(to: selectedDataType)
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                            Text("Применить")
                        }
                        .font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(state.cube == nil || state.cube?.originalDataType == selectedDataType)
                    
                    if let cube = state.cube {
                        Divider()
                            .padding(.vertical, 4)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            infoRow(
                                title: "Размер в памяти",
                                value: formatMemorySize(bytes: cube.storage.sizeInBytes)
                            )
                            
                            if selectedDataType != cube.originalDataType {
                                let estimatedSize = estimateSize(
                                    elementCount: cube.totalElements,
                                    dataType: selectedDataType
                                )
                                
                                infoRow(
                                    title: "После конвертации",
                                    value: formatMemorySize(bytes: estimatedSize)
                                )
                                
                                let ratio = Double(estimatedSize) / Double(cube.storage.sizeInBytes)
                                let change = ratio >= 1.0 
                                    ? String(format: "↑ %.1fx", ratio)
                                    : String(format: "↓ %.1fx", 1.0 / ratio)
                                
                                infoRow(title: "Изменение", value: change)
                                    .foregroundColor(ratio >= 1.0 ? .orange : .green)
                            }
                        }
                    }
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
            if let cube = state.cube {
                selectedDataType = cube.originalDataType
            }
        }
        .onChange(of: state.cube?.id) { _ in
            if let cube = state.cube {
                selectedDataType = cube.originalDataType
            }
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
        }
    }
    
    private func formatMemorySize(bytes: Int) -> String {
        let sizeInMB = Double(bytes) / (1024 * 1024)
        let sizeInGB = Double(bytes) / (1024 * 1024 * 1024)
        
        if sizeInGB >= 1.0 {
            return String(format: "%.2f ГБ", sizeInGB)
        } else {
            return String(format: "%.1f МБ", sizeInMB)
        }
    }
    
    private func estimateSize(elementCount: Int, dataType: DataType) -> Int {
        let bytesPerElement: Int
        switch dataType {
        case .float64: bytesPerElement = 8
        case .float32: bytesPerElement = 4
        case .int8: bytesPerElement = 1
        case .int16: bytesPerElement = 2
        case .int32: bytesPerElement = 4
        case .uint8: bytesPerElement = 1
        case .uint16: bytesPerElement = 2
        case .unknown: bytesPerElement = 8
        }
        return elementCount * bytesPerElement
    }
}

