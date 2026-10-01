//
//  RootView.swift
//  flow
//
//  macOS root: sidebar + detail. Coach features (camp planning, feedback,
//  dashboards) land here from M8 onward.
//

import SwiftUI

struct RootView: View {
    enum SidebarItem: String, CaseIterable, Identifiable {
        case camps = "Camps"
        var id: String { rawValue }
        var systemImage: String {
            switch self {
            case .camps: return "calendar"
            }
        }
    }

    @AppStorage("flowSelectedSection") private var selection: SidebarItem = .camps

    var body: some View {
        NavigationSplitView {
            List(SidebarItem.allCases, selection: Binding(
                get: { selection },
                set: { if let new = $0 { selection = new } }
            )) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            switch selection {
            case .camps:
                ContentUnavailableView(
                    "No Camps Yet",
                    systemImage: "calendar",
                    description: Text("Plan a fight camp here. Live sparring runs on iPhone.")
                )
            }
        }
    }
}
