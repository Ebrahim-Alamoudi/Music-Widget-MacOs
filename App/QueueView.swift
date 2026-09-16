import SwiftUI

struct QueueItem: Identifiable, Hashable {
    var id: String
    var title: String
    var artist: String
    var artwork: URL?
    /// Source-specific position used to jump to this song.
    var position: Int
}

enum QueueResult {
    case items([QueueItem])
    case unavailable(String)
}

/// "Up Next" button that opens the queue in a popover.
struct QueueButton: View {
    var size: CGFloat = 38
    @State private var isShowing = false

    var body: some View {
        Button {
            isShowing.toggle()
        } label: {
            Image(systemName: "list.bullet")
                .font(.system(size: size * 0.37, weight: .semibold))
                .foregroundStyle(isShowing ? AnyShapeStyle(Color.black.opacity(0.85)) : AnyShapeStyle(.primary))
                .frame(width: size, height: size)
                .background {
                    Circle().fill(.white).opacity(isShowing ? 1 : 0)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .help("Up Next")
        .popover(isPresented: $isShowing, arrowEdge: .bottom) {
            QueueView()
        }
    }
}

struct QueueView: View {
    @Environment(PlayerHub.self) private var hub
    @State private var result: QueueResult?

    var body: some View {
        let np = hub.nowPlaying
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up Next")
                    .font(.headline)
                Text(np.isEmpty ? "Not Playing" : np.sourceName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top], 14)
            .padding(.bottom, 10)

            if np.shuffle == true, np.source == .appleMusic {
                Label("Shuffle is on — songs are listed in album or playlist order.", systemImage: "shuffle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
            }

            Divider()

            switch result {
            case nil:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable(let reason):
                ContentUnavailableView("No Queue", systemImage: "list.bullet", description: Text(reason))
                    .frame(maxHeight: .infinity)
            case .items(let items) where items.isEmpty:
                ContentUnavailableView("Nothing Up Next", systemImage: "music.note.list",
                                       description: Text("This is the last song in the queue."))
                    .frame(maxHeight: .infinity)
            case .items(let items):
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            QueueRow(item: item) {
                                hub.playQueueItem(item)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        }
        .frame(width: 300, height: 400)
        .task(id: np.trackID) {
            result = await hub.upNext()
        }
    }
}

private struct QueueRow: View {
    let item: QueueItem
    let play: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: play) {
            HStack(spacing: 10) {
                AsyncImage(url: item.artwork) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle().fill(.quaternary)
                        .overlay { Image(systemName: "music.note").font(.caption).foregroundStyle(.tertiary) }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                    Text(item.artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "play.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .opacity(hovering ? 1 : 0)
            }
            .padding(6)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(.primary.opacity(hovering ? 0.08 : 0)))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Play \(item.title)")
    }
}
