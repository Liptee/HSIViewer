import SwiftUI

struct ToolbarDockView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack(spacing: 6) {
            ForEach(AnalysisTool.allCases.filter { $0 != .none }) { tool in
                ToolButton(
                    tool: tool,
                    isActive: state.activeAnalysisTool == tool
                ) {
                    state.toggleAnalysisTool(tool)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 1)
        )
    }
}

struct ToolButton: View {
    let tool: AnalysisTool
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(backgroundColor)
                
                if isActive {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1.5)
                }
                
                Image(systemName: tool.iconName)
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

