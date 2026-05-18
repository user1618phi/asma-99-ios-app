import SwiftUI
import SwiftData

struct FlashcardsLandingView: View {
    @Environment(\.modelContext) private var context
    @Environment(LocalizationManager.self) private var localization
    @Query private var progress: [NameProgress]
    @AppStorage(AppSettingsKey.flashcardCount) private var flashcardCount = AppSettingsKey.flashcardDefault
    @State private var path = NavigationPath()
    @State private var search = ""
    @State private var searchVisible = false
    @State private var allahSheetPresented = false

    private var language: String { localization.current.rawValue }

    private var favoriteNumbers: Set<Int> {
        Set(progress.filter { $0.isFavorite }.map(\.number))
    }

    private var favorites: [AsmaName] {
        NamesRepository.shared.names.filter { favoriteNumbers.contains($0.number) }
    }

    /// Count of names that have at least reached `.confirmed` — i.e. the
    /// user has hit "3 correct in a row" in tests. Lower than the legacy
    /// "≥ 3 mastery" rule because the new engine only awards confirmed via
    /// real test answers, not flashcard taps. Surfaced as the "X / 99"
    /// counter beside the All Ninety-nine list header.
    private var learnedCount: Int {
        progress.filter { $0.reviewStateRaw >= ReviewState.confirmed.rawValue }.count
    }

    /// Same state derivation as HomeView. `.studyingToday` and
    /// `.readyToTest` collapse into a single "active" copy variant here,
    /// because the Learn CTA always opens a flashcard session regardless
    /// — only the wording changes between fresh / active / caught-up.
    private var sessionStatus: SessionStatus {
        let introduced = progress.filter {
            $0.reviewStateRaw >= ReviewState.studying.rawValue
        }.count
        if introduced == 0 { return .fresh }

        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let studied = progress.filter {
            if let last = $0.lastStudiedAt {
                return cal.startOfDay(for: last) == today
            }
            return false
        }.count
        if studied < flashcardCount {
            return .studyingToday(remaining: flashcardCount - studied)
        }

        let counts = TodayPoolFactory.todayCounts(progresses: progress)
        let poolTotal = counts.newToday + counts.dueReviews
        if poolTotal > 0 { return .readyToTest(count: poolTotal) }

        return .caughtUp
    }

    private var sessionEyebrowKey: String {
        switch sessionStatus {
        case .fresh:         return "learn.cta.fresh.eyebrow"
        case .studyingToday: return "learn.session.eyebrow"
        case .readyToTest, .cooldown, .caughtUp:
            return "learn.cta.freePractice.eyebrow"
        }
    }

    private var sessionTitleKey: String {
        switch sessionStatus {
        case .fresh:         return "learn.cta.fresh.title"
        case .studyingToday: return "learn.cta.active.title"
        case .readyToTest, .cooldown, .caughtUp:
            return "learn.cta.freePractice.title"
        }
    }

    /// Only Free Practice gets a subtitle — it's the one state that needs
    /// to explain itself ("no progress tracked" disclaimer). The other
    /// states stay clean with just eyebrow + title.
    private var sessionSubtitleKey: String? {
        switch sessionStatus {
        case .readyToTest, .cooldown, .caughtUp:
            return "learn.cta.freePractice.subtitle"
        default:
            return nil
        }
    }

    /// Tap destination — `.session` for daily learning (today's pool,
    /// writes to ProgressEngine), `.freePractice` once goal is hit (all
    /// 99, no state side effects).
    private var sessionRoute: FlashcardsRoute {
        switch sessionStatus {
        case .fresh, .studyingToday:
            return .session
        case .readyToTest, .cooldown, .caughtUp:
            return .freePractice
        }
    }

