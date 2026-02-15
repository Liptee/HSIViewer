import SwiftUI

struct MatVariableSelectionView: View {
    @EnvironmentObject var state: AppState
    let request: MatSelectionRequest
    
    @State private var selectedName: String
    
    init(request: MatSelectionRequest) {
        self.request = request
        _selectedName = State(initialValue: request.options.first?.name ?? "")
    }
    
    private var selectedOption: MatVariableOption? {
        request.options.first { $0.name == selectedName }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            optionsList
            Divider()
            footer
        }
        .frame(width: 420, height: 360)
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(state.localized("mat.select_variable.title"))
                .font(.system(size: 13, weight: .semibold))
            Text(request.fileURL.lastPathComponent)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(16)
    }
    
    private var optionsList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(request.options) { option in
                    selectionRow(for: option)
                }
            }
            .padding(16)
        }
    }
    
    @ViewBuilder
    private func selectionRow(for option: MatVariableOption) -> some View {
        let isSelected = selectedName == option.name
        Button {
            selectedName = option.name
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                    Text("\(option.formattedSize) • \(option.typeDescription)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(isSelected ? 0.6 : 0.3))
            )
        }
        .buttonStyle(.plain)
    }
    
    private var footer: some View {
        HStack {
            Button(state.localized("common.cancel")) {
                state.cancelMatSelection()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            
            Spacer()
            
            Button(state.localized("common.open")) {
                if let option = selectedOption {
                    state.confirmMatSelection(option: option)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(selectedOption == nil)
        }
        .padding(16)
    }
}
