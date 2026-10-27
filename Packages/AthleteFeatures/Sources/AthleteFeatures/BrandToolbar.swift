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
    ///
    /// The overlay is sized by the view it's attached to, so the view is made
    /// to fill the screen first: a ScrollView whose only content is narrow
    /// (e.g. a loading spinner) otherwise hugs it and the image draws as a
    /// centred block instead of spanning the bar.
    public func brandedToolbars() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
