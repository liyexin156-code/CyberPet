import SwiftUI

enum PixelTheme {
    static let screen = Color(hex: 0x16150F)
    static let panel = Color(hex: 0x23221A)
    static let border = Color(hex: 0x2F6E59)
    static let borderMuted = Color(hex: 0x3C5C4E)
    static let text = Color(hex: 0xE8E4D5)
    static let secondaryText = Color(hex: 0x9A9582)
    static let cyan = Color(hex: 0x5DCAA5)
    static let pink = Color(hex: 0xED93B1)
    static let amber = Color(hex: 0xFAC775)

    static let radius: CGFloat = 4
    static let gap: CGFloat = 12
    static let tightGap: CGFloat = 8
    static let pagePadding: CGFloat = 18
    static let mono = Font.system(.body, design: .monospaced)
    static let monoCaption = Font.system(.caption, design: .monospaced)
    static let monoTitle = Font.system(.title3, design: .monospaced).weight(.semibold)
}

extension Color {
    init(hex: UInt, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xff) / 255,
            green: Double((hex >> 8) & 0xff) / 255,
            blue: Double(hex & 0xff) / 255,
            opacity: alpha
        )
    }
}

struct PixelPanelStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(PixelTheme.mono)
            .foregroundStyle(PixelTheme.text)
            .tint(PixelTheme.cyan)
            .background(PixelTheme.screen)
    }
}

struct PixelCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(PixelTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: PixelTheme.radius)
                    .stroke(PixelTheme.borderMuted, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PixelTheme.radius))
    }
}

struct PixelPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelTheme.monoCaption.weight(.bold))
            .foregroundStyle(PixelTheme.screen)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(configuration.isPressed ? PixelTheme.amber : PixelTheme.cyan)
            .clipShape(RoundedRectangle(cornerRadius: PixelTheme.radius))
    }
}

struct PixelSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(PixelTheme.monoCaption.weight(.semibold))
            .foregroundStyle(configuration.isPressed ? PixelTheme.amber : PixelTheme.cyan)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(PixelTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: PixelTheme.radius)
                    .stroke(configuration.isPressed ? PixelTheme.amber : PixelTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: PixelTheme.radius))
    }
}

struct PixelTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(PixelTheme.mono)
            .foregroundStyle(PixelTheme.text)
            .textFieldStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(PixelTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: PixelTheme.radius)
                    .stroke(PixelTheme.borderMuted, lineWidth: 1)
            )
    }
}

struct PixelSquareCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(configuration.isOn ? PixelTheme.cyan : Color.clear)
                    .frame(width: 14, height: 14)
                    .overlay(Rectangle().stroke(PixelTheme.cyan, lineWidth: 1))
                    .padding(.top, 2)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}

struct PixelToggleButtonStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(configuration.isOn ? PixelTheme.cyan : PixelTheme.screen)
                    .frame(width: 16, height: 16)
                    .overlay(Rectangle().stroke(PixelTheme.cyan, lineWidth: 1))
                configuration.label
                    .font(PixelTheme.monoCaption)
                    .foregroundStyle(PixelTheme.text)
            }
        }
        .buttonStyle(.plain)
    }
}

struct SegmentedPixelMeter: View {
    let value: Int
    let segments: Int = 12

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<segments, id: \.self) { index in
                Rectangle()
                    .fill(index < filledSegments ? meterColor : PixelTheme.screen)
                    .frame(height: 10)
                    .overlay(Rectangle().stroke(PixelTheme.borderMuted, lineWidth: 1))
            }
        }
    }

    private var filledSegments: Int {
        Int((Double(max(min(value, 100), 0)) / 100 * Double(segments)).rounded(.up))
    }

    private var meterColor: Color {
        value >= 70 ? PixelTheme.cyan : (value >= 40 ? PixelTheme.amber : PixelTheme.pink)
    }
}

extension View {
    func pixelPanel() -> some View {
        modifier(PixelPanelStyle())
    }

    func pixelCard() -> some View {
        modifier(PixelCard())
    }
}
