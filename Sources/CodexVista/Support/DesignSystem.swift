import AppKit
import SwiftUI

struct CodexVistaPalette {
    let background: UInt32
    let surface: UInt32
    let raised: UInt32
    let control: UInt32
    let border: UInt32
    let primary: UInt32
    let muted: UInt32
    let accent: UInt32
    let secondary: UInt32
    let cached: UInt32
    let output: UInt32
    let reasoning: UInt32
    let grid: UInt32
    let selected: UInt32
    let selectedText: UInt32
    let heatText: UInt32
    let action: UInt32

    static func resolve(skin: AppSkinPreference, dark: Bool) -> Self {
        switch (skin, dark) {
        case (.standard, false): standardLight
        case (.standard, true): standardDark
        case (.ink, _): inkLight
        case (.celadon, false): celadonLight
        case (.celadon, true): celadonDark
        case (.dusk, false): duskLight
        case (.dusk, true): duskDark
        case (.cyber, _): cyberDark
        case (.xianxia, _): xianxiaLight
        }
    }

    private static let standardLight = Self(
        background: 0xE9EDF0,
        surface: 0xF2F5F7,
        raised: 0xFFFFFF,
        control: 0xE2E8ED,
        border: 0xCAD3DB,
        primary: 0x263440,
        muted: 0x566876,
        accent: 0x2147A7,
        secondary: 0x2A657E,
        cached: 0x963C86,
        output: 0xA65316,
        reasoning: 0x16705A,
        grid: 0xD8E0E7,
        selected: 0xFFFFFF,
        selectedText: 0x2147A7,
        heatText: 0xFFFFFF,
        action: 0x2147A7
    )

    private static let standardDark = Self(
        background: 0x19212A,
        surface: 0x202B36,
        raised: 0x283542,
        control: 0x303E4C,
        border: 0x425264,
        primary: 0xEDF3F8,
        muted: 0xACBDCC,
        accent: 0x9BBCFF,
        secondary: 0x8AC6DA,
        cached: 0xEC91D3,
        output: 0xFFBD78,
        reasoning: 0x65D9AB,
        grid: 0x354454,
        selected: 0x405268,
        selectedText: 0xF0F5FF,
        heatText: 0x182430,
        action: 0x274FAE
    )

    private static let inkLight = Self(
        background: 0xECEDE8,
        surface: 0xF2F3EE,
        raised: 0xFAFAF5,
        control: 0xE4E7E1,
        border: 0xD2D7D1,
        primary: 0x303B40,
        muted: 0x5B686A,
        accent: 0x3B4850,
        secondary: 0x557373,
        cached: 0x365FA0,
        output: 0xAE3E30,
        reasoning: 0x777020,
        grid: 0xD8DDD7,
        selected: 0xFAFAF5,
        selectedText: 0xA33F3B,
        heatText: 0xFFFFFF,
        action: 0x3B4850
    )
    private static let celadonLight = Self(
        background: 0xE5EFEB,
        surface: 0xF0F6F2,
        raised: 0xFAFCF8,
        control: 0xD8E6DF,
        border: 0xB7CEC2,
        primary: 0x203E36,
        muted: 0x47645B,
        accent: 0x21664F,
        secondary: 0x426B87,
        cached: 0x8540A0,
        output: 0xAC4D25,
        reasoning: 0x275FAD,
        grid: 0xD1E1D8,
        selected: 0xFAFCF8,
        selectedText: 0x21664F,
        heatText: 0xFFFFFF,
        action: 0x21664F
    )

    private static let celadonDark = Self(
        background: 0x142C28,
        surface: 0x1B3630,
        raised: 0x23433B,
        control: 0x2B4D43,
        border: 0x456A5C,
        primary: 0xE6F4EB,
        muted: 0xAAC9B9,
        accent: 0x8BD1AE,
        secondary: 0x9BC9DD,
        cached: 0xDE9EF5,
        output: 0xFFB27C,
        reasoning: 0x8CBFFF,
        grid: 0x34594C,
        selected: 0x355D4E,
        selectedText: 0xC0ECD3,
        heatText: 0x152F25,
        action: 0x275B46
    )

    private static let duskLight = Self(
        background: 0xF1E6E3,
        surface: 0xF8F0EB,
        raised: 0xFFFAF4,
        control: 0xEADAD4,
        border: 0xD6B9B0,
        primary: 0x4B323A,
        muted: 0x775660,
        accent: 0xA14960,
        secondary: 0x936139,
        cached: 0x4C54AC,
        output: 0x965B12,
        reasoning: 0x146D60,
        grid: 0xE8D3CC,
        selected: 0xFFFAF4,
        selectedText: 0x963D55,
        heatText: 0xFFFFFF,
        action: 0x963D55
    )

    private static let duskDark = Self(
        background: 0x302128,
        surface: 0x3B2A32,
        raised: 0x49343D,
        control: 0x55404A,
        border: 0x775766,
        primary: 0xF9EAF0,
        muted: 0xD9B8C4,
        accent: 0xEBA3B8,
        secondary: 0xE9B38B,
        cached: 0xAEB3FF,
        output: 0xFFD17C,
        reasoning: 0x66DCC1,
        grid: 0x624653,
        selected: 0x704656,
        selectedText: 0xFBE0E8,
        heatText: 0x38222B,
        action: 0x8E3B52
    )

