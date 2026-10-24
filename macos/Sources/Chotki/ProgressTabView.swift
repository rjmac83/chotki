import SwiftUI
import ChotkiCore

/// What has been kept, in words first.
///
/// The order is deliberate and load-bearing: the sentences come before the
/// figure, because "evening prayers slipped twice, both Fridays" is something a
/// person can act on and a percentage is not. The figure can be hidden entirely
/// in settings, and nothing here is coloured as a warning — there is no red in
/// this view by design.
struct ProgressTabViewContent: View {
    @ObservedObject var model: AppModel
    @State private var confirmingReset = false

    var body: some View {
        let report = model.report()

        VStack(alignment: .leading, spacing: 0) {
            Text("Your progress up to \(Format.longDate(model.progressThrough))")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.bottom, 8)

            summary(report)

            if model.settings.showConsistencyNumber, let overall = report.overall {
                figure(overall)
            }

            if report.hasAnythingDue {
                Rectangle().fill(Theme.line).frame(height: 1).padding(.top, 4)
                perRule(report)
            }

            // Kept together, and above the fold: a button under the picture
            // panel is a button nobody can find.
            HStack(spacing: 22) {
                if report.hasAnythingDue {
                    Button { model.openDetachedReport?() } label: {
                        Label("Open in a window", systemImage: "macwindow")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.gold)
                    }
                    .buttonStyle(.plain)
                }
                resetButton
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .alert("Are you sure?", isPresented: $confirmingReset) {
            Button("Yes") { model.resetRecord() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will completely erase your record and cannot be undone.")
        }
    }

    // MARK: starting again

    /// Always there, because someone with nothing yet recorded may still want to
    /// clear a rule's old stretch. Quiet, and not red: it is a legitimate thing
    /// to want, not a warning.
    private var resetButton: some View {
        Button { confirmingReset = true } label: {
            Label("Reset record", systemImage: "arrow.counterclockwise")
                .font(.system(size: 14))
                .foregroundStyle(Theme.muted)
        }
        .buttonStyle(.plain)
        .overlay { NativeClickRegion(action: { confirmingReset = true }) }
        .accessibilityLabel("Reset record")
    }

    // MARK: prose, which leads

    private func summary(_ report: ProgressReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(report.summary, id: \.self) { line in
                Text(line)
                    .font(Theme.reading(17))
                    .foregroundStyle(Theme.parchment)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: the figure, which does not

    private func figure(_ overall: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(Int((overall * 100).rounded()))%")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.gold)
                Text("Kept, over the 30 days to then")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(.top, 14)
    }

    // MARK: per rule

    private func perRule(_ report: ProgressReport) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("By Rule")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .padding(.top, 10).padding(.bottom, 5)

            ForEach(report.perRule.filter(\.hasAnythingDue)) { score in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(score.title)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.parchmentDim)
                    Spacer(minLength: 6)
                    if score.streak > 1 {
                        // Stated as a fact, never as something at risk.
                        Text("\(score.streak) in a row")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.goldDim)
                    }
                    Text(kept(score))
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
    }

    /// Phrased as what was kept out of what came round — never as a shortfall.
    private func kept(_ score: RuleScore) -> String {
        "\(score.kept + score.keptLate) of \(score.scoreable)"
    }
}

struct ProgressTabView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView { ProgressTabViewContent(model: model).frame(maxWidth: 800).frame(maxWidth: .infinity, alignment: .leading).padding(12).chotkiScrollContent() }
                .frame(maxHeight: .infinity).scrollContentBackgroundHidden().softVerticalScrollEdges()
            if let url = Bundle.module.url(forResource: "progress", withExtension: "jpg", subdirectory: "Resources"),
               let image = NSImage(contentsOf: url) {
                GeometryReader { proxy in
                    let scale = max(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
                    let width = image.size.width * scale
                    let height = image.size.height * scale
                    ZStack(alignment: .bottom) {
                        Image(nsImage: image).resizable()
                            .frame(width: width, height: height)
                            .position(x: proxy.size.width / 2, y: height / 2)
                        LinearGradient(colors: [.clear, .black.opacity(0.92)], startPoint: .top, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(alignment: .top, spacing: 3) {
                                Text("“").font(Theme.reading(49)).offset(y: -11)
                                    .accessibilityHidden(true)
                                Text("Those who have really determined to serve Christ, with the help of spiritual fathers and their own self-knowledge, will strive before all else to choose a place, a way of life, a habitation, and exercises suitable for them.”")
                                    .font(Theme.reading(16)).italic()
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text("— Saint John Climacus · The Ladder of Divine Ascent")
                                .font(.system(size: 12)).padding(.leading, 40)
                            Text("Icon of St. Anthony the Great, St. Paul of Thebes, St. Sabbas the Sanctified, and St. John Climacus.")
                                .font(.system(size: 10)).multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity).padding(.top, 4)
                        }.foregroundStyle(Theme.parchment)
                            .padding(.horizontal, 34).padding(.bottom, 18)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    }
                }.frame(height: 300).clipped()
            }
        }
    }
}
