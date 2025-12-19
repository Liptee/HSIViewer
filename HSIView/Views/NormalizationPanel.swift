import SwiftUI

struct NormalizationPanel: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded: Bool = true
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Text("Нормализация")
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
                    Picker("Тип:", selection: $state.normalizationType) {
                        ForEach(CubeNormalizationType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    
                    Text(state.normalizationType.description)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    if state.normalizationType.hasParameters {
                        Divider()
                            .padding(.vertical, 4)
                        
                        parametersView
                    }
                    
                    Button(action: {
                        state.applyNormalization()
                    }) {
                        HStack {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 10))
                            Text("Применить")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(state.cube == nil)
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
    }
    
    @ViewBuilder
    private var parametersView: some View {
        switch state.normalizationType {
        case .minMaxCustom:
            VStack(alignment: .leading, spacing: 8) {
                Text("Параметры:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Min:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("0.0", value: $state.normalizationParams.minValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                
                HStack {
                    Text("Max:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("1.0", value: $state.normalizationParams.maxValue, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
            }
        case .manualRange:
            VStack(alignment: .leading, spacing: 8) {
                Text("Исходный диапазон:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Min:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("0.0", value: $state.normalizationParams.sourceMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                
                HStack {
                    Text("Max:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("1.0", value: $state.normalizationParams.sourceMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                
                Text("Новый диапазон:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Min:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("0.0", value: $state.normalizationParams.targetMin, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                
                HStack {
                    Text("Max:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 35, alignment: .leading)
                    
                    TextField("1.0", value: $state.normalizationParams.targetMax, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
            }
            
        case .percentile:
            VStack(alignment: .leading, spacing: 8) {
                Text("Параметры:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack {
                    Text("Нижний %:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    TextField("2.0", value: $state.normalizationParams.lowerPercentile, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
                
                HStack {
                    Text("Верхний %:")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 70, alignment: .leading)
                    
                    TextField("98.0", value: $state.normalizationParams.upperPercentile, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 10, design: .monospaced))
                }
            }
            
        default:
            EmptyView()
        }
    }
}