    private static let cyberDark = Self(
        background: 0x10191C,
        surface: 0x17262B,
        raised: 0x1D3036,
        control: 0x294149,
        border: 0x3D626A,
        primary: 0xE3F6F6,
        muted: 0xA5C4C9,
        accent: 0x65DCD3,
        secondary: 0x83BCEC,
        cached: 0xD696FF,
        output: 0xFFAC69,
        reasoning: 0xC8E86B,
        grid: 0x2C4D54,
        selected: 0x31515A,
        selectedText: 0xA3F6EC,
        heatText: 0x122629,
        action: 0x235F60
    )

    private static let xianxiaLight = Self(
        background: 0xEFF3F3,
        surface: 0xF7FAF9,
        raised: 0xFCFDFC,
        control: 0xE2EAE9,
        border: 0xCEDBD8,
        primary: 0x263F44,
        muted: 0x50676A,
        accent: 0x356B70,
        secondary: 0x876C39,
        cached: 0x8047A4,
        output: 0xAD4B26,
        reasoning: 0x82700D,
        grid: 0xDEE8E5,
        selected: 0xFCFDFC,
        selectedText: 0x356B70,
        heatText: 0xFFFFFF,
        action: 0x356B70
    )
}

enum CodexVistaTheme {
    static var accent: Color { color(\.accent) }
    static var accentBlue: Color { color(\.secondary) }
    static var popoverPrimary: Color { color(\.accent) }
    static var popoverSecondary: Color { color(\.secondary) }
    static var output: Color { color(\.output) }
    static var reasoning: Color { color(\.reasoning) }
    static var dashboardBackground: Color { color(\.background) }
    static var dashboardSurface: Color { color(\.surface) }
    static var dashboardSurfaceOpaque: Color { color(\.surface) }
    static var dashboardSurfaceStrong: Color { color(\.raised) }
    static var dashboardTile: Color { color(\.raised) }
    static var dashboardControlBackground: Color { color(\.control) }
    static var dashboardBorder: Color { color(\.border) }
    static var dashboardPrimaryText: Color { color(\.primary) }
    static var dashboardMutedText: Color { color(\.muted) }
    static var dashboardGrid: Color { color(\.grid) }
    static var dashboardAccent: Color { color(\.accent) }
    static var dashboardAccentSecondary: Color { color(\.secondary) }
    static var dashboardInput: Color { color(\.accent) }
    static var dashboardCachedInput: Color { color(\.cached) }
    static var selectionSurface: Color { color(\.selected) }
    static var selectionText: Color { color(\.selectedText) }
    static var heatmapText: Color { color(\.heatText) }
    static var cinnabar: Color { color(\.selectedText) }
    static var dashboardShadow: Color { Color.black.opacity((isInk || skin == .xianxia) ? 0.025 : 0.06) }
    static var skin: AppSkinPreference { AppSkinPreference.load() }
    static var isInk: Bool { skin == .ink }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [color(\.action), color(\.action)], startPoint: .top, endPoint: .bottom)
    }

    static func headingFont(size: CGFloat, skin: AppSkinPreference = skin) -> Font {
        (skin == .ink || skin == .xianxia) ? .custom("Songti SC", size: size).weight(.semibold) : .system(size: size, weight: .semibold)
    }

    static func metricFont(size: CGFloat, skin: AppSkinPreference = skin) -> Font {
        switch skin {
        case .ink: .system(size: size, weight: .semibold, design: .serif)
        case .xianxia: .system(size: size, weight: .medium)
        case .celadon, .dusk: .system(size: size, weight: .semibold, design: .rounded)
        case .standard: .custom("DINAlternate-Bold", size: size)
        case .cyber: .system(size: size, weight: .medium, design: .monospaced)
        }
    }

    static func cornerRadius(_ radius: CGFloat, skin: AppSkinPreference = skin) -> CGFloat {
        switch skin {
        case .ink: radius * 0.5
        case .standard: radius * 0.72
        case .celadon: radius * 1.15
        case .dusk: radius
        case .cyber: radius * 0.25
        case .xianxia: radius * 0.85
        }
    }

    static func swatch(_ hex: UInt32) -> Color { Color(nsColor: nsColor(hex)) }

    private static func color(_ key: KeyPath<CodexVistaPalette, UInt32>) -> Color {
        let skin = AppSkinPreference.load()
        let light = CodexVistaPalette.resolve(skin: skin, dark: false)[keyPath: key]
        let dark = CodexVistaPalette.resolve(skin: skin, dark: true)[keyPath: key]
        return Color(nsColor: NSColor(name: nil) { appearance in
            nsColor(appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light)
        })
    }

    private static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
}

struct CodexVistaBackdrop: View {
    var body: some View {
        CodexVistaTheme.dashboardBackground
            .overlay {
                if CodexVistaTheme.isInk { CodexVistaPaperGrain() }
            }
            .ignoresSafeArea()
    }
}

