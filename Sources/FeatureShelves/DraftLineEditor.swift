import LarderCore
import LarderDesign
import SwiftUI

/// Editable fields for one pending line: name, quantity, unit, location and an optional best-by date.
struct DraftLineEditor: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Binding var line: DraftLine
    let defaultBestBy: Date
    let onRemove: () -> Void

    private var hasBestBy: Binding<Bool> {
        Binding(
            get: { line.bestBy != nil },
            set: { line.bestBy = $0 ? defaultBestBy : nil }
        )
    }

    private var bestByDate: Binding<Date> {
        Binding(get: { line.bestBy ?? defaultBestBy }, set: { line.bestBy = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            HStack {
                TextField(ShelvesCopy.name, text: $line.name)
                    .font(LarderFont.body(.body, weight: .semibold))
                Button(action: onRemove) {
                    Label(ShelvesCopy.removeLine, systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(LarderColor.ink.secondary)
            }
            amountFields
            Picker(ShelvesCopy.location, selection: $line.location) {
                ForEach(StorageLocation.allCases, id: \.self) { location in
                    Text(ShelvesCopy.name(of: location)).tag(location)
                }
            }
            Toggle(ShelvesCopy.bestBy, isOn: hasBestBy)
            if line.bestBy != nil {
                DatePicker(ShelvesCopy.bestBy, selection: bestByDate, displayedComponents: .date)
            }
        }
        .padding(.vertical, LarderSpacing.xs)
        .accessibilityElement(children: .contain)
    }

    private var amountFields: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: LarderSpacing.s))
            : AnyLayout(HStackLayout(spacing: LarderSpacing.m))
        return layout {
            TextField(ShelvesCopy.quantity, value: $line.quantity, format: .number)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
            Picker(ShelvesCopy.unit, selection: $line.unit) {
                ForEach(UnitOfMeasure.allCases, id: \.self) { unit in
                    Text(ShelvesCopy.name(of: unit)).tag(unit)
                }
            }
        }
    }
}

#if DEBUG
#Preview("DraftLineEditor") {
    @Previewable @State var line = DraftLine(
        name: "Rice", quantity: 2, unit: .cup, location: .pantry, bestBy: .now.addingTimeInterval(86_400 * 30)
    )
    Form {
        DraftLineEditor(line: $line, defaultBestBy: .now) {}
    }
    .larderList()
}
#endif
