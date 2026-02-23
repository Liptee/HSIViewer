import SwiftUI

struct ToolbarDockView: View {
    @EnvironmentObject var state: AppState

    private var visibleAnalysisTools: [AnalysisTool] {
        AnalysisTool.allCases.filter { tool in
            guard tool != .none else { return false }
            if tool == .spectrumGraphLayer {
                return state.hasMaskLayerSpectra || state.activeAnalysisTool == .spectrumGraphLayer
            }
            return true
        }
    }
    
    var body: some View {
        GlassCapsule(padding: 0) {
            HStack(spacing: 6) {
                ForEach(visibleAnalysisTools) { tool in
                    ToolButton(
                        tool: tool,
                        iconName: iconName(for: tool),
                        isActive: state.activeAnalysisTool == tool,
                        isRulerEditMode: tool == .ruler
                            && state.activeAnalysisTool == .ruler
                            && state.rulerMode == .edit
                    ) {
                        state.toggleAnalysisTool(tool)
                    }
                }
                
                if state.viewMode == .mask {
                    Divider()
                        .frame(height: 18)
                    MaskInlineTools(maskState: state.maskEditorState)
                        .environmentObject(state)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    private func iconName(for tool: AnalysisTool) -> String {
        if tool == .ruler,
           state.activeAnalysisTool == .ruler,
           state.rulerMode == .edit {
            return "ruler.fill"
        }
        return tool.iconName
    }
}

private struct MaskInlineTools: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var maskState: MaskEditorState
    @State private var showMaskSettings: Bool = false

    private func activateMaskTool(_ tool: MaskDrawingTool) {
        if state.activeAnalysisTool != .none {
            state.activeAnalysisTool = .none
        }
        state.selectedRulerPointID = nil
        state.maskEditorState.currentTool = tool
    }

    private func isMaskToolActive(_ tool: MaskDrawingTool) -> Bool {
        state.viewMode == .mask
            && state.activeAnalysisTool == .none
            && state.maskEditorState.currentTool == tool
    }

    private func maskToolBackground(for tool: MaskDrawingTool) -> Color {
        if isMaskToolActive(tool) {
            return Color.accentColor.opacity(0.15)
        }
        return Color.clear
    }
    
    var body: some View {
        Group {
            ForEach(MaskDrawingTool.allCases) { tool in
                Button {
                    activateMaskTool(tool)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(maskToolBackground(for: tool))
                        if isMaskToolActive(tool) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.accentColor, lineWidth: 1.5)
                        }
                        Image(systemName: tool.iconName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isMaskToolActive(tool) ? .accentColor : .secondary)
                    }
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .help(tool.localizedTitle)
            }
            
            Button {
                showMaskSettings.toggle()
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                    )
            }
            .buttonStyle(.plain)
            .help(AppLocalizer.localized("Параметры инструмента маски"))
            .popover(isPresented: $showMaskSettings, arrowEdge: .bottom) {
                MaskToolSettingsPopover(maskState: maskState)
            }
            
            if let activeID = maskState.activeLayerID {
                Button {
                    maskState.undo(for: activeID)
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!maskState.canUndo(for: activeID))
                .keyboardShortcut("z", modifiers: .command)
                .help(AppLocalizer.localized("Отменить (⌘Z)"))
            }
        }
    }
}

private struct MaskToolSettingsPopover: View {
    @ObservedObject var maskState: MaskEditorState
    private let presetSizes: [Int] = [1, 5, 10, 25, 50]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(LF("mask.brush_size_px", maskState.brushSize))
                .font(.system(size: 11, weight: .semibold))
            
            Slider(
                value: Binding(
                    get: { Double(maskState.brushSize) },
                    set: { maskState.brushSize = Int($0) }
                ),
                in: 1...100,
                step: 1
            )
            .frame(width: 190)
            
            HStack(spacing: 6) {
                ForEach(presetSizes, id: \.self) { size in
                    Button("\(size)") {
                        maskState.brushSize = size
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(maskState.brushSize == size ? .accentColor : nil)
                }
            }
        }
        .padding(12)
    }
}

struct ToolButton: View {
    let tool: AnalysisTool
    let iconName: String
    let isActive: Bool
    let isRulerEditMode: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)

                if isRulerEditMode {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.ultraThinMaterial.opacity(0.8))
                        .overlay(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.45),
                                    Color.white.opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
                
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActive ? .accentColor : (isHovered ? .primary : .secondary))
            }
            .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .help(tool.displayName)
    }
    
    private var backgroundColor: Color {
        if isActive {
            return Color.accentColor.opacity(0.15)
        } else if isHovered {
            return Color(NSColor.controlBackgroundColor).opacity(0.8)
        } else {
            return Color.clear
        }
    }
}
