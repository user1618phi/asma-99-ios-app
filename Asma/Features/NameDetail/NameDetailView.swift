import SwiftUI
import SwiftData

struct NameDetailView: View {
    let name: AsmaName

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(LocalizationManager.self) private var localization
    @Query private var progressAll: [NameProgress]
    @State private var meaningExpanded = true
    @State private var practicePresented = false

    private var language: String { localization.current.rawValue }

    private var isFavorite: Bool {
        progressAll.first(where: { $0.number == name.number })?.isFavorite ?? false
    }

    private var translation: NameTranslation {
        name.translation(for: language)
    }

    var body: some View {
        ZStack {
            EditorialPalette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                    .padding(.horizontal, 22)
                    .padding(.top, 8)

                Spacer().frame(height: 60)

                hero

                Spacer().frame(height: 32)

                Rectangle()
                    .fill(EditorialPalette.textFaint)
                    .frame(height: 1)
                    .padding(.horizontal, 40)

                Spacer().frame(height: 28)

                actionRow
                    .padding(.horizontal, 30)

                Spacer(minLength: 16)

                meaningCard
                    .padding(.horizontal, 18)

                Spacer(minLength: 0)
            }
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
        .hideTabBar()
        .preferredColorScheme(.dark)
        .onAppear { markSeen() }
        .sheet(isPresented: $practicePresented) {
            NavigationStack {
                PracticeView(name: name)
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            CircleGlassButton(systemName: "arrow.left") { dismiss() }

            Spacer()

            VStack(spacing: 3) {
                EditorialEyebrow(text: "nameDetail.eyebrow", color: EditorialPalette.textMute, tracking: 2.8, size: 9.5)
                Text(String(format: "%02d / 99", name.number))
                    .font(EditorialFont.mono(12, weight: .medium))
                    .tracking(1.4)
                    .foregroundStyle(EditorialPalette.text)
            }

            Spacer()

            // Balance counter pill — invisible right-side spacer matching the
            // back button's footprint keeps the centre label visually centred.
            Color.clear.frame(width: 38, height: 38)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 0) {
            Text(name.arabic)
                .font(EditorialFont.arabic(60, weight: .regular))
                .foregroundStyle(EditorialPalette.gold)
                .environment(\.layoutDirection, .rightToLeft)
                .shadow(color: EditorialPalette.gold.opacity(0.28), radius: 30)

            Text(name.transliteration)
                .font(EditorialFont.display(36, weight: .bold))
                .tracking(-0.6)
                .foregroundStyle(EditorialPalette.text)
                .padding(.top, 26)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack {
            actionTile(icon: "speaker.wave.2", label: "nameDetail.action.listen") {
                AudioPlayer.shared.play(file: name.audio)
                Haptics.tap()
            }
            Spacer()
            actionTile(icon: isFavorite ? "heart.fill" : "heart", label: "nameDetail.action.favorite") {
                toggleFavorite()
            }
            Spacer()
            actionTile(icon: "mic", label: "nameDetail.action.practice") {
                practicePresented = true
            }
        }
    }

    private func actionTile(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .background(Circle().fill(EditorialPalette.glassBg))
                        .background(Circle().fill(.ultraThinMaterial).opacity(0.4))
                        .frame(width: 60, height: 60)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(EditorialPalette.gold)
                }
                EditorialEyebrow(text: label, color: EditorialPalette.gold, tracking: 2, size: 10.5, weight: .semibold)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggleFavorite() {
        let item = context.progress(for: name.number)
        item.isFavorite.toggle()
        try? context.save()
        Haptics.selection()
    }

    // MARK: - Meaning

    private var meaningCard: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { meaningExpanded.toggle() }
            } label: {
                HStack {
                    EditorialEyebrow(text: "nameDetail.meaning")
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(EditorialPalette.gold)
                        .rotationEffect(.degrees(meaningExpanded ? 180 : 0))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, meaningExpanded ? 16 : 20)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if meaningExpanded {
                Text(translation.translation)
                    .font(EditorialFont.display(26, weight: .bold))
                    .tracking(-0.5)
                    .lineSpacing(2)
                    .foregroundStyle(EditorialPalette.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 22)
                    .transition(.opacity)
            }
        }
        .editorialGlassDeep(cornerRadius: 28)
    }

    // MARK: - Bookkeeping

    /// Increment seenCount **at most once per calendar day per name** so the
    /// number stays a meaningful "how many days I've encountered this name"
    /// instead of a re-open counter.
    private func markSeen() {
        let progress = context.progress(for: name.number)
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let alreadyToday = (progress.lastReviewedAt.map { cal.startOfDay(for: $0) } == today)
        if !alreadyToday {
            progress.seenCount += 1
        }
        progress.lastReviewedAt = Date()
        try? context.save()
    }
}
