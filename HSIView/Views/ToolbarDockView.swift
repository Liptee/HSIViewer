import SwiftUI

struct ToolbarDockView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        GlassCapsule(padding: 0) {
            HStack(spacing: 6) {
                ForEach(AnalysisTool.allCases.filter { $0 != .none }) { tool in
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
