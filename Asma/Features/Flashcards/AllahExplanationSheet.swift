import SwiftUI

/// Modal sheet explaining "Allah" as the proper name — surfaced from the
/// featured row at the top of the Learn list.
struct AllahExplanationSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer().frame(height: 30)

                    Text("ٱللّٰه")
                        .font(EditorialFont.arabic(108, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                        .environment(\.layoutDirection, .rightToLeft)
                        .shadow(color: EditorialPalette.gold.opacity(0.3), radius: 40)

                    Spacer().frame(height: 24)

                    EditorialEyebrow(text: "allah.eyebrow")

                    Spacer().frame(height: 28)

                    LocText("allah.title")
                        .font(EditorialFont.display(22, weight: .bold))
                        .tracking(-0.4)
                        .lineSpacing(4)
                        .foregroundStyle(EditorialPalette.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Spacer().frame(height: 18)

                    LocText("allah.body")
                        .font(EditorialFont.sans(14, weight: .medium))
                        .lineSpacing(4)
                        .foregroundStyle(EditorialPalette.textDim)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)

                    Spacer().frame(height: 28)

                    Rectangle()
                        .fill(EditorialPalette.goldFaint)
                        .frame(width: 28, height: 1)

                    Spacer().frame(height: 24)

                    LocText("allah.hadith")
                        .font(EditorialFont.display(14, weight: .light).italic())
                        .lineSpacing(3)
                        .foregroundStyle(EditorialPalette.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer().frame(height: 10)

                    LocText("allah.hadith.source")
                        .font(EditorialFont.sans(11, weight: .medium))
                        .foregroundStyle(EditorialPalette.textMute)

                    Spacer().frame(height: 32)

                    Button { dismiss() } label: {
                        LocText("common.done")
                            .font(EditorialFont.sans(11, weight: .semibold))
                            .tracking(2.4)
                            .textCase(.uppercase)
                            .foregroundStyle(Color.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(Capsule().fill(EditorialPalette.gold))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 32)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
