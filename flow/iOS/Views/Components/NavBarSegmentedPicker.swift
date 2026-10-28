//
//  NavBarSegmentedPicker.swift
//  flow
//
//  Solid segmented control for the branded nav bar. iOS 26 draws toolbar
//  items on Liquid Glass, and light glass over the blue NavBar image washes
//  the stock segmented control out to pale-on-pale. This draws its own opaque
//  capsule instead (the suite's house style: white letters on dark navy, the
//  selected segment a white capsule); pair it with
//  `.sharedBackgroundVisibility(.hidden)` on the ToolbarItem.
//

import SwiftUI
import SwCharts

/// Dark navy from the NavBar image's rim, so white labels read at well
/// over 4.5:1 and the selected segment's navy letters do too.
private let navBarControlFill = Color(red: 0x0E / 255, green: 0x1B / 255, blue: 0x5C / 255)

struct NavBarSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [Value]
    let label: (Value) -> String
    let accessibilityLabel: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let selected = option == selection
                Button { selection = option } label: {
                    Text(label(option))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(selected ? navBarControlFill : .white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            if selected { Capsule().fill(.white) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(option))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        // Sized like SwCharts' PeriodPicker (72pt segments).
        .frame(width: PeriodPicker.width, height: 40)
        .background(navBarControlFill, in: Capsule())
        .animation(.snappy(duration: 0.2), value: selection)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

extension NavBarSegmentedPicker where Value == ChartPeriod {
    /// Drop-in for SwCharts' `PeriodPicker` in the nav bar.
    init(selection: Binding<ChartPeriod>) {
        self.init(selection: selection,
                  options: Array(ChartPeriod.allCases),
                  label: \.short,
                  accessibilityLabel: { $0.rawValue.capitalized })
    }
}
