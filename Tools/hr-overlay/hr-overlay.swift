#!/usr/bin/env swift
//
//  hr-overlay.swift
//
//  Burns a heart-rate overlay (zone-colored heart, bpm, % HR max) into a video,
//  e.g. a merged GoPro session, ready to upload to YouTube.
//
//  Heart rate comes from flow: Intensity → long-press workout → Export Heart Rate.
//
//  Sync, in order of preference:
//    1. QR (automatic): film flow's Settings → GoPro Sync Clock near the start of
//       the recording. The first 3 minutes are scanned for it.
//    2. --sync VIDEO=CLOCK: a moment in the video and the wall-clock time it
//       happened. CLOCK is "start" (first HR sample, i.e. when the workout
//       started), "HH:MM:SS[.fff]" local time, or full ISO 8601.
//         --sync 1:12=start          workout started 1m12s into the video
//         --sync 0:07.4=14:03:22.5
//    --offset SEC nudges either: positive shows heart rate from later.
//  --hrmax BPM sets HR max (default 191, the measured max; flow's exported value is ignored).
//
//  Usage:
//    swift hr-overlay.swift <video> <hr.csv> [--sync V=C] [--offset SEC]
//                           [--preview VIDEOTIME [--length DURATION]] [--out FILE]
//  --preview renders 20 s (or --length) from VIDEOTIME to check sync and look.
//  --chart-interval SEC redraws the session HR chart every SEC (default 30).
//
//  Needs ffmpeg/ffprobe (brew install ffmpeg).
//

import Foundation
import Vision
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - Process helpers

