import SwiftUI

struct FontSizePopup: View {
    @Bindable var settings: ReaderSettings

    var body: some View {
        VStack(spacing: 16) {
            Text("字号")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#e5e5e7"))

            HStack(spacing: 12) {
                Button {
                    settings.fontSize = max(settings.fontSize - 1, 12)
                    settings.save()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "#e5e5e7"))
                    }
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { Double(settings.fontSize) },
                        set: {
                            settings.fontSize = CGFloat($0)
                            settings.save()
                        }
                    ),
                    in: 12...32,
                    step: 1
                )
                .tint(Color(hex: "#636366"))

                Button {
                    settings.fontSize = min(settings.fontSize + 1, 32)
                    settings.save()
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 32, height: 32)
                        Text("A")
                            .font(.system(size: 18))
                            .foregroundStyle(Color(hex: "#e5e5e7"))
                    }
                }
                .buttonStyle(.plain)
            }

            Text("\(Int(settings.fontSize))")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Color(hex: "#8e8e93"))
        }
        .padding(24)
        .frame(width: 240)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(hex: "#2c2c2e").opacity(0.98))
                .shadow(color: .black.opacity(0.4), radius: 16)
        )
        .offset(y: -40)
    }
}