/// Deterministic fibers, drawn once per update; no images, timers, or random flicker.
struct CodexVistaPaperGrain: View {
    var body: some View {
        Canvas { context, size in
            var fibers = Path()
            let count = min(1_200, Int(size.width * size.height / 650))
            for index in 0..<max(0, count) {
                let x = CGFloat((index * 137 + 29) % 1009) / 1009 * size.width
                let y = CGFloat((index * 193 + 71) % 1013) / 1013 * size.height
                fibers.move(to: CGPoint(x: x, y: y))
                fibers.addLine(to: CGPoint(x: x + CGFloat(index % 4 + 1), y: y + 0.6))
            }
            context.stroke(fibers, with: .color(CodexVistaTheme.dashboardAccent.opacity(0.032)), lineWidth: 0.45)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}


/// A horizontal landscape with its own reserved space below the quota controls.
struct CodexVistaInkPainting: View {
    var body: some View {
        Canvas { context, size in
            let ink = CodexVistaTheme.dashboardAccent
            func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: x * size.width, y: y * size.height)
            }
            // Distant, broad washes and a darker near bank leave the river mostly blank.
            let ridges: [[CGPoint]] = [
                [point(0, 0.44), point(0.09, 0.30), point(0.18, 0.40), point(0.28, 0.10),
                 point(0.35, 0.24), point(0.44, 0.46), point(0.52, 0.60)],
                [point(0.56, 0.72), point(0.67, 0.58), point(0.73, 0.41), point(0.79, 0.47),
                 point(0.86, 0.30), point(0.94, 0.56), point(1, 0.54)],
                [point(0, 0.61), point(0.07, 0.49), point(0.13, 0.55), point(0.2, 0.38),
                 point(0.29, 0.60), point(0.36, 0.77)]
            ]
            for (layer, ridge) in ridges.enumerated() {
                var mountain = Path()
                mountain.move(to: ridge[0])
                for index in 1..<ridge.count {
                    let previous = ridge[index - 1]
                    let current = ridge[index]
                    mountain.addQuadCurve(to: CGPoint(x: (previous.x + current.x) / 2,
                                                      y: (previous.y + current.y) / 2), control: previous)
                }
                let last = ridge[ridge.count - 1]
                mountain.addLine(to: last)
                mountain.addLine(to: CGPoint(x: last.x, y: size.height))
                mountain.addLine(to: CGPoint(x: ridge[0].x, y: size.height))
                mountain.closeSubpath()
                context.fill(mountain, with: .linearGradient(
                    Gradient(colors: [ink.opacity(layer == 2 ? 0.30 : 0.14), ink.opacity(0)]),
                    startPoint: point(0, layer == 2 ? 0.38 : 0.16), endPoint: point(0, 1)
                ))
                var wash = context
                wash.clip(to: mountain)
                for index in 0..<10 {
                    let x = CGFloat((index * 23 + layer * 7) % 100) / 100
                    var crease = Path()
                    crease.move(to: point(x, 0.3))
                    crease.addQuadCurve(to: point(x - 0.06, 0.88), control: point(x + 0.02, 0.57))
                    wash.stroke(crease, with: .color(ink.opacity(0.025)), lineWidth: 0.5)
                }
            }

            // One small boat establishes scale; the river remains clear around it.
            var boat = Path()
            boat.move(to: point(0.53, 0.77))
            boat.addQuadCurve(to: point(0.65, 0.74), control: point(0.60, 0.87))
            boat.addQuadCurve(to: point(0.53, 0.77), control: point(0.59, 0.80))
            context.fill(boat, with: .color(ink.opacity(0.62)))
            var person = Path()
            person.move(to: point(0.59, 0.77))
            person.addQuadCurve(to: point(0.585, 0.63), control: point(0.57, 0.71))
            person.move(to: point(0.585, 0.68))
            person.addLine(to: point(0.62, 0.73))
            person.move(to: point(0.61, 0.69))
            person.addLine(to: point(0.66, 0.87))
            context.stroke(person, with: .color(ink.opacity(0.65)), style: StrokeStyle(lineWidth: 0.7, lineCap: .round))
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.581, y: size.height * 0.58, width: 2, height: 2)),
                         with: .color(ink.opacity(0.65)))
            var ripple = Path()
            ripple.move(to: point(0.49, 0.91))
            ripple.addQuadCurve(to: point(0.68, 0.89), control: point(0.58, 0.92))
            context.stroke(ripple, with: .color(ink.opacity(0.16)), lineWidth: 0.5)
            // Two distant birds, with no extra foreground ornament competing with the seal.
            for (x, y, wing) in [(0.69, 0.15, 0.013), (0.76, 0.24, 0.010)] {
                var bird = Path()
                bird.move(to: point(x - wing, y))
                bird.addQuadCurve(to: point(x, y + 0.035), control: point(x - wing * 0.3, y))
                bird.addQuadCurve(to: point(x + wing, y - 0.01), control: point(x + wing * 0.4, y - 0.008))
                context.stroke(bird, with: .color(ink.opacity(0.42)), lineWidth: 0.6)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaSword: Shape {
    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var sword = Path()
        sword.addLines([
            point(0.5, 0), point(0.65, 0.025), point(0.59, 0.055),
            point(0.59, 0.23), point(0.86, 0.215), point(1, 0.25),
            point(0.7, 0.275), point(0.63, 0.3), point(0.61, 0.87),
            point(0.5, 1), point(0.39, 0.87), point(0.37, 0.3),
            point(0.3, 0.275), point(0, 0.25), point(0.14, 0.215),
            point(0.41, 0.23), point(0.41, 0.055), point(0.35, 0.025)
        ])
        sword.closeSubpath()
        return sword
    }
}

