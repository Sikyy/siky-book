import SwiftUI

struct BrightnessPopup: View {
    @State private var brightness: Double = Double(UIScreen.main.brightness)

    var body: some View {
        VStack(spacing: 16) {
            Text("亮度")
                .font(.system(size: 13))
                .foregroundStyle(Color(hex: "#e5e5e7"))

            HStack(spacing: 12) {
                Image(systemName: "sun.min")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(hex: "#e5e5e7"))

                Slider(value: $brightness, in: 0...1) { editing in
                    if !editing {
                        UIScreen.main.brightness = CGFloat(brightness)
                    }
                }
                .tint(Color(hex: "#636366"))
                .onChange(of: brightness) { _, newValue in
                    UIScreen.main.brightness = CGFloat(newValue)
                }

                Image(systemName: "sun.max")
                    .font(.system(size: 16))
                    .foregroundStyle(Color(hex: "#e5e5e7"))
            }
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
