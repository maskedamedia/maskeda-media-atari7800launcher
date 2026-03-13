import SwiftUI

public struct HelpView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox("Support") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.headline)
                        Text("info@maskedamedia.com")
                            .textSelection(.enabled)

                        Text("Website")
                            .font(.headline)
                        Link("retrogaming.maskedamedia.com", destination: URL(string: "https://retrogaming.maskedamedia.com")!)

                        Text("Git Repository")
                            .font(.headline)
                        Link("github.com/mpro-maskeda/maskeda-media-atari7800launcher", destination: URL(string: "https://github.com/mpro-maskeda/maskeda-media-atari7800launcher")!)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Project Notes") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This launcher hosts the Atari 7800 libretro core as a focused native macOS frontend.")
                        Text("Users must provide their own compatible core binary and only use ROMs they are entitled to use.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Input Support") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Two player ports are supported and configured in Settings > Input.")
                        Text("Keyboard and detected controllers can be assigned to either player, but the same device cannot be assigned to both players at once.")
                            .foregroundStyle(.secondary)
                        Text("Standard macOS controllers use GameController.framework. Additional USB gamepads may appear through the HID fallback path.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox("Tested Controllers") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("PS5 DualSense")
                        Text("Atari CX70+ controller with USB wireless dongle")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 520, minHeight: 360)
    }
}