/// A single vertical composition, kept separate from quota text and reset controls.
struct CodexVistaXianxiaScene: View {
    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 104, size.height / 156)
            context.translateBy(x: (size.width - 104 * scale) / 2, y: (size.height - 156 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let jade = CodexVistaTheme.dashboardAccent
            let gold = CodexVistaTheme.dashboardAccentSecondary
            let moon = Path(ellipseIn: CGRect(x: 21, y: 12, width: 62, height: 62))
            context.fill(moon, with: .color(CodexVistaTheme.dashboardTile))
            context.stroke(moon, with: .color(gold.opacity(0.3)), lineWidth: 0.7)

            // Layered ridgelines share one horizon; the lower edges dissolve into mist.
            for layer in 0..<3 {
                let offset = CGFloat(layer) * 13
                var ridge = Path()
                ridge.move(to: CGPoint(x: 0, y: 108 + offset))
                ridge.addLines([
                    CGPoint(x: 12, y: 98 + offset), CGPoint(x: 23, y: 76 + offset),
                    CGPoint(x: 32, y: 89 + offset), CGPoint(x: 43, y: 86 + offset),
                    CGPoint(x: 61, y: 108 + offset), CGPoint(x: 76, y: 90 + offset),
                    CGPoint(x: 87, y: 96 + offset), CGPoint(x: 104, y: 113 + offset),
                    CGPoint(x: 104, y: 156), CGPoint(x: 0, y: 156)
                ])
                ridge.closeSubpath()
                context.fill(ridge, with: .linearGradient(
                    Gradient(colors: [jade.opacity(0.09 + Double(layer) * 0.04), jade.opacity(0)]),
                    startPoint: CGPoint(x: 52, y: 80 + offset), endPoint: CGPoint(x: 52, y: 156)
                ))
            }

            let swordRect = CGRect(x: 39, y: 21, width: 26, height: 115)
            let sword = CodexVistaSword().path(in: swordRect)
            context.fill(sword, with: .linearGradient(
                Gradient(colors: [jade.opacity(0.8), jade.opacity(0.14)]),
                startPoint: CGPoint(x: 49, y: 21), endPoint: CGPoint(x: 56, y: 136)
            ))
            context.stroke(sword, with: .color(jade.opacity(0.72)), lineWidth: 0.65)
            var fuller = Path()
            fuller.move(to: CGPoint(x: 52, y: 57))
            fuller.addLine(to: CGPoint(x: 52, y: 130))
            context.stroke(fuller, with: .color(CodexVistaTheme.dashboardTile), lineWidth: 0.75)
            var guardLine = Path()
            guardLine.addLines([CGPoint(x: 40, y: 49), CGPoint(x: 52, y: 52), CGPoint(x: 64, y: 49)])
            context.stroke(guardLine, with: .color(gold), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            for index in 0..<4 {
                var grip = Path()
                let y = 30 + CGFloat(index) * 4
                grip.move(to: CGPoint(x: 50, y: y))
                grip.addLine(to: CGPoint(x: 54, y: y + 1))
                context.stroke(grip, with: .color(gold.opacity(0.85)), lineWidth: 0.9)
            }
            var cord = Path()
            cord.move(to: CGPoint(x: 53, y: 24))
            cord.addCurve(to: CGPoint(x: 76, y: 67),
                          control1: CGPoint(x: 86, y: 20), control2: CGPoint(x: 58, y: 49))
            context.stroke(cord, with: .color(gold.opacity(0.75)), lineWidth: 0.8)
            var tassel = Path()
            tassel.addLines([CGPoint(x: 76, y: 65), CGPoint(x: 73, y: 77), CGPoint(x: 79, y: 77)])
            tassel.closeSubpath()
            context.fill(tassel, with: .color(gold.opacity(0.55)))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaXianxiaQuota: View {
    let quotas: [QuotaSnapshot]

    var body: some View {
        HStack(spacing: 20) {
            CodexVistaXianxiaScene()
                .frame(width: 92, height: 156)
            VStack(alignment: .leading, spacing: 16) {
                ForEach(quotas) { quota in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(quota.compactTitle) · 剩余额度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(quota.remainingPercent)")
                                .font(.system(size: quotas.count > 1 ? 30 : 46, weight: .light))
                            Text("%")
                                .font(.system(size: 16, weight: .regular))
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        }
                        .monospacedDigit()
                        GeometryReader { geometry in
                            let fraction = quota.remaining.isFinite ? min(1, max(0, quota.remaining)) : 0
                            Capsule().fill(CodexVistaTheme.dashboardControlBackground)
                            Capsule().fill(CodexVistaTheme.dashboardAccent)
                                .frame(width: geometry.size.width * fraction)
                        }
                        .frame(height: 3)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(quota.remainingLabel)
                }
            }
            .frame(width: 116, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct CodexVistaSkinMotif: View {
    let skin: AppSkinPreference

    var body: some View {
        Canvas { context, size in
            let accent = CodexVistaTheme.dashboardAccent
            switch skin {
            case .celadon:
                // Concentric glaze rings, like a shallow porcelain bowl.
                for index in 0..<5 {
                    let inset = CGFloat(index) * 16
                    let ellipse = CGRect(x: inset, y: 12 + CGFloat(index) * 5,
                                         width: max(0, size.width - inset * 2), height: 36 - CGFloat(index) * 6)
                    context.stroke(Path(ellipseIn: ellipse), with: .color(accent.opacity(0.05 + Double(index) * 0.018)), lineWidth: 0.7)
                }
            case .dusk:
                // A low sun and warm horizontal reflections.
                let center = CGPoint(x: size.width * 0.72, y: 35)
                var sun = Path()
                sun.addArc(center: center, radius: 22, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
                sun.closeSubpath()
                context.fill(sun, with: .linearGradient(
                    Gradient(colors: [CodexVistaTheme.dashboardAccentSecondary.opacity(0.2), accent.opacity(0.04)]),
                    startPoint: CGPoint(x: center.x, y: 10), endPoint: center
                ))
                for index in 0..<4 {
                    var horizon = Path()
                    let inset = CGFloat(index) * 19
                    horizon.move(to: CGPoint(x: 15 + inset, y: 36 + CGFloat(index) * 6))
                    horizon.addLine(to: CGPoint(x: size.width - 8 - inset, y: 36 + CGFloat(index) * 6))
                    context.stroke(horizon, with: .color(accent.opacity(0.12 - Double(index) * 0.022)), lineWidth: 0.7)
                }
            case .cyber:
                for row in 0..<3 {
                    let y = 12 + CGFloat(row) * 14
                    var circuit = Path()
                    circuit.move(to: CGPoint(x: 12, y: y))
                    circuit.addLine(to: CGPoint(x: size.width * 0.35, y: y))
                    circuit.addLine(to: CGPoint(x: size.width * 0.42, y: y - 8))
                    circuit.addLine(to: CGPoint(x: size.width - 15 - CGFloat(row) * 20, y: y - 8))
                    context.stroke(circuit, with: .color(accent.opacity(0.09)), lineWidth: 0.6)
                    context.stroke(Path(CGRect(x: size.width - 18 - CGFloat(row) * 20, y: y - 11, width: 6, height: 6)),
                                   with: .color(accent.opacity(0.22)), lineWidth: 0.6)
                }
            case .standard, .ink, .xianxia:
                break
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaDialTicks: View {
    let remaining: Double

    var body: some View {
        Canvas { context, size in
            let radius = min(size.width, size.height) / 2
            let fraction = remaining.isFinite ? min(1, max(0, remaining)) : 0
            for index in 0..<20 {
                let angle = Double(index) / 20 * .pi * 2 - .pi / 2
                let length: CGFloat = index.isMultiple(of: 5) ? 6 : 3
                var tick = Path()
                tick.move(to: CGPoint(x: radius + cos(angle) * (radius - length), y: radius + sin(angle) * (radius - length)))
                tick.addLine(to: CGPoint(x: radius + cos(angle) * radius, y: radius + sin(angle) * radius))
                context.stroke(tick, with: .color(Double(index) / 20 < fraction
                    ? CodexVistaTheme.dashboardAccent.opacity(0.7)
                    : CodexVistaTheme.dashboardMutedText.opacity(0.3)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct CodexVistaCyberQuota: View {
    let quota: QuotaSnapshot
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(quota.compactTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(CodexVistaTheme.dashboardAccent)
                Spacer()
                Text("\(quota.remainingPercent)%")
                    .font(CodexVistaTheme.metricFont(size: compact ? 27 : 40))
                    .monospacedDigit()
            }
            Canvas { context, size in
                let fraction = quota.remaining.isFinite ? min(1, max(0, quota.remaining)) : 0
                let step = size.width / 24
                var segments = Path()
                for index in 0..<24 {
                    segments.addRect(CGRect(x: CGFloat(index) * step, y: 1, width: max(0, step - 2), height: size.height - 2))
                }
                context.fill(segments, with: .color(CodexVistaTheme.dashboardControlBackground))
                context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width * fraction, height: size.height)))
                context.fill(segments, with: .color(CodexVistaTheme.dashboardAccent))
            }
            .frame(height: compact ? 10 : 16)
            HStack {
                Text("剩余额度")
                Spacer()
                Text("100%")
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
        }
        .padding(.vertical, compact ? 3 : 18)
        .frame(width: 214)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }
}

struct CodexVistaInkQuota: View {
    let quota: QuotaSnapshot
    let compact: Bool

    var body: some View {
        VStack(spacing: compact ? 3 : 6) {
            Text("\(quota.title) · 剩余额度")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(quota.remainingPercent)")
                    .font(.system(size: compact ? 28 : 44, weight: .regular, design: .serif))
                Text("%")
                    .font(.system(size: compact ? 13 : 18, weight: .regular, design: .serif))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .monospacedDigit()
            Canvas { context, size in
                let fraction = quota.remaining.isFinite ? min(1, max(0, quota.remaining)) : 0
                context.fill(Path(CGRect(x: 0, y: 3, width: size.width, height: 2)),
                             with: .color(CodexVistaTheme.dashboardControlBackground))
                let width = size.width * fraction
                guard width > 0 else { return }
                // A restrained, tapered stroke; its width still represents the exact quota.
                var brush = Path()
                brush.addLines([
                    CGPoint(x: 0, y: 1.5), CGPoint(x: width * 0.18, y: 1), CGPoint(x: width * 0.52, y: 1.6),
                    CGPoint(x: width * 0.87, y: 1.2), CGPoint(x: width, y: 2.3),
                    CGPoint(x: width, y: 5.8), CGPoint(x: width * 0.65, y: 6.3),
                    CGPoint(x: width * 0.28, y: 5.7), CGPoint(x: 0, y: 6)
                ])
                brush.closeSubpath()
                context.fill(brush, with: .color(CodexVistaTheme.dashboardAccent))
                var dryBrush = Path()
                dryBrush.move(to: CGPoint(x: width * 0.13, y: 3.7))
                dryBrush.addLine(to: CGPoint(x: width * 0.78, y: 3.3))
                context.stroke(dryBrush, with: .color(CodexVistaTheme.dashboardTile.opacity(0.25)), lineWidth: 0.4)
            }
            .frame(height: 8)
            .padding(.top, compact ? 0 : 4)
        }
        .padding(.horizontal, 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quota.remainingLabel)
    }
}

/// The sample is illustrative; typography, geometry and colors use the same theme tokens as the dashboard.
struct CodexVistaSkinPreview: View {
    let skin: AppSkinPreference
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    private var schemeLabel: String {
        switch skin.fixedColorScheme {
        case .light: "仅浅色"
        case .dark: "仅深色"
        default: "浅色 / 深色"
        }
    }

    var body: some View {
        let palette = CodexVistaPalette.resolve(skin: skin, dark: colorScheme == .dark)
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    previewGauge(palette)
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("剩余额度")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(CodexVistaTheme.swatch(palette.muted))
                        Text("68%")
                            .font(CodexVistaTheme.metricFont(size: 26, skin: skin))
                            .monospacedDigit()
                    }
                    Spacer(minLength: 0)
                    VStack(spacing: 5) {
                        ForEach([palette.accent, palette.cached, palette.output, palette.reasoning], id: \.self) { color in
                            Capsule().fill(CodexVistaTheme.swatch(color))
                                .frame(width: 16, height: 4)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, minHeight: 76)
                .background(CodexVistaTheme.swatch(palette.raised), in: RoundedRectangle(
                    cornerRadius: CodexVistaTheme.cornerRadius(10, skin: skin), style: .continuous
                ))
                .accessibilityHidden(true)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(skin.title)
                        .font(CodexVistaTheme.headingFont(size: 13, skin: skin))
                    Text(schemeLabel)
                        .font(.system(size: 10))
                        .foregroundStyle(CodexVistaTheme.swatch(palette.muted))
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CodexVistaTheme.swatch(isSelected ? palette.selectedText : palette.muted))
                }
                Text(skin.detail)
                    .font(.system(size: 11))
                    .foregroundStyle(CodexVistaTheme.swatch(palette.muted))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .foregroundStyle(CodexVistaTheme.swatch(palette.primary))
            .background(CodexVistaTheme.swatch(palette.background), in: shape)
            .overlay {
                shape.strokeBorder(
                    CodexVistaTheme.swatch(isSelected || isHovered ? palette.selectedText : palette.border),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .overlay {
                if isFocused {
                    shape.inset(by: -3)
                        .stroke(CodexVistaTheme.swatch(palette.selectedText), lineWidth: 2)
                }
            }
        }
        .buttonStyle(CodexVistaControlStyle())
        .focused($isFocused)
        .onHover { isHovered = $0 }
        .help("\(skin.detail)，\(schemeLabel)；额度为示例")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(skin.title)皮肤，\(skin.detail)，\(schemeLabel)")
        .accessibilityValue(isSelected ? "已选中" : "未选中")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private func previewGauge(_ palette: CodexVistaPalette) -> some View {
        let accent = CodexVistaTheme.swatch(palette.accent)
        switch skin {
        case .ink:
            Text("墨")
                .font(.custom("Songti SC", size: 26).weight(.medium))
                .foregroundStyle(CodexVistaTheme.swatch(palette.selectedText))
                .frame(width: 32, height: 38)
                .overlay {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(CodexVistaTheme.swatch(palette.selectedText), lineWidth: 1)
                }
        case .xianxia:
            ZStack {
                Circle().stroke(CodexVistaTheme.swatch(palette.secondary).opacity(0.5), lineWidth: 0.75)
                CodexVistaSword().fill(accent).frame(width: 16, height: 42)
            }
        case .cyber:
            HStack(spacing: 3) {
                ForEach(0..<8) { index in
                    Rectangle()
                        .fill(index < 5 ? accent : CodexVistaTheme.swatch(palette.control))
                }
            }
            .frame(height: 25)
        case .standard, .celadon, .dusk:
            ZStack {
                Circle().stroke(CodexVistaTheme.swatch(palette.control), lineWidth: 4)
                Circle().trim(from: 0, to: 0.68)
                    .stroke(accent, style: StrokeStyle(lineWidth: skin == .dusk ? 3 : 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                if skin == .celadon || skin == .dusk {
                    Image(systemName: skin == .celadon ? "water.waves" : "sun.horizon")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(accent)
                }
            }
            .padding(3)
        }
    }
}

struct CodexVistaInkSeal: View {
    var body: some View {
        Text("墨")
            .font(.custom("Songti SC", size: 12).weight(.bold))
            .foregroundStyle(CodexVistaTheme.cinnabar)
            .frame(width: 18, height: 22)
            .overlay {
                RoundedRectangle(cornerRadius: 2)
                    .strokeBorder(CodexVistaTheme.cinnabar.opacity(0.8), lineWidth: 1)
                    .padding(1)
            }
            .accessibilityHidden(true)
    }
}

/// Immediate press feedback for frequently used controls, including keyboard input.
/// No implicit animation delays selection or ignores the reduced-motion preference.
struct CodexVistaControlStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(isEnabled ? (configuration.isPressed ? 0.78 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
    }
}

struct CodexVistaAppearanceContainer<Content: View>: View {
    @AppStorage(AppPreferenceKeys.colorScheme)
    private var colorSchemeRaw = AppColorSchemePreference.system.rawValue
    @AppStorage(AppPreferenceKeys.skin)
    private var skinRaw = AppSkinPreference.standard.rawValue
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            // Recreate local presentation on a skin change so all static palette users,
            // including native popovers, pick up the new palette together.
            .id(AppSkinPreference.resolved(from: skinRaw))
            .preferredColorScheme(
                AppSkinPreference.resolved(from: skinRaw).effectiveColorScheme(
                    for: AppColorSchemePreference.resolved(from: colorSchemeRaw)
                )
            )
            .tint(CodexVistaTheme.accent)
    }
}

struct CodexVistaVisualEffect: NSViewRepresentable {
    enum Style {
        case window
        case popover
    }

    let style: Style

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = style == .window ? .underWindowBackground : .popover
        view.blendingMode = style == .window ? .behindWindow : .withinWindow
        view.state = .active
        view.isEmphasized = true
    }
}

enum CodexVistaGlassEmphasis {
    case standard
    case strong
}

struct CodexVistaGlassGroup<Content: View>: View {
    let spacing: CGFloat?
    private let content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

// Keep the shared surface API so popovers, settings, and details use the same palette.
// Data surfaces are opaque: desktop wallpaper must not alter chart/text contrast.
struct CodexVistaGlassSurface: ViewModifier {
    let padding: CGFloat
    let cornerRadius: CGFloat
    let emphasis: CodexVistaGlassEmphasis
    let shadowOpacity: Double

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(cornerRadius), style: .continuous)
        content
            .padding(padding)
            .background {
                shape.fill(
                    emphasis == .strong
                        ? CodexVistaTheme.dashboardSurfaceStrong
                        : CodexVistaTheme.dashboardSurface
                )
                .overlay {
                    if CodexVistaTheme.isInk {
                        CodexVistaPaperGrain().clipShape(shape)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(CodexVistaTheme.dashboardBorder, lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: CodexVistaTheme.dashboardShadow.opacity(shadowOpacity),
                radius: 8,
                y: 2
            )
    }
}

struct CodexVistaMetricSurface: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodexVistaTheme.cornerRadius(12), style: .continuous)
        content
            .background(CodexVistaTheme.isInk ? Color.clear : CodexVistaTheme.dashboardSurface, in: shape)
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(CodexVistaTheme.dashboardMutedText, lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }
}

extension View {
    func dashboardCard(padding: CGFloat = 18) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: 16,
            emphasis: .standard,
            shadowOpacity: 0.62
        ))
    }

    func dashboardPanel(
        padding: CGFloat = 16,
        cornerRadius: CGFloat = 16,
        strong: Bool = false
    ) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: cornerRadius,
            emphasis: strong ? .strong : .standard,
            shadowOpacity: 0.72
        ))
    }

    func codexVistaGlassSurface(
        padding: CGFloat = 0,
        cornerRadius: CGFloat = 12,
        strong: Bool = false,
        shadowOpacity: Double = 0.58
    ) -> some View {
        modifier(CodexVistaGlassSurface(
            padding: padding,
            cornerRadius: cornerRadius,
            emphasis: strong ? .strong : .standard,
            shadowOpacity: shadowOpacity
        ))
    }
}


/// Shared presentation for the four non-overlapping Token categories.
struct TokenCompositionView: View {
    let breakdown: TokenBreakdown?
    var total: Int? = nil
    var compact = false
    var showsBar = true

    private var segments: [TokenCompositionSegment] {
        TokenCompositionSegment.make(breakdown: breakdown, total: total)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 14) {
            if showsBar {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            let width = max(0, geometry.size.width) * segment.share
                            segment.color
                                .frame(width: width)
                                .overlay(alignment: .leading) {
                                    // Separate broad neighbors without hiding genuinely tiny segments.
                                    if index > 0, width >= 4,
                                       geometry.size.width * segments[index - 1].share >= 4 {
                                        Rectangle()
                                            .fill(CodexVistaTheme.dashboardSurfaceStrong)
                                            .frame(width: 1)
                                    }
                                }
                        }
                    }
                    .frame(width: max(0, geometry.size.width), alignment: .leading)
                    .background(CodexVistaTheme.dashboardControlBackground)
                    .clipShape(Capsule())
                }
                .frame(height: compact ? 7 : 9)
                .accessibilityHidden(true)
            }

            Grid(horizontalSpacing: compact ? 14 : 20, verticalSpacing: compact ? 7 : 10) {
                GridRow {
                    TokenCompositionMetric(segment: segments[0], compact: compact)
                    TokenCompositionMetric(segment: segments[1], compact: compact)
                }
                Rectangle()
                    .fill(CodexVistaTheme.dashboardBorder.opacity(0.6))
                    .frame(height: 1)
                    .gridCellColumns(2)
                    .gridCellUnsizedAxes(.horizontal)
                    .accessibilityHidden(true)
                GridRow {
                    TokenCompositionMetric(segment: segments[2], compact: compact)
                    TokenCompositionMetric(segment: segments[3], compact: compact)
                }
            }
        }
    }
}

struct TokenCompositionSegment: Identifiable {
    let id: String
    let title: String
    let value: Int?
    let share: Double
    let color: Color

    var valueText: String { value.map(TokenFormatter.compact) ?? "—" }
    var shareText: String { value == nil ? "—" : TokenFormatter.percentage(share) }
    var accessibilityText: String {
        guard let value else { return "\(title)，暂无数据" }
        return "\(title)，\(value.formatted()) Token，占比 \(shareText)"
    }

    static func make(breakdown: TokenBreakdown?, total: Int? = nil) -> [Self] {
        let denominator = total ?? breakdown?.total ?? 0
        let entries: [(String, String, Int?, Color)] = [
            ("input", "未缓存输入", breakdown?.input, CodexVistaTheme.dashboardInput),
            ("cached", "缓存输入", breakdown?.cachedInput, CodexVistaTheme.dashboardCachedInput),
            ("output", "可见输出", breakdown?.output, CodexVistaTheme.output),
            ("reasoning", "推理输出", breakdown?.reasoning, CodexVistaTheme.reasoning)
        ]
        return entries.map { id, title, value, color in
            Self(id: id, title: title, value: value,
                 share: denominator > 0 ? min(max(Double(value ?? 0) / Double(denominator), 0), 1) : 0,
                 color: color)
        }
    }
}

struct TokenCompositionMetric: View {
    let segment: TokenCompositionSegment
    var compact = false
    var stacksPercentage = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 3 : 5) {
            HStack(spacing: 6) {
                Circle().fill(segment.color).frame(width: 6, height: 6)
                Text(segment.title)
                    .font(.system(size: compact ? 9.5 : 10, weight: .medium))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                    .lineLimit(1)
            }
            let valueLayout = stacksPercentage
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
            valueLayout {
                Text(segment.valueText)
                    .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardPrimaryText)
                if !stacksPercentage { Spacer(minLength: 0) }
                Text(segment.shareText)
                    .font(.system(size: compact ? 9 : 10, weight: .medium, design: .rounded))
                    .foregroundStyle(CodexVistaTheme.dashboardMutedText)
            }
            .monospacedDigit()
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .help(segment.accessibilityText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segment.accessibilityText)
    }
}

struct TokenCompositionCostTable: View {
    let breakdown: TokenBreakdown
    let costs: ModelCostBreakdown
    var total: Int? = nil
    var pricing: ModelPricingRule? = nil

    private var amounts: [Double] {
        [costs.uncachedInputUSD, costs.cachedInputUSD, costs.visibleOutputUSD, costs.reasoningUSD]
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Token 类型")
                Spacer(minLength: 0)
                Text("用量").frame(width: 55, alignment: .trailing)
                Text("占比").frame(width: 40, alignment: .trailing)
                Text("等值费用").frame(width: 58, alignment: .trailing)
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(CodexVistaTheme.dashboardMutedText)

            ForEach(Array(TokenCompositionSegment.make(breakdown: breakdown, total: total).enumerated()), id: \.element.id) { index, segment in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        HStack(spacing: 5) {
                            Circle().fill(segment.color).frame(width: 5, height: 5)
                            Text(segment.title)
                                .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                        }
                        Spacer(minLength: 0)
                        Text(segment.valueText)
                            .fontWeight(.semibold)
                            .frame(width: 55, alignment: .trailing)
                        Text(segment.shareText)
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .frame(width: 40, alignment: .trailing)
                        Text(ModelCostFormatter.usd(amounts[index]))
                            .fontWeight(.semibold)
                            .frame(width: 58, alignment: .trailing)
                    }
                    .font(.system(size: 10, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    if let pricing {
                        let rate = index == 0 ? pricing.inputPerMillionUSD
                            : index == 1 ? pricing.cachedInputPerMillionUSD : pricing.outputPerMillionUSD
                        Text("单价 \(ModelCostFormatter.rate(rate)) / 百万 Token")
                            .font(.system(size: 9))
                            .foregroundStyle(CodexVistaTheme.dashboardMutedText)
                            .padding(.leading, 10)
                    }
                }
                .contentShape(Rectangle())
                .help("\(segment.accessibilityText)，API 等值费用 \(ModelCostFormatter.usd(amounts[index]))")
                if index < 3 {
                    Rectangle()
                        .fill(CodexVistaTheme.dashboardBorder.opacity(0.45))
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
        }
    }
}
