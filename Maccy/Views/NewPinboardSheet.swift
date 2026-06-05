import SwiftUI

struct SVGrid: View {
  let hue: Double
  @Binding var saturation: Double
  @Binding var brightness: Double
  let onChange: () -> Void

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .topLeading) {
        // Base hue color
        Color(hue: hue / 360, saturation: 1, brightness: 1)
        
        // Saturation gradient (white-to-transparent)
        LinearGradient(
          colors: [.white, .white.opacity(0)],
          startPoint: .leading,
          endPoint: .trailing
        )
        
        // Brightness gradient (transparent-to-black)
        LinearGradient(
          colors: [.clear, .black],
          startPoint: .top,
          endPoint: .bottom
        )

        // Selector thumb
        Circle()
          .stroke(Color.white, lineWidth: 2)
          .background(Circle().fill(Color(hue: hue / 360, saturation: saturation, brightness: brightness)))
          .frame(width: 14, height: 14)
          .shadow(color: .black.opacity(0.35), radius: 3)
          .offset(
            x: saturation * geo.size.width - 7,
            y: (1.0 - brightness) * geo.size.height - 7
          )
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let s = max(0, min(1, value.location.x / geo.size.width))
            let v = max(0, min(1, 1.0 - (value.location.y / geo.size.height)))
            saturation = s
            brightness = v
            onChange()
          }
      )
    }
  }
}

struct HueSlider: View {
  @Binding var hue: Double
  let onChange: () -> Void

  var body: some View {
    GeometryReader { geo in
      ZStack(alignment: .leading) {
        // Rainbow track
        LinearGradient(
          colors: [
            Color(hue: 0.0, saturation: 1, brightness: 1),
            Color(hue: 0.166, saturation: 1, brightness: 1),
            Color(hue: 0.333, saturation: 1, brightness: 1),
            Color(hue: 0.5, saturation: 1, brightness: 1),
            Color(hue: 0.666, saturation: 1, brightness: 1),
            Color(hue: 0.833, saturation: 1, brightness: 1),
            Color(hue: 1.0, saturation: 1, brightness: 1)
          ],
          startPoint: .leading,
          endPoint: .trailing
        )
        .frame(height: 10)
        .clipShape(Capsule())

        // Thumb indicator
        Circle()
          .stroke(Color.white, lineWidth: 2)
          .background(Circle().fill(Color(hue: hue / 360, saturation: 1, brightness: 1)))
          .frame(width: 14, height: 14)
          .shadow(color: .black.opacity(0.35), radius: 3)
          .offset(x: (hue / 360) * (geo.size.width - 14))
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let percent = max(0, min(1, value.location.x / geo.size.width))
            hue = percent * 360
            onChange()
          }
      )
    }
    .frame(height: 14)
  }
}

struct NewPinboardSheet: View {
  let onCreate: (String, String) -> Void
  let onCancel: () -> Void

  @State private var name = ""
  @State private var selectedHex = "0088FF"
  @State private var customColor = Color.blue

  // HSV Picker Bindings
  @State private var hue: Double = 208
  @State private var saturation: Double = 1.0
  @State private var brightness: Double = 1.0

  // State to revert on cancel
  @State private var tempColor = Color.blue
  @State private var tempHue: Double = 208
  @State private var tempSaturation: Double = 1.0
  @State private var tempBrightness: Double = 1.0

  @State private var isCustomPickerOpen = false
  private var isCustomActive: Bool {
    !presets.contains(where: { $0.0 == selectedHex })
  }

  private let presets: [(String, Color)] = [
    ("0088FF", .blue),
    ("8B5CF6", Color(red: 0.55, green: 0.36, blue: 0.96)),
    ("EF4444", Color(red: 0.94, green: 0.27, blue: 0.27)),
    ("F59E0B", Color(red: 0.96, green: 0.62, blue: 0.04)),
    ("6B7280", Color(red: 0.42, green: 0.45, blue: 0.50))
  ]

  var body: some View {

    // Main New Pinboard Panel (left side)
    VStack(spacing: 16) {
      Text("New Pinboard")
        .font(.system(size: 14, weight: .semibold))

      TextField("Name (e.g. Work, Design)", text: $name)
        .textFieldStyle(.roundedBorder)
        .frame(width: 190)

      HStack(spacing: 8) {
        // Presets
        ForEach(presets, id: \.0) { hex, color in
          Circle()
            .fill(color)
            .frame(width: 20, height: 20)
            .overlay(Circle().stroke(Color.white, lineWidth: (!isCustomActive && selectedHex == hex) ? 2.5 : 0))
            .scaleEffect((!isCustomActive && selectedHex == hex) ? 1.15 : 1.0)
            .onTapGesture {
              withAnimation(.spring(duration: 0.15)) {
                selectPreset(hex)
              }
            }
        }

        // Custom Color Circle (plus icon)
        ZStack {
          Circle()
            .fill(isCustomActive ? customColor : Color.clear)
            .frame(width: 20, height: 20)
            .background(
              Circle()
                .strokeBorder(Color.white.opacity(0.3), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3]))
            )
            .overlay(
              Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(isCustomActive ? contrastColor(customColor) : .white.opacity(0.8))
            )
            .overlay(Circle().stroke(Color.white, lineWidth: isCustomActive ? 2.5 : 0))
            .scaleEffect(isCustomActive ? 1.15 : 1.0)
            .onTapGesture {
              withAnimation(.spring(duration: 0.15)) {
                // Capture state to allow reversion if user cancels
                tempColor = customColor
                tempHue = hue
                tempSaturation = saturation
                tempBrightness = brightness

                isCustomPickerOpen = true
              }
            }
        }
      }