@discardableResult
func run(_ tool: String, _ args: [String], quiet: Bool = true) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [tool] + args
    let pipe = Pipe()
    process.standardOutput = pipe
    if quiet { process.standardError = FileHandle.nullDevice }
    do { try process.run() } catch { fail("Couldn't run \(tool): \(error.localizedDescription)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    if process.terminationStatus != 0 { fail("\(tool) failed (exit \(process.terminationStatus)).") }
    return String(decoding: data, as: UTF8.self)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Parsing

/// "7.4", "1:12", "00:01:12.5" → seconds.
func parseVideoTime(_ text: String) -> Double? {
    var total = 0.0
    for part in text.split(separator: ":") {
        guard let value = Double(part) else { return nil }
        total = total * 60 + value
    }
    return total
}

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func parseISO(_ text: String) -> Date? {
    if let date = isoFormatter.date(from: text) { return date }
    return ISO8601DateFormatter().date(from: text)
}

struct Sample { let time: Date; let bpm: Int }

func loadCSV(_ path: String) -> (samples: [Sample], hrMax: Int) {
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { fail("Can't read \(path)") }
    var samples: [Sample] = []
    var hrMax = 0
    for line in text.split(whereSeparator: \.isNewline).dropFirst() {
        let cols = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard cols.count >= 3, let time = parseISO(cols[0]), let bpm = Int(cols[1]), let max = Int(cols[2]) else { continue }
        samples.append(Sample(time: time, bpm: bpm))
        hrMax = max
    }
    guard !samples.isEmpty, hrMax > 0 else { fail("No heart-rate rows in \(path) (expected timestamp,bpm,hrmax).") }
    return (samples.sorted { $0.time < $1.time }, hrMax)
}

// MARK: - Arguments

var positional: [String] = []
var syncArg: String?
var offsetNudge = 0.0
var previewAt: Double?
var previewLength = 20.0
/// Measured max (191 bpm on 2026-10-08), used over the CSV's age-based estimate.
var hrMaxOverride: Int? = 191
var chartInterval = 30.0
var outPath: String?

var argv = CommandLine.arguments.dropFirst().makeIterator()
while let arg = argv.next() {
    switch arg {
    case "--sync": syncArg = argv.next()
    case "--offset":
        guard let value = argv.next().flatMap(Double.init) else { fail("--offset needs seconds, e.g. --offset -1.5") }
        offsetNudge = value
    case "--preview":
        guard let value = argv.next().flatMap(parseVideoTime) else { fail("--preview needs a video time, e.g. --preview 5:30") }
        previewAt = value
    case "--length":
        guard let value = argv.next().flatMap(parseVideoTime) else { fail("--length needs a duration, e.g. --length 5:00") }
        previewLength = value
    case "--hrmax":
        guard let value = argv.next().flatMap(Int.init), value > 0 else { fail("--hrmax needs bpm, e.g. --hrmax 191") }
        hrMaxOverride = value
    case "--chart-interval":
        guard let value = argv.next().flatMap(Double.init), value > 0 else { fail("--chart-interval needs seconds, e.g. 30") }
        chartInterval = value
    case "--out": outPath = argv.next()
    case "-h", "--help":
        print("usage: swift hr-overlay.swift <video> <hr.csv> [--sync VIDEO=CLOCK] [--offset SEC] [--preview VIDEOTIME] [--out FILE]")
        exit(0)
    default: positional.append(arg)
    }
}
guard positional.count == 2 else { fail("usage: swift hr-overlay.swift <video> <hr.csv> [options] (see --help)") }
let videoPath = positional[0]
let (samples, csvHRMax) = loadCSV(positional[1])
let hrMax = hrMaxOverride ?? csvHRMax

// MARK: - Video info

let probe = run("ffprobe", ["-v", "error", "-select_streams", "v:0",
                            "-show_entries", "stream=width,height:format=duration:format_tags=creation_time",
                            "-of", "default=noprint_wrappers=1", videoPath])
var info: [String: String] = [:]
for line in probe.split(separator: "\n") {
    let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
    if kv.count == 2 { info[kv[0]] = kv[1] }
}
guard let width = info["width"].flatMap(Int.init), let height = info["height"].flatMap(Int.init),
      let duration = info["duration"].flatMap(Double.init) else { fail("Couldn't read video size/duration.") }

let clockFormatter = DateFormatter()
clockFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SS"
print("Video: \(width)x\(height), \(Int(duration / 60))m\(Int(duration) % 60)s, camera clock \(info["TAG:creation_time"] ?? "none")")
print("Heart rate: \(samples.count) samples, \(clockFormatter.string(from: samples.first!.time)) → \(clockFormatter.string(from: samples.last!.time)), HR max \(hrMax)")

// MARK: - Sync

/// Wall-clock time (epoch seconds) at video time zero.
func syncFromArgument(_ text: String) -> Double {
    let parts = text.split(separator: "=", maxSplits: 1).map(String.init)
    guard parts.count == 2, let videoTime = parseVideoTime(parts[0]) else { fail("--sync expects VIDEO=CLOCK, e.g. 1:12=start") }
    let clock: Date
    if parts[1] == "start" {
        clock = samples.first!.time
    } else if let iso = parseISO(parts[1]) {
        clock = iso
    } else if let secondsOfDay = parseVideoTime(parts[1]) {
        // Local time on the day the workout started.
        clock = Calendar.current.startOfDay(for: samples.first!.time).addingTimeInterval(secondsOfDay)
    } else {
        fail("Couldn't read clock time \"\(parts[1])\".")
    }
    return clock.timeIntervalSince1970 - videoTime
}

func syncFromQR() -> Double? {
    let scanSeconds = min(duration, 180)
    let framesPerSecond = 10.0
    print("Scanning first \(Int(scanSeconds))s for the flow sync QR…")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("hr-overlay-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    run("ffmpeg", ["-v", "error", "-t", String(scanSeconds), "-i", videoPath,
                   "-vf", "fps=\(Int(framesPerSecond)),scale=1280:-2", "-q:v", "3",
                   dir.appendingPathComponent("%05d.jpg").path])

    let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    var offsets: [Double] = []
    for file in files {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(url: dir.appendingPathComponent(file)).perform([request])
        for observation in request.results ?? [] {
            guard let payload = observation.payloadStringValue, payload.hasPrefix("FLOWSYNC:"),
                  let millis = Double(payload.dropFirst("FLOWSYNC:".count)),
                  let index = Double(file.prefix(5)) else { continue }
            let videoTime = (index - 1) / framesPerSecond
            offsets.append(millis / 1000 - videoTime)
        }
    }
    guard !offsets.isEmpty else { return nil }
    let sorted = offsets.sorted()
    let median = sorted[sorted.count / 2]
    print(String(format: "Found sync QR in %d frames (spread %.2fs).", offsets.count, sorted.last! - sorted.first!))
    return median
}

guard var videoZero = syncArg.map(syncFromArgument) ?? syncFromQR() else {
    fail("""
        No sync QR found. Pass a sync point instead, e.g.
          --sync 1:12=start        (the moment you started the workout is at 1:12 in the video)
          --sync 0:07=14:03:22     (video 0:07 happened at 14:03:22 local time)
        Then check with --preview <video time> and fine-tune with --offset.
        """)
}
videoZero += offsetNudge
print("Video 0:00 = \(clockFormatter.string(from: Date(timeIntervalSince1970: videoZero)))")

let firstAt = samples.first!.time.timeIntervalSince1970 - videoZero
let lastAt = samples.last!.time.timeIntervalSince1970 - videoZero
let covered = max(0, min(lastAt, duration) - max(firstAt, 0))
print(String(format: "Heart rate covers video %.0fs → %.0fs (%.0f%% of the video).", firstAt, lastAt, covered / duration * 100))
if covered <= 0 { fail("Heart rate doesn't overlap the video with this sync — check --sync/--offset.") }

// MARK: - Overlay (ASS subtitles)

/// Zone label and color, matching flow's HRZone + ZoneUI (gray/blue/green/yellow/orange/red);
/// colors as ASS &HBBGGRR.
func zone(percent: Double) -> (label: String, color: String) {
    switch percent {
    case ..<50: return ("Z0 Rest", "&H938E8E&")
    case ..<60: return ("Z1 Recovery", "&HFF840A&")
    case ..<70: return ("Z2 Endurance", "&H58D130&")
    case ..<80: return ("Z3 Tempo", "&H0AD6FF&")
    case ..<90: return ("Z4 Threshold", "&H0A9FFF&")
    default:    return ("Z5 Max", "&H3A45FF&")
    }
}

func assTime(_ seconds: Double) -> String {
    let cs = Int((max(seconds, 0) * 100).rounded())
    return String(format: "%d:%02d:%02d.%02d", cs / 360000, cs / 6000 % 60, cs / 100 % 60, cs % 100)
}

let fontSize = Double(height) * 0.04
let margin = Double(height) * 0.045
let heartScale = Int(fontSize * 0.75)   // heart path is 100 units wide → % scale
let heartPath = "m 50 30 b 50 10 20 0 10 20 b 0 40 30 60 50 90 b 70 60 100 40 90 20 b 80 0 50 10 50 30"
let maxGap = 30.0   // like ZoneBucketer: hide the overlay across sensor dropouts
let shift = previewAt ?? 0

var ass = """
    [Script Info]
    ScriptType: v4.00+
    PlayResX: \(width)
    PlayResY: \(height)
    WrapStyle: 2
    ScaledBorderAndShadow: yes

    [V4+ Styles]
    Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
    Style: HR,AvenirNext-Bold,\(Int(fontSize)),&H00FFFFFF,&H00FFFFFF,&H00000000,&H80000000,0,0,0,0,100,100,0,0,1,0,0,1,0,0,0,1

    [Events]
    Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text

    """
for (i, sample) in samples.enumerated() {
    let start = sample.time.timeIntervalSince1970 - videoZero - shift
    let nextTime = i + 1 < samples.count ? samples[i + 1].time.timeIntervalSince1970 - videoZero - shift : start + 5
    let end = min(nextTime, start + maxGap)
    guard end > 0, start < duration - shift else { continue }
    let percent = Double(sample.bpm) / Double(hrMax) * 100
    let (label, color) = zone(percent: percent)
    // Top-left stack, largest first: % HR max, bpm, zone.
    let text = "{\\an7\\pos(\(Int(margin)),\(Int(margin)))}"
        + "{\\c\(color)\\fscx\(heartScale)\\fscy\(heartScale)\\p1}\(heartPath){\\p0\\fscx100\\fscy100} "
        + "\(Int(percent.rounded()))%{\\fs\(Int(fontSize * 0.5))} max"
        + "\\N{\\fs\(Int(fontSize * 0.62))\\c&HFFFFFF&}\(sample.bpm){\\fs\(Int(fontSize * 0.42))} bpm"
        + "\\N{\\fs\(Int(fontSize * 0.45))\\c\(color)}\(label)"
    ass += "Dialogue: 0,\(assTime(start)),\(assTime(end)),HR,,0,0,0,,\(text)\n"
}

// MARK: - Render

let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("hr-overlay-ass-\(UUID().uuidString)")
try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: workDir) }
let assFile = workDir.appendingPathComponent("hr.ass")
do { try ass.write(to: assFile, atomically: true, encoding: .utf8) } catch { fail("Couldn't write overlay: \(error)") }

