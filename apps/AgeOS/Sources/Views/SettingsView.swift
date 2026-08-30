import SwiftUI
import AppKit
import AgeOSCore

/// The Settings window. Unlike `MenuBarView` this is an ordinary view, so the shared
/// components apply here.
struct SettingsView: View {
    @Environment(AppModel.self) private var model

    private var libraryRoot: URL { AgeOSHome().root }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                SectionCard(title: "Library",
                            accessory: AnyView(
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([libraryRoot])
                                })) {
                    // The path was shown as text you could not click — and it is the thing
                    // people most often want to open from this screen.
                    Text(verbatim: libraryRoot.path)
                        .font(.ageCaption)
                        .foregroundStyle(Color.ageTextSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                SectionCard(title: "Adapters", count: model.adapters.count) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Bundled specs ship with AgeOS. Drop JSON files in ~/.ageos/adapters/ to override them or add an agent.")
                            .font(.ageCallout)
                            .foregroundStyle(Color.ageTextSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: "\(model.matrixAdapters.count) detected on this Mac")
                            .font(.ageCaption)
                            .foregroundStyle(Color.ageTextSecondary)
                    }
                }

                SectionCard(title: "Sources", count: model.sources.count) {
                    if model.sources.isEmpty {
                        Text("No sources yet. Add one from the Library screen.")
                            .font(.ageCallout)
                            .foregroundStyle(Color.ageTextSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            ForEach(model.sources, id: \.id) { source in
                                Text(verbatim: source.id)
                                    .font(.ageCaption)
                                    .foregroundStyle(Color.ageTextSecondary)
                            }
                        }
                    }
                }

                Text("Budget numbers are estimates, ±20% (4 bytes per token, measured in a spike).")
                    .font(.ageCaption)
                    .foregroundStyle(Color.ageTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Space.xl)
        }
        .background(Color.ageSurface)
        .frame(width: 520, height: 460)
    }
}
