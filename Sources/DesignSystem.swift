import SwiftUI
import AppKit

// MARK: - Design System
// Tokens e peças reutilizáveis para que todas as superfícies do painel
// compartilhem a mesma escala de espaçamento, raio, cor e tipografia.
enum DS {
    // Escala de espaçamento
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16

    // Raios de canto
    static let rSm: CGFloat = 8
    static let rMd: CGFloat = 12
    static let rLg: CGFloat = 16

    // Painel da barra de menus
    static let panelWidth: CGFloat = 404
    static let panelHeight: CGFloat = 566

    // Paleta
    static let accent = Color(red: 0.29, green: 0.56, blue: 1.00)
    static let good   = Color(red: 0.22, green: 0.80, blue: 0.46)
    static let warn   = Color(red: 1.00, green: 0.62, blue: 0.12)
    static let bad    = Color(red: 1.00, green: 0.33, blue: 0.29)
    static let violet = Color(red: 0.61, green: 0.48, blue: 1.00)

    static let cardFill   = Color.white.opacity(0.055)
    static let cardStroke = Color.white.opacity(0.075)
    static let fieldFill  = Color.white.opacity(0.07)
    static let hairline   = Color.white.opacity(0.08)

    static let textPrimary   = Color.white
    static let textSecondary = Color.white.opacity(0.64)
    static let textTertiary  = Color.white.opacity(0.38)
}

// MARK: - Vibrancy (material nativo do macOS)
struct VisualEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = state
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
        view.state = state
    }
}

// MARK: - Card
struct Card<Content: View>: View {
    var padding: CGFloat = DS.s3
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .fill(DS.cardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                    .stroke(DS.cardStroke, lineWidth: 0.75)
            )
    }
}

// MARK: - Hairline
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(DS.hairline)
            .frame(height: 1)
    }
}

// MARK: - Barra de progresso
struct ProgressBar: View {
    var value: Double          // 0...1
    var tint: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(0.75), tint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

// MARK: - Cartão de métrica (CPU / RAM)
struct MetricCard: View {
    var symbol: String
    var title: String
    var percent: Double        // 0...100
    var valueText: String
    var caption: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: DS.s2) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(tint)

                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(DS.textSecondary)

                Spacer(minLength: 4)

                Text(valueText)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .monospacedDigit()
            }

            ProgressBar(value: percent / 100, tint: tint)

            Text(caption)
                .font(.system(size: 10.5))
                .foregroundColor(DS.textTertiary)
                .lineLimit(1)
                .monospacedDigit()
        }
        .padding(DS.s3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .fill(DS.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.rMd, style: .continuous)
                .stroke(DS.cardStroke, lineWidth: 0.75)
        )
    }
}

// MARK: - Pílula de status
struct StatusPill: View {
    var title: String
    var color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.14))
        )
    }
}

// MARK: - Botão de ícone
struct IconButton: View {
    var systemName: String
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(hovering ? 0.14 : 0.06))
                    .frame(width: 28, height: 28)
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(hovering ? .white : DS.textSecondary)
            }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Rótulo de seção
struct SectionLabel: View {
    var text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.6)
            .foregroundColor(DS.textTertiary)
    }
}

// MARK: - Seletor segmentado compacto
struct SegmentedPicker<T: Hashable>: View {
    @Binding var selection: T
    var options: [(value: T, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = option.value == selection

                Text(option.label)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundColor(isSelected ? .white : DS.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.16) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { selection = option.value }
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: DS.rSm, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
