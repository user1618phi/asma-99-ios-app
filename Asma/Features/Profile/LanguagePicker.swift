import SwiftUI
import SwiftData

struct LanguagePicker: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization
    @Query private var statsAll: [UserStats]

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 24)

                EditorialEyebrow(text: "language.eyebrow")
                    .padding(.horizontal, 30)

                Spacer().frame(height: 16)

                LocText("language.description")
                    .font(EditorialFont.sans(14, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(EditorialPalette.textDim)
                    .padding(.horizontal, 30)

                Spacer().frame(height: 28)

                VStack(spacing: 0) {
                    Rectangle()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 1)
                    ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element) { idx, lang in
                        Button {
                            let stats = statsAll.first ?? context.userStats()
                            stats.preferredLanguage = lang
                            try? context.save()
                            localization.current = lang
                            Haptics.selection()
                            dismiss()
                        } label: {
                            HStack {
                                Text(lang.displayName)
                                    .font(EditorialFont.display(17, weight: .semibold))
                                    .tracking(-0.2)
                                    .foregroundStyle(EditorialPalette.text)
                                Spacer()
                                if localization.current == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(EditorialPalette.gold)
                                }
                            }
                            .padding(.horizontal, 30)
                            .padding(.vertical, 18)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if idx < AppLanguage.allCases.count - 1 {
                            Rectangle()
                                .fill(EditorialPalette.textFaint)
                                .frame(height: 1)
                                .padding(.leading, 30)
                        }
                    }
                    Rectangle()
                        .fill(EditorialPalette.textFaint)
                        .frame(height: 1)
                }

                Spacer(minLength: 0)
            }
        }
        .preferredColorScheme(.dark)
    }
}
