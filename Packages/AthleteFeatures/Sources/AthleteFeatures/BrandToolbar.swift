//
//  BrandToolbar.swift
//  AthleteFeatures
//
//  The sphericalwave suite nav bar: the app's `NavBar` imageset (main
//  bundle) behind a transparent bar, white inline title and buttons. Lives
//  here so the app's tabs and this package's screens share one look.
//

#if os(iOS)
import SwiftUI

extension View {
    /// Apply to the root content of every screen that shows a nav bar,
    /// pushed destinations included — never to the TabView.
    ///
    /// UIKit appearance images are ignored by iOS 26 Liquid Glass bars and get
    /// overwritten by SwiftUI's own toolbar background, so instead the bar is made
    /// transparent and the image is drawn in SwiftUI across the top safe area
    /// (status bar + nav bar), above the scrolling content but under the bar items.
    public func brandedToolbars() -> some View {
        self
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .overlay(alignment: .top) {
                GeometryReader { proxy in
                    Image("NavBar")
                        .resizable()
                        .frame(width: proxy.size.width, height: proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
    }
}
#endif
