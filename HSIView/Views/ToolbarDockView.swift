import SwiftUI

struct ToolbarDockView: View {
    @EnvironmentObject var state: AppState
    
    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(AnalysisTool.allCases.filter { $0 != .none }) { tool in
                    ToolButton(
                        tool: tool,
                        isActive: state.activeAnalysisTool == tool
                    ) {
                        state.toggleAnalysisTool(tool)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 2)
            )
        }
        .padding(.vertical, 8)
    }
}

struct ToolButton: View {
    let tool: AnalysisTool
    let isActive: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(backgroundColor)
                    
                    if isActive {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 2)
                    }
                    
                    Image(systemName: tool.iconName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(isActive ? .accentColor : (isHovered ? .primary : .secondary))
                }
                .frame(width: 40, height: 40)
                
                Text(tool.displayName)
                    .font(.system(size: 9, weight: isActive ? .semibold : .regular))
                    .foregroundColor(isActive ? .accentColor : .secondary)
                    .lineLimit(1)
            }
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

