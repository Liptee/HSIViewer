import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LibraryPanel: View {
    @EnvironmentObject var state: AppState
    @State private var isExpanded: Bool = true
    @State private var isTargeted: Bool = false
    @State private var selectedEntryIDs: Set<CubeLibraryEntry.ID> = []
    @State private var hoveredEntryID: CubeLibraryEntry.ID?
    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @State private var renameTargetID: CubeLibraryEntry.ID?
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                content
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted, perform: handleDrop(providers:))
        .focusable(true)
        .focusEffectDisabled(true)
        .focused($isFocused)
        .onDeleteCommand(perform: deleteSelectedEntries)
        .onChange(of: state.libraryEntries) { entries in
            let existingIDs = Set(entries.map(\.id))
            selectedEntryIDs = selectedEntryIDs.intersection(existingIDs)
        }
        .alert(state.localized("library.rename_cube.title"), isPresented: $isRenaming) {
            TextField(state.localized("library.rename_cube.field_name"), text: $renameText)
            Button(state.localized("common.save")) {
                commitRename()
            }
            Button(state.localized("common.cancel"), role: .cancel) {
                cancelRename()
            }
        } message: {
            Text(state.localized("library.rename_cube.message"))
        }
        .sheet(item: $state.cubeMetricsRequest) { request in
            CubeMetricsSheet(request: request)
                .environmentObject(state)
        }
    }
    
    private var header: some View {
        HStack {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Text(state.localized("library.title"))
                .font(.system(size: 11, weight: .semibold))
            Spacer()
            if isTargeted {
                Text(state.localized("library.drop_release_to_add"))
                    .font(.system(size: 10))
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isTargeted ? Color.accentColor.opacity(0.1) : Color(NSColor.controlBackgroundColor))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
    
    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.isCubeMetricsSelectionMode {
                cubeMetricsSelectionBanner
            }

            if state.libraryEntries.isEmpty {
                Text(state.localized("library.empty_hint"))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
                    )
            } else {
                ForEach(state.libraryEntries) { entry in
                    libraryRow(for: entry)
                }
            }
        }
        .padding(8)
    }
    
    @ViewBuilder
    private func libraryRow(for entry: CubeLibraryEntry) -> some View {
        let isActive = isEntryActive(entry)
        let isSelected = selectedEntryIDs.contains(entry.id) && !isActive
        let isMetricsSource = state.cubeMetricsSelectionSourceID == entry.id
        let isMetricsCandidate = state.isCubeMetricsSelectionMode && !isMetricsSource
        let isHovered = hoveredEntryID == entry.id
        let singleTap = TapGesture()
            .onEnded {
                if state.isCubeMetricsSelectionMode {
                    if isMetricsCandidate {
                        state.selectCubeMetricsTarget(entry.id)
                    }
                    isFocused = true
                    return
                }
                handleSelection(for: entry, isCommandPressed: isCommandPressed())
                isFocused = true
            }
        
        let doubleTap = TapGesture(count: 2)
            .onEnded {
                guard !state.isCubeMetricsSelectionMode else { return }
                selectSingleEntry(entry)
                state.open(url: entry.url)
            }
        
        let contextTargets = contextMenuTargets(for: entry)
        let canCopyFromSingle = contextTargets.count == 1 && contextTargets.first.map { state.canCopyProcessing(from: $0) } == true
        let canCopyWavelengthsFromSingle = contextTargets.count == 1 && contextTargets.first.map { state.canCopyWavelengths(from: $0) } == true
        let canCopySelectionsFromSingle = contextTargets.count == 1 && contextTargets.first.map { state.canCopySpectrumSelections(from: $0) } == true
        let canPastePoint = state.canPasteSpectrumPoint
        let canPasteROI = state.canPasteSpectrumROI
        let canPasteSelections = state.canPasteSpectrumSelections
        let canRename = contextTargets.count == 1
        let canCallMetrics = contextTargets.count == 1 && state.libraryEntries.count > 1
        
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isActive ? .accentColor : .primary)
            libraryStatsRow(for: entry)
            Label(state.libraryEntryWavelengthRangeText(for: entry), systemImage: "waveform.path")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor(
                    isActive: isActive,
                    isSelected: isSelected,
                    isMetricsSource: isMetricsSource,
                    isMetricsCandidate: isMetricsCandidate
                ))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor(
                    isActive: isActive,
                    isSelected: isSelected,
                    isMetricsSource: isMetricsSource,
                    isMetricsCandidate: isMetricsCandidate
                ), lineWidth: 1)
        )
        .scaleEffect(isHovered ? 1.02 : 1.0)
        .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.0), radius: isHovered ? 8 : 0, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .contentShape(Rectangle())
        .highPriorityGesture(doubleTap)
        .simultaneousGesture(singleTap)
        .onHover { hovering in
            if hovering {
                hoveredEntryID = entry.id
            } else if hoveredEntryID == entry.id {
                hoveredEntryID = nil
            }
        }
        .contextMenu {
            if state.isCubeMetricsSelectionMode {
                Button(state.localized("cube.metrics.cancel_selection")) {
                    state.cancelCubeMetricsSelection()
                }
            } else {
                Button(state.localized("library.context.copy_processing")) {
                    if let target = contextTargets.first {
                        state.copyProcessing(from: target)
                    }
                }
                .disabled(!canCopyFromSingle)
                
                if state.hasProcessingClipboard {
                    Button(state.localized("library.context.paste_processing")) {
                        for target in contextTargets {
                            state.pasteProcessing(to: target)
                        }
                    }
                }

                Divider()

                Button(state.localized("library.context.copy_wavelengths")) {
                    if let target = contextTargets.first {
                        state.copyWavelengths(from: target)
                    }
                }
                .disabled(!canCopyWavelengthsFromSingle)

                if state.hasWavelengthClipboard {
                    Button(state.localized("library.context.paste_wavelengths")) {
                        for target in contextTargets {
                            state.pasteWavelengths(to: target)
                        }
                    }
                }

                Divider()
                
                Button(state.localized("library.context.paste_point")) {
                    for target in contextTargets {
                        state.pasteSpectrumPoint(to: target)
                    }
                }
                .disabled(!canPastePoint)
                
                Button(state.localized("library.context.paste_area")) {
                    for target in contextTargets {
                        state.pasteSpectrumROI(to: target)
                    }
                }
                .disabled(!canPasteROI)

                Button(state.localized("library.context.copy_points_areas")) {
                    if let target = contextTargets.first {
                        state.copySpectrumSelections(from: target)
                    }
                }
                .disabled(!canCopySelectionsFromSingle)

                Button(state.localized("library.context.paste_points_areas")) {
                    for target in contextTargets {
                        state.pasteSpectrumSelections(to: target)
                    }
                }
                .disabled(!canPasteSelections)
                
                Divider()

                Button(state.localized("library.context.call_metrics")) {
                    if let source = contextTargets.first {
                        state.beginCubeMetricsSelection(from: source.id)
                    }
                }
                .disabled(!canCallMetrics)

                Divider()

                Button(state.localized("library.context.rename")) {
                    if let target = contextTargets.first {
                        startRename(for: target)
                    }
                }
                .disabled(!canRename)
                
                Divider()
                
                Button(role: .destructive) {
                    removeEntries(contextTargets)
                } label: {
                    Text(state.localized("library.context.remove_from_library"))
                }
            }
        }
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        var handled = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                if let url = object as? URL {
                    DispatchQueue.main.async {
                        state.addLibraryEntries(from: [url])
                    }
                }
            }
            handled = true
        }
        return handled
    }
    
    private func isEntryActive(_ entry: CubeLibraryEntry) -> Bool {
        guard let current = state.cubeURL?.standardizedFileURL.path else { return false }
        return current == entry.url.standardizedFileURL.path
    }
    
    private var cubeMetricsSelectionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(state.localized("cube.metrics.select_target_title"))
                .font(.system(size: 10, weight: .semibold))
            if let sourceName = state.cubeMetricsSelectionSourceDisplayName {
                Text(state.localizedFormat("cube.metrics.select_target_subtitle", sourceName))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            Button(state.localized("cube.metrics.cancel_selection")) {
                state.cancelCubeMetricsSelection()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.45), lineWidth: 1)
        )
    }

    private func backgroundColor(
        isActive: Bool,
        isSelected: Bool,
        isMetricsSource: Bool,
        isMetricsCandidate: Bool
    ) -> Color {
        if isMetricsSource {
            return Color.black.opacity(0.35)
        } else if isMetricsCandidate {
            return Color.accentColor.opacity(0.16)
        } else if isActive {
            return Color.accentColor.opacity(0.2)
        } else if isSelected {
            return Color(NSColor.selectedControlColor).opacity(0.3)
        } else {
            return Color(NSColor.controlBackgroundColor).opacity(0.2)
        }
    }
    
    private func borderColor(
        isActive: Bool,
        isSelected: Bool,
        isMetricsSource: Bool,
        isMetricsCandidate: Bool
    ) -> Color {
        if isMetricsSource {
            return Color.accentColor.opacity(0.7)
        } else if isMetricsCandidate {
            return Color.accentColor.opacity(0.8)
        } else if isActive {
            return Color.accentColor
        } else if isSelected {
            return Color(NSColor.selectedControlColor)
        } else {
            return Color(NSColor.separatorColor.withAlphaComponent(0.6))
        }
    }

    private func libraryStatsRow(for entry: CubeLibraryEntry) -> some View {
        let stats = state.libraryEntryStats(for: entry)
        return HStack(spacing: 10) {
            statsBadge(systemImage: "point.topleft.down.to.point.bottomright.curvepath", count: stats.points)
            statsBadge(systemImage: "rectangle.dashed", count: stats.roi)
            statsBadge(systemImage: "line.3.horizontal.decrease.circle", count: stats.pipelineOperations)
        }
    }
    
    private func statsBadge(systemImage: String, count: Int) -> some View {
        Label("\(count)", systemImage: systemImage)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
    }
    
    private func deleteSelectedEntries() {
        let entriesToDelete = state.libraryEntries.filter { selectedEntryIDs.contains($0.id) }
        removeEntries(entriesToDelete)
    }
    
    private func removeEntry(_ entry: CubeLibraryEntry) {
        removeEntries([entry])
    }
    
    private func removeEntries(_ entries: [CubeLibraryEntry]) {
        guard !entries.isEmpty else { return }
        for entry in entries {
            state.removeLibraryEntry(entry)
            selectedEntryIDs.remove(entry.id)
        }
    }
    
    private func startRename(for entry: CubeLibraryEntry) {
        renameTargetID = entry.id
        renameText = entry.displayName
        isRenaming = true
    }
    
    private func commitRename() {
        guard let targetID = renameTargetID else { return }
        state.renameLibraryEntry(id: targetID, to: renameText)
        isRenaming = false
        renameTargetID = nil
        renameText = ""
    }
    
    private func cancelRename() {
        isRenaming = false
        renameTargetID = nil
        renameText = ""
    }
    
    private func contextMenuTargets(for entry: CubeLibraryEntry) -> [CubeLibraryEntry] {
        if selectedEntryIDs.contains(entry.id) {
            let selected = state.libraryEntries.filter { selectedEntryIDs.contains($0.id) }
            return selected.isEmpty ? [entry] : selected
        } else {
            return [entry]
        }
    }
    
    private func selectSingleEntry(_ entry: CubeLibraryEntry) {
        selectedEntryIDs = [entry.id]
    }
    
    private func handleSelection(for entry: CubeLibraryEntry, isCommandPressed: Bool) {
        if isCommandPressed {
            if selectedEntryIDs.contains(entry.id) {
                selectedEntryIDs.remove(entry.id)
            } else {
                selectedEntryIDs.insert(entry.id)
            }
        } else {
            selectSingleEntry(entry)
        }
    }
    
    private func isCommandPressed() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        return event.modifierFlags.contains(.command)
    }
}