    private var filtered: [AsmaName] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return NamesRepository.shared.names }
        return NamesRepository.shared.names.filter { name in
            if name.transliteration.lowercased().contains(q) { return true }
            if "\(name.number)".contains(q) { return true }
            let t = name.translation(for: language)
            if t.translation.lowercased().contains(q) { return true }
            if t.meaning.lowercased().contains(q) { return true }
            return false
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .topTrailing) {
                EditorialPalette.bg.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                        editorialHeader
                            .padding(.top, 32)
                            .padding(.horizontal, 30)

                        if searchVisible {
                            searchField
                                .padding(.horizontal, 18)
                                .padding(.top, 16)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        sessionCard
                            .padding(.horizontal, 18)
                            .padding(.top, 24)

                        if !favorites.isEmpty && search.isEmpty {
                            favoritesSection
                                .padding(.top, 32)
                        }

                        allNamesSection
                            .padding(.top, 32)
                            .padding(.bottom, 40)
                    }
                }

                HStack(spacing: 10) {
                    CircleGlassButton(systemName: "magnifyingglass") {
                        withAnimation(.easeOut(duration: 0.25)) {
                            searchVisible.toggle()
                            if !searchVisible { search = "" }
                        }
                    }
                    AmbientSoundButton()
                }
                .padding(.top, 8)
                .padding(.trailing, 18)
            }
            .navigationBarHidden(true)
            .navigationDestination(for: FlashcardsRoute.self) { route in
                switch route {
                case .session:      FlashcardsSessionView(mode: .todaysPool)
                case .freePractice: FlashcardsSessionView(mode: .freePractice)
                }
            }
            .navigationDestination(for: AsmaName.self) { name in
                NameDetailView(name: name)
            }
            .sheet(isPresented: $allahSheetPresented) {
                AllahExplanationSheet()
                    .presentationDetents([.large])
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Header

    @ViewBuilder private var editorialHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            EditorialEyebrow(text: "learn.eyebrow")
                .padding(.top, 30)
            LocText("learn.title")
                .font(EditorialFont.display(84, weight: .heavy))
                .tracking(-2)
                .lineSpacing(-10)
                .foregroundStyle(EditorialPalette.text)
            LocText("learn.subtitle")
                .font(EditorialFont.display(17, weight: .medium))
                .foregroundStyle(EditorialPalette.textDim)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(EditorialPalette.textMute)
            TextField("", text: $search, prompt: Text(verbatim: Bundle.loc("learn.search.placeholder"))
                .foregroundColor(EditorialPalette.textMute))
                .font(EditorialFont.sans(15, weight: .medium))
                .foregroundStyle(EditorialPalette.text)
                .tint(EditorialPalette.gold)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .editorialGlass(cornerRadius: 18)
    }

    // MARK: - Session CTA

    private var sessionCard: some View {
        Button {
            path.append(sessionRoute)
        } label: {
            HStack(spacing: 18) {
                ZStack {
                    Circle()
                        .strokeBorder(EditorialPalette.goldFaint, lineWidth: 1)
                        .frame(width: 60, height: 60)
                        .background(
                            Circle().fill(EditorialPalette.gold.opacity(0.04))
                        )
                    Image(systemName: "play.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(EditorialPalette.gold)
                        .offset(x: 2)
                }

                VStack(alignment: .leading, spacing: 4) {
                    EditorialEyebrow(text: sessionEyebrowKey, size: 9.5, weight: .medium)
                    LocText(sessionTitleKey)
                        .font(EditorialFont.display(22, weight: .bold))
                        .tracking(-0.4)
                        .lineSpacing(1)
                        .foregroundStyle(EditorialPalette.text)
                        .multilineTextAlignment(.leading)
                    if let subtitleKey = sessionSubtitleKey {
                        LocText(subtitleKey)
                            .font(EditorialFont.sans(12, weight: .medium))
                            .foregroundStyle(EditorialPalette.textDim)
                            .multilineTextAlignment(.leading)
                            .padding(.top, 2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(EditorialPalette.gold)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .editorialGlassDeep(cornerRadius: 32)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(EditorialPalette.gold)
                EditorialEyebrow(text: "learn.favorites")
                Spacer()
                Text(String(format: "%02d", favorites.count))
                    .font(EditorialFont.mono(10.5, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.horizontal, 30)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(favorites) { name in
                        favoriteTile(name)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func favoriteTile(_ name: AsmaName) -> some View {
        Button {
            path.append(name)
        } label: {
            VStack(spacing: 0) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorialPalette.gold)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, 14)
                    .padding(.trailing, 14)

                Spacer().frame(height: 6)

                Text(name.arabic)
                    .font(EditorialFont.arabic(38, weight: .regular))
                    .foregroundStyle(EditorialPalette.gold)
                    .environment(\.layoutDirection, .rightToLeft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Spacer().frame(height: 14)

                Text(name.transliteration)
                    .font(EditorialFont.display(19, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(EditorialPalette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)

                Text(name.translation(for: language).translation)
                    .font(EditorialFont.sans(11, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 4)
                    .padding(.bottom, 18)
                    .padding(.horizontal, 10)
            }
            .frame(width: 168, height: 180)
            .editorialGlassDeep(cornerRadius: 28)
        }
        .buttonStyle(.plain)
    }

    // MARK: - All names

    private var allNamesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                EditorialEyebrow(text: "learn.allNames", color: EditorialPalette.textMute, size: 10)
                Rectangle()
                    .fill(EditorialPalette.textFaint)
                    .frame(height: 1)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(EditorialPalette.gold)
                            .frame(width: 8, height: 1)
                    }
                Text(String(format: "%02d / 99", min(learnedCount, 99)))
                    .font(EditorialFont.mono(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(EditorialPalette.textMute)
            }
            .padding(.horizontal, 30)

            VStack(spacing: 0) {
                if search.trimmingCharacters(in: .whitespaces).isEmpty {
                    EditorialAllahRow { allahSheetPresented = true }
                    EditorialNameDivider()
                }
                ForEach(filtered) { name in
                    Button {
                        path.append(name)
                    } label: {
                        EditorialNameRow(
                            name: name,
                            language: language,
                            isFavorite: favoriteNumbers.contains(name.number),
                            toggleFavorite: { toggleFavorite(name.number) }
                        )
                    }
                    .buttonStyle(.plain)
                    if name.number != filtered.last?.number {
                        EditorialNameDivider()
                    }
                }
            }
        }
    }

    private func toggleFavorite(_ number: Int) {
        let item = context.progress(for: number)
        item.isFavorite.toggle()
        try? context.save()
        Haptics.selection()
    }
}

enum FlashcardsRoute: Hashable {
    /// Daily learning loop — today's pool, writes back to ProgressEngine.
    case session
    /// Bonus browsing — all 99 names, no state side effects. Unlocked
    /// once the user has hit their daily flashcard goal.
    case freePractice
}

// MARK: - Row primitives (keep the user's existing card structure, dark-themed)

struct EditorialNameDivider: View {
    var body: some View {
        Rectangle()
            .fill(EditorialPalette.textFaint)
            .frame(height: 1)
            .padding(.leading, 60)
    }
}

struct EditorialAllahRow: View {
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(EditorialPalette.gold)
                    .frame(width: 20, alignment: .center)

                VStack(alignment: .leading, spacing: 1) {
                    LocText("learn.allah.title")
                        .font(EditorialFont.display(28, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(EditorialPalette.gold)
                    LocText("learn.allah.subtitle")
                        .font(EditorialFont.sans(11.5, weight: .medium))
                        .foregroundStyle(EditorialPalette.textDim)
                }

                Spacer(minLength: 0)

                Text("ٱللّٰه")
                    .font(EditorialFont.arabic(28, weight: .regular))
                    .foregroundStyle(EditorialPalette.gold)
                    .environment(\.layoutDirection, .rightToLeft)
                    .frame(minWidth: 70, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .foregroundStyle(EditorialPalette.textMute)
                    .frame(width: 14)
            }
            .padding(.horizontal, 30)
            .padding(.vertical, 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct EditorialNameRow: View {
    let name: AsmaName
    let language: String
    let isFavorite: Bool
    let toggleFavorite: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text(String(format: "%02d", name.number))
                .font(EditorialFont.mono(10.5, weight: .medium))
                .tracking(0.4)
                .foregroundStyle(EditorialPalette.textMute)
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 1) {
                Text(name.transliteration)
                    .font(EditorialFont.display(24, weight: .bold))
                    .tracking(-0.3)
                    .foregroundStyle(EditorialPalette.text)
                    .lineLimit(1)
                Text(name.translation(for: language).translation)
                    .font(EditorialFont.sans(11.5, weight: .medium))
                    .foregroundStyle(EditorialPalette.textDim)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(name.arabic)
                .font(EditorialFont.arabic(24, weight: .regular))
                .foregroundStyle(EditorialPalette.text)
                .environment(\.layoutDirection, .rightToLeft)
                .frame(minWidth: 70, alignment: .trailing)
                .lineLimit(1)

            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 14))
                    .foregroundStyle(isFavorite ? EditorialPalette.gold : EditorialPalette.textFaint)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}
