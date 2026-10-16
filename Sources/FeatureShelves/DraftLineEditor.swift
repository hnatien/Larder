import LarderCore
import LarderDesign
import SwiftUI

/// One pending line as a compact card: the name, then a wrapping row of menus for the amount, where it is kept and
/// an optional best-by date.
struct DraftLineEditor: View {
    @Binding var line: DraftLine
    let defaultBestBy: Date
    let onRemove: () -> Void
    @State private var isPickingDate = false

    /// Picking a day in the calendar sets it and closes the calendar.
    private var bestByDate: Binding<Date> {
        Binding(
            get: { line.bestBy ?? defaultBestBy },
            set: {
                line.bestBy = $0
                isPickingDate = false
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LarderSpacing.s) {
            HStack(spacing: LarderSpacing.s) {
                TextField(ShelvesCopy.name, text: $line.name, axis: .vertical)
                    .font(LarderFont.body(.body, weight: .semibold))
                    .foregroundStyle(LarderColor.ink.primary)
                Button(action: onRemove) {
                    Label(ShelvesCopy.removeLine, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .font(LarderFont.body(.subheadline, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(LarderColor.ink.secondary)
            }
            ChipFlow {
                amountField
                locationMenu
                bestByMenu
            }
        }
        .padding(.vertical, LarderSpacing.s)
        .accessibilityElement(children: .contain)
        .swipeActions(edge: .trailing) {
            Button(ShelvesCopy.removeLine, systemImage: "trash", role: .destructive, action: onRemove)
        }
    }

    /// The quantity and its unit read together, as in "2 piece".
    private var amountField: some View {
        HStack(spacing: LarderSpacing.xs) {
            // Sized by the number it shows rather than by its title, so the capsule hugs the amount.
            Text(line.quantity, format: .number)
                .padding(.horizontal, LarderSpacing.xxs)
                .frame(minWidth: LarderSpacing.l)
                .hidden()
                .overlay {
                    TextField(ShelvesCopy.quantity, value: $line.quantity, format: .number)
                        #if os(iOS)
                        .keyboardType(.decimalPad)
                        #endif
                        .multilineTextAlignment(.center)
                        .foregroundStyle(LarderColor.ink.primary)
                }
                .font(LarderFont.body(.subheadline, weight: .semibold))
            Menu {
                Picker(ShelvesCopy.unit, selection: $line.unit) {
                    ForEach(UnitOfMeasure.allCases, id: \.self) { unit in
                        Text(ShelvesCopy.name(of: unit)).tag(unit)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                MenuText(ShelvesCopy.name(of: line.unit))
            }
            .accessibilityLabel(ShelvesCopy.unit)
            .accessibilityValue(ShelvesCopy.name(of: line.unit))
        }
        .modifier(FieldCapsule())
    }

    private var locationMenu: some View {
        Menu {
            Picker(ShelvesCopy.location, selection: $line.location) {
                ForEach(StorageLocation.allCases, id: \.self) { location in
                    Label(ShelvesCopy.name(of: location), systemImage: ShelvesView.symbol(for: location)).tag(location)
                }
            }
            .pickerStyle(.inline)
        } label: {
            MenuText(ShelvesCopy.name(of: line.location), systemImage: ShelvesView.symbol(for: line.location))
                .modifier(FieldCapsule())
        }
        .accessibilityLabel(ShelvesCopy.location)
        .accessibilityValue(ShelvesCopy.name(of: line.location))
    }

    private var bestByMenu: some View {
        Menu {
            ForEach(BestByChoice.allCases, id: \.self) { choice in
                Button(choice.title) { line.bestBy = choice.date(from: defaultBestBy) }
            }
            Button(ShelvesCopy.chooseDate, systemImage: "calendar") { isPickingDate = true }
            if line.bestBy != nil {
                Divider()
                Button(ShelvesCopy.noDate, systemImage: "xmark", role: .destructive) { line.bestBy = nil }
            }
        } label: {
            MenuText(
                line.bestBy.map { $0.formatted(.dateTime.day().month(.abbreviated)) } ?? ShelvesCopy.bestBy,
                systemImage: "calendar",
                isPlaceholder: line.bestBy == nil
            )
            .modifier(FieldCapsule())
        }
        .accessibilityLabel(ShelvesCopy.bestBy)
        .accessibilityValue(line.bestBy.map { $0.formatted(date: .long, time: .omitted) } ?? ShelvesCopy.noDate)
        .popover(isPresented: $isPickingDate) {
            DatePicker(ShelvesCopy.bestBy, selection: bestByDate, in: defaultBestBy..., displayedComponents: .date)
                .datePickerStyle(.graphical)
                .tint(LarderColor.accent.brand)
                .padding(LarderSpacing.m)
                .frame(minWidth: 320)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// Quick best-by dates, counted from today.
private enum BestByChoice: CaseIterable {
    case threeDays, week, twoWeeks, month

    var title: String {
        switch self {
        case .threeDays: ShelvesCopy.inThreeDays
        case .week: ShelvesCopy.inAWeek
        case .twoWeeks: ShelvesCopy.inTwoWeeks
        case .month: ShelvesCopy.inAMonth
        }
    }

    func date(from today: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .threeDays: calendar.date(byAdding: .day, value: 3, to: today)
        case .week: calendar.date(byAdding: .day, value: 7, to: today)
        case .twoWeeks: calendar.date(byAdding: .day, value: 14, to: today)
        case .month: calendar.date(byAdding: .month, value: 1, to: today)
        }
    }
}

/// A menu's current value with an optional icon and the up-down chevron that says it opens a choice.
private struct MenuText: View {
    let text: String
    var systemImage: String?
    var isPlaceholder = false

    init(_ text: String, systemImage: String? = nil, isPlaceholder: Bool = false) {
        self.text = text
        self.systemImage = systemImage
        self.isPlaceholder = isPlaceholder
    }

    var body: some View {
        HStack(spacing: LarderSpacing.xs) {
            if let systemImage {
                Image(systemName: systemImage)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Image(systemName: "chevron.up.chevron.down")
                .font(LarderFont.body(.caption2, weight: .semibold))
                .accessibilityHidden(true)
        }
        .font(LarderFont.body(.subheadline, weight: isPlaceholder ? .regular : .semibold))
        .foregroundStyle(isPlaceholder ? LarderColor.ink.secondary : LarderColor.ink.primary)
    }
}

/// The sunken capsule every field on the line sits in, at least 44 points tall.
private struct FieldCapsule: ViewModifier {
    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, LarderSpacing.s + LarderSpacing.xxs)
            .padding(.vertical, LarderSpacing.s)
            .frame(minHeight: 44)
            .background(LarderColor.surface.sunken, in: Capsule())
            .overlay {
                Capsule().strokeBorder(LarderColor.line.hairline, lineWidth: 1 / displayScale)
            }
            .contentShape(Capsule())
    }
}

#if DEBUG
#Preview("DraftLineEditor") {
    @Previewable @State var lines = [
        DraftLine(name: "Chicken breasts", quantity: 2, unit: .piece, location: .fridge),
        DraftLine(name: "Rice", quantity: 2, unit: .cup, location: .pantry, bestBy: .now.addingTimeInterval(86_400 * 30)),
    ]
    Form {
        ForEach($lines) { $line in
            DraftLineEditor(line: $line, defaultBestBy: .now) {}
        }
    }
    .larderList()
}
#endif