let videoURL = URL(fileURLWithPath: videoPath)
let output = outPath ?? videoURL.deletingPathExtension().path + (previewAt == nil ? "-hr.mp4" : "-hr-preview.mp4")
// Frosted "ultra-thin material" card behind the stats: the video under it,
// blurred, lightly darkened and clipped to a rounded rect. Sized for the
// widest content ("100% max", "Z4 Threshold"); dimensions even for 4:2:0.
func even(_ value: Double) -> Int { Int(value / 2) * 2 }
let pad = fontSize * 0.4
let cardX = even(margin - pad), cardY = even(margin - pad)
let cardW = even(fontSize * 5.2), cardH = even(fontSize * 2.75)
let radius = Int(fontSize * 0.4)

// Session HR chart in the card's lower right, beside bpm + zone: zone bands
// (Z1–Z5) with the HR line, x spanning the whole video and filling in as it
// plays. Redrawn every chartInterval seconds as a PNG sequence.
let chartX = even(margin + fontSize * 2.4), chartY = even(margin + fontSize * 1.15)
let chartW = even(Double(cardX + cardW) - pad - Double(chartX)), chartH = even(fontSize * 0.95)
let chartDir = workDir.appendingPathComponent("chart")
try? FileManager.default.createDirectory(at: chartDir, withIntermediateDirectories: true)
let videoSamples = samples.map { (t: $0.time.timeIntervalSince1970 - videoZero, pct: Double($0.bpm) / Double(hrMax) * 100) }
let renderLength = previewAt == nil ? duration : min(previewLength, duration - shift)