private struct CubeMetricsSheet: View {
    private enum MetricPanelID: String, CaseIterable, Hashable {
        case rmse
        case psnr
        case ssim
        case sam
    }

    let request: CubeMetricsRequest

    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var settings = CubeMetricsSettings()
    @State private var result: CubeMetricsResult?
    @State private var errorMessage: String?
    @State private var expandedPanels: Set<MetricPanelID> = Set(MetricPanelID.allCases)
    @State private var copiedPanel: MetricPanelID?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(state.localized("cube.metrics.sheet.title"))
                .font(.system(size: 20, weight: .semibold))

            Text(state.localizedFormat("cube.metrics.sheet.compare", request.reference.displayName, request.target.displayName))
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text(state.localizedFormat(
                "cube.metrics.sheet.signature",
                request.reference.signature.width,
                request.reference.signature.height,
                request.reference.signature.channels
            ))
            .font(.system(size: 11))
            .foregroundColor(.secondary)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    settingsSection(state.localized("cube.metrics.section.rmse")) {
                        Toggle(
                            state.localized("cube.metrics.per_channel"),
                            isOn: $settings.rmsePerChannelEnabled
                        )
                        .font(.system(size: 12))
                    }

                    settingsSection(state.localized("cube.metrics.section.psnr")) {
                        Toggle(
                            state.localized("cube.metrics.per_channel"),
                            isOn: $settings.psnrPerChannelEnabled
                        )
                        .font(.system(size: 12))

                        Picker(state.localized("cube.metrics.psnr.peak_mode"), selection: $settings.psnrPeakMode) {
                            ForEach(CubeMetricsPSNRPeakMode.allCases) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }

                        if settings.psnrPeakMode == .custom {
                            HStack {
                                Text(state.localized("cube.metrics.psnr.custom_value"))
                                    .font(.system(size: 12))
                                Spacer()
                                TextField("", value: $settings.psnrCustomPeak, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                            }
                        }
                    }

                    settingsSection(state.localized("cube.metrics.section.ssim")) {
                        Toggle(
                            state.localized("cube.metrics.per_channel"),
                            isOn: $settings.ssimPerChannelEnabled
                        )
                        .font(.system(size: 12))

                        Picker(state.localized("cube.metrics.ssim.range_mode"), selection: $settings.ssimRangeMode) {
                            ForEach(CubeMetricsSSIMRangeMode.allCases) { mode in
                                Text(mode.localizedTitle).tag(mode)
                            }
                        }

                        if settings.ssimRangeMode == .custom {
                            numericRow(
                                title: state.localized("cube.metrics.ssim.custom_range"),
                                value: $settings.ssimCustomRange
                            )
                        }

                        numericRow(
                            title: state.localized("cube.metrics.ssim.k1"),
                            value: $settings.ssimK1
                        )
                        numericRow(
                            title: state.localized("cube.metrics.ssim.k2"),
                            value: $settings.ssimK2
                        )
                    }

                    settingsSection(state.localized("cube.metrics.section.sam")) {
                        Toggle(
                            state.localized("cube.metrics.per_channel"),
                            isOn: $settings.samPerChannelEnabled
                        )
                        .font(.system(size: 12))

                        numericRow(
                            title: state.localized("cube.metrics.sam.epsilon"),
                            value: $settings.samEpsilon
                        )
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let result {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(state.localized("cube.metrics.result.title"))
                                .font(.system(size: 13, weight: .semibold))
                            Text(state.localizedFormat("cube.metrics.result.voxels", result.voxelCount))
                                .foregroundColor(.secondary)

                            metricResultPanel(
                                id: .rmse,
                                title: state.localized("cube.metrics.result.rmse"),
                                lines: metricResultLines(
                                    title: state.localized("cube.metrics.result.rmse"),
                                    summaryValue: result.rmse,
                                    perChannelValues: result.rmsePerChannel
                                )
                            )
                            metricResultPanel(
                                id: .psnr,
                                title: state.localized("cube.metrics.result.psnr"),
                                lines: metricResultLines(
                                    title: state.localized("cube.metrics.result.psnr"),
                                    summaryValue: result.psnr,
                                    perChannelValues: result.psnrPerChannel,
                                    extraLines: [
                                        "\(state.localized("cube.metrics.result.psnr_peak")): \(formattedMetricValue(result.psnrPeak))"
                                    ]
                                )
                            )
                            metricResultPanel(
                                id: .ssim,
                                title: state.localized("cube.metrics.result.ssim"),
                                lines: metricResultLines(
                                    title: state.localized("cube.metrics.result.ssim"),
                                    summaryValue: result.ssim,
                                    perChannelValues: result.ssimPerChannel
                                )
                            )
                            metricResultPanel(
                                id: .sam,
                                title: state.localized("cube.metrics.result.sam"),
                                lines: metricResultLines(
                                    title: state.localized("cube.metrics.result.sam"),
                                    summaryValue: result.samDegrees,
                                    perChannelValues: result.samPerChannelDegrees
                                )
                            )
                        }
                        .font(.system(size: 12))
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.55))
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                Spacer()
                Button(state.localized("common.cancel")) {
                    dismiss()
                }
                Button(state.localized("cube.metrics.calculate")) {
                    calculate()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(state.isBusy)
            }
        }
        .padding(18)
        .frame(minWidth: 560, minHeight: 560)
    }

    @ViewBuilder
    private func settingsSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }

    private func numericRow(title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private func metricResultLines(
        title: String,
        summaryValue: Double,
        perChannelValues: [Double]?,
        extraLines: [String] = []
    ) -> [String] {
        var lines: [String] = []
        if let perChannelValues {
            lines.append("\(title) (\(state.localized("cube.metrics.result.average"))): \(formattedMetricValue(summaryValue))")
            for (index, value) in perChannelValues.enumerated() {
                lines.append("\(state.localizedFormat("cube.metrics.result.channel", index + 1)): \(formattedMetricValue(value))")
            }
        } else {
            lines.append("\(title): \(formattedMetricValue(summaryValue))")
        }
        lines.append(contentsOf: extraLines)
        return lines
    }

    @ViewBuilder
    private func metricResultPanel(
        id: MetricPanelID,
        title: String,
        lines: [String]
    ) -> some View {
        let isExpanded = expandedPanels.contains(id)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    togglePanel(id)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.primary)
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button(copiedPanel == id ? state.localized("common.copied") : state.localized("cube.metrics.copy_panel")) {
                    copyMetricPanel(title: title, lines: lines, panelID: id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }

    private func togglePanel(_ id: MetricPanelID) {
        if expandedPanels.contains(id) {
            expandedPanels.remove(id)
        } else {
            expandedPanels.insert(id)
        }
    }

    private func copyMetricPanel(title: String, lines: [String], panelID: MetricPanelID) {
        let text = ([title] + lines).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedPanel = panelID
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedPanel == panelID {
                copiedPanel = nil
            }
        }
    }

    private func calculate() {
        errorMessage = nil
        result = nil

        state.calculateCubeMetrics(request: request, settings: settings) { outcome in
            switch outcome {
            case .success(let value):
                result = value
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }

    private func formattedMetricValue(_ value: Double) -> String {
        if value.isInfinite {
            return state.localized("cube.metrics.value.infinity")
        }
        if value.isNaN {
            return "NaN"
        }
        return String(format: "%.6f", value)
    }
}
