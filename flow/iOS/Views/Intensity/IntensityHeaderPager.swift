//
//  IntensityHeaderPager.swift
//  flow
//
//  Swipeable header for Intensity, styled after fitWrench's Food dash pager:
//  page 0 = peak workout heart rate, page 1 = average workout heart rate,
//  both per D/W/M period. The charts aren't selectable so a drag swipes pages.
//

import SwiftUI
import SwCharts

struct IntensityHeaderPager: View {
    @ObservedObject var viewModel: DashboardViewModel
    let period: ChartPeriod
    @AppStorage("intensityHeaderPage") private var page = 0

    /// Natural height of a chart page, measured from a hidden copy so the
    /// card hugs its content at every text size.
    @State private var measuredHeight: CGFloat?
    /// Used only until the first measurement lands.
    @ScaledMetric(relativeTo: .body) private var fallbackHeight: CGFloat = 230
    private var cardHeight: CGFloat { measuredHeight ?? fallbackHeight }

    private let pageNames = ["Peak heart rate", "Average heart rate"]

    var body: some View {
        VStack(spacing: 4) {
            TabView(selection: $page) {
                peakChart
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(0)
                averageChart
                    .frame(maxHeight: .infinity, alignment: .top)
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: cardHeight)
            .background { pageSizer }
            .padding(14)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            pageDots
        }
    }

    private var peakChart: some View {
        PeriodChartView(title: pageNames[0],
                        samples: viewModel.peakHRSamples,
                        period: period,
                        aggregation: .max,
                        valueLabel: Self.bpm,
                        selectable: false)
    }

    private var averageChart: some View {
        PeriodChartView(title: pageNames[1],
                        samples: viewModel.averageHRSamples,
                        period: period,
                        aggregation: .average,
                        valueLabel: Self.bpm,
                        selectable: false)
    }

    private static func bpm(_ value: Double) -> String {
        "\(Int(value.rounded())) bpm"
    }

    /// Layout-only copy of a page at its ideal height; never shown or tappable.
    private var pageSizer: some View {
        peakChart
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                measuredHeight = $0.rounded(.up)
            }
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(pageNames.indices, id: \.self) { i in
                Button {
                    withAnimation { page = i }
                } label: {
                    Circle()
                        .fill(Color.primary.opacity(page == i ? 0.85 : 0.28))
                        .frame(width: 9, height: 9)
                        .frame(width: 32, height: 16)
                        // A 32pt-tall tap target without spending 32pt of layout.
                        .contentShape(Rectangle().size(width: 32, height: 32).offset(y: -8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pageNames[i])
                .accessibilityValue(page == i ? "Showing" : "")
                .accessibilityHint("Page \(i + 1) of \(pageNames.count)")
            }
        }
    }
}