func writeChart(upTo videoTime: Double, to url: URL) {
    guard let ctx = CGContext(data: nil, width: chartW, height: chartH, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
    let w = Double(chartW), h = Double(chartH)
    let lo = 40.0, hi = 105.0
    func y(_ pct: Double) -> Double { (min(max(pct, lo), hi) - lo) / (hi - lo) * h }
    ctx.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                       cornerWidth: fontSize * 0.08, cornerHeight: fontSize * 0.08, transform: nil))
    ctx.clip()
    // Zone bands, flow's colors at low alpha so the frosted card shows through.
    let bands: [(Double, Double, (Double, Double, Double))] = [
        (50, 60, (0.04, 0.52, 1.0)), (60, 70, (0.19, 0.82, 0.35)), (70, 80, (1.0, 0.84, 0.04)),
        (80, 90, (1.0, 0.62, 0.04)), (90, hi, (1.0, 0.27, 0.23)),
    ]
    for (from, to, c) in bands {
        ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 0.38))
        ctx.fill(CGRect(x: 0, y: y(from), width: w, height: y(to) - y(from)))
    }
    let points = videoSamples.filter { $0.t >= 0 && $0.t <= videoTime }
    guard points.count > 1 else { writePNG(ctx, url); return }
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(max(1.5, fontSize * 0.035))
    ctx.setLineJoin(.round)
    ctx.beginPath()
    for (i, p) in points.enumerated() {
        let pt = CGPoint(x: p.t / duration * w, y: y(p.pct))
        if i == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
    }
    ctx.strokePath()
    writePNG(ctx, url)
}

func writePNG(_ ctx: CGContext, _ url: URL) {
    guard let image = ctx.makeImage(),
          let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// Frame i shows HR up to (output time i × interval) and holds until the next.
let chartFrames = Int(renderLength / chartInterval) + 1
for i in 0..<chartFrames {
    writeChart(upTo: shift + Double(i) * chartInterval,
               to: chartDir.appendingPathComponent(String(format: "%05d.png", i)))
}
let mask = "color=c=black:s=\(cardW)x\(cardH),format=gray,"
    + "geq=lum='255*clip(\(radius)+0.5-hypot(X-clip(X,\(radius),W-1-\(radius)),Y-clip(Y,\(radius),H-1-\(radius))),0,1)'"
let filter = "[0:v]split[base][src];"
    + "[src]crop=\(cardW):\(cardH):\(cardX):\(cardY),gblur=sigma=\(Int(fontSize * 0.3)),"
    + "drawbox=c=black@0.25:t=fill,format=yuva420p[frost];"
    + "[frost][1:v]alphamerge[card];"
    + "[base][card]overlay=\(cardX):\(cardY):shortest=1[carded];"
    + "[carded][2:v]overlay=\(chartX):\(chartY):eof_action=repeat,ass=\(assFile.path)[out]"

var ffmpegArgs = ["-hide_banner", "-loglevel", "warning", "-stats", "-y"]
if let previewAt { ffmpegArgs += ["-ss", String(previewAt), "-t", String(previewLength)] }
ffmpegArgs += ["-i", videoPath, "-f", "lavfi", "-i", mask,
               "-framerate", "1/\(chartInterval)", "-i", chartDir.appendingPathComponent("%05d.png").path,
               "-filter_complex", filter,
               "-map", "[out]", "-map", "0:a:0?", "-shortest",
               "-c:v", "hevc_videotoolbox", "-q:v", "65", "-tag:v", "hvc1",
               "-c:a", "copy", "-movflags", "+faststart", output]
print("Rendering \(output)…")
run("ffmpeg", ffmpegArgs, quiet: false)
print("Done: \(output)")