      HStack(spacing: 12) {
        Button("Cancel") { onCancel() }
          .buttonStyle(.plain)
          .foregroundStyle(.secondary)
          .font(.system(size: 11))
        
        Button("Create") {
          let t = name.trimmingCharacters(in: .whitespaces)
          guard !t.isEmpty else { return }
          onCreate(t, selectedHex)
        }
        .buttonStyle(.borderedProminent)
        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        .font(.system(size: 11))
      }
    }
    .padding(16)
    .frame(width: 220, height: 160)
    .background(.regularMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))

    // Right Custom Color Picker Panel (draws as overlay, preventing left card movement)
    .overlay(alignment: .trailing) {
      if isCustomPickerOpen {
        VStack(spacing: 10) {
          SVGrid(hue: hue, saturation: $saturation, brightness: $brightness) {
            updateCustomColorFromHSV()
          }
          .frame(width: 170, height: 80)

          HueSlider(hue: $hue) {
            updateCustomColorFromHSV()
          }
          .frame(width: 170)

          // Hex entry field (linked directly to the custom picker view)
          HStack(spacing: 6) {
            Text("Hex:")
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(.secondary)
            
            HStack(spacing: 2) {
              Text("#")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
              TextField("HEX", text: hexBinding)
              .textFieldStyle(.plain)
              .font(.system(size: 10, design: .monospaced))
              .frame(width: 55)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 6))
          }

          HStack(spacing: 12) {
            Button("Cancel") {
              withAnimation(.spring(duration: 0.15)) {
                // Revert custom color values to pre-edit state
                customColor = tempColor
                hue = tempHue
                saturation = tempSaturation
                brightness = tempBrightness
                
                isCustomPickerOpen = false
              }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.system(size: 11))

            Button("Apply") {
              withAnimation(.spring(duration: 0.15)) {
                let hex = colorToHex(customColor)
                selectedHex = hex
                isCustomPickerOpen = false
              }
            }
            .buttonStyle(.borderedProminent)
            .font(.system(size: 11))
          }
        }
        .padding(14)
        .frame(width: 200, height: 190)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.15), lineWidth: 1))
        .offset(x: 216) // Offset by width (200) + spacing (16) to slide out absolutely to the right
        .transition(.asymmetric(
          insertion: .move(edge: .trailing).combined(with: .opacity),
          removal: .move(edge: .trailing).combined(with: .opacity)
        ))
      }
    }
  }

  private func selectPreset(_ hex: String) {
    selectedHex = hex
    updateHSVFromHex(hex)
  }

  private func updateCustomColorFromHSV() {
    let color = Color(hue: hue / 360, saturation: saturation, brightness: brightness)
    customColor = color
  }

  private func updateHSVFromHex(_ hex: String) {
    guard let color = Color(hex: hex) else { return }
    let nsColor = NSColor(color)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return }
    var h: CGFloat = 0
    var s: CGFloat = 0
    var b: CGFloat = 0
    var a: CGFloat = 0
    rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
    self.hue = Double(h * 360)
    self.saturation = Double(s)
    self.brightness = Double(b)
    self.customColor = color
  }

  private func colorToHex(_ color: Color) -> String {
    let nsColor = NSColor(color)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
      return "0088FF"
    }
    let r = Int(rgbColor.redComponent * 255)
    let g = Int(rgbColor.greenComponent * 255)
    let b = Int(rgbColor.blueComponent * 255)
    return String(format: "%02X%02X%02X", r, g, b)
  }

  private func contrastColor(_ color: Color) -> Color {
    let nsColor = NSColor(color)
    guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
      return .white
    }
    let luminance = 0.299 * rgbColor.redComponent + 0.587 * rgbColor.greenComponent + 0.114 * rgbColor.blueComponent
    return luminance > 0.6 ? Color(hex: "024E50")! : .white
  }

  private var hexBinding: Binding<String> {
    Binding<String>(
      get: { colorToHex(customColor) },
      set: { newValue in
        let cleaned = newValue.trimmingCharacters(in: CharacterSet.alphanumerics.inverted).prefix(6).uppercased()
        let cleanedStr = String(cleaned)
        if Color(hex: cleanedStr) != nil {
          updateHSVFromHex(cleanedStr)
        }
      }
    )
  }
}
