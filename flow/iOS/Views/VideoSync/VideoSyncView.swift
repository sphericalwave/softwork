//
//  VideoSyncView.swift
//  flow
//
//  Full-screen clock + QR code for syncing heart rate to GoPro video. Film this
//  screen for a couple of seconds; youtube-uploader's hr-overlay.swift reads
//  the QR to line up the video timeline with the Health samples.
//

import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

struct VideoSyncView: View {
    private let context = CIContext()

    var body: some View {
        TimelineView(.animation) { timeline in
            VStack(spacing: 24) {
                if let qr = qrImage(for: timeline.date) {
                    Image(decorative: qr, scale: 1)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
                Text(timeline.date, format: .dateTime.hour().minute().second().secondFraction(.fractional(2)))
                    .font(.system(size: 44, weight: .bold, design: .monospaced))
                Text("Hold up to the camera for 2–3 seconds before starting your workout.")
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .foregroundStyle(.black)
        .background(.white)
        .navigationTitle("GoPro Sync")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    /// QR payload `FLOWSYNC:<unix epoch milliseconds>`, low error correction
    /// so modules stay large and readable from across a room.
    private func qrImage(for date: Date) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data("FLOWSYNC:\(Int64(date.timeIntervalSince1970 * 1000))".utf8)
        filter.correctionLevel = "L"
        guard let output = filter.outputImage else { return nil }
        return context.createCGImage(output, from: output.extent)
    }
}
