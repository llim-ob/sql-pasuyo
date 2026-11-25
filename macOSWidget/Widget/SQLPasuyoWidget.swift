import SwiftUI
import WidgetKit

struct TaskEntry: TimelineEntry { let date: Date }

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry { TaskEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        completion(Timeline(entries: [TaskEntry(date: .now)], policy: .never))
    }
}

struct SQLPasuyoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private let mint = Color(red: 0.48, green: 0.95, blue: 0.77)
    private var fullColor: Bool { renderingMode == .fullColor }

    var body: some View {
        Group {
            if family == .systemSmall {
                VStack(alignment: .leading, spacing: 0) {
                    documentMark(size: 34)
                    Spacer(minLength: 6)
                    Text("SQL Pasuyo")
                        .font(.system(size: 17, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    openLabel
                        .padding(.top, 5)
                }
            } else {
                HStack(spacing: 15) {
                    documentMark(size: 55)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SQL Pasuyo")
                            .font(.system(size: 20, weight: .semibold))
                        Text("Generate SQL from Teamwork tasks.")
                            .font(.caption)
                            .foregroundStyle(fullColor ? Color.white.opacity(0.78) : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        openLabel
                            .padding(.top, 7)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(fullColor ? Color.white : Color.primary)
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.07, green: 0.25, blue: 0.22),
                    Color(red: 0.04, green: 0.11, blue: 0.14),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .accessibilityElement(children: .combine)
        .widgetURL(URL(string: "sqlpasuyo://submit"))
    }

    private func documentMark(size: CGFloat) -> some View {
        Image(systemName: "doc.text")
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(fullColor ? mint : Color.primary)
            .frame(width: size, height: size)
            .background(
                fullColor ? mint.opacity(0.15) : Color.primary.opacity(0.10),
                in: .rect(cornerRadius: size * 0.27)
            )
            .widgetAccentable()
            .accessibilityHidden(true)
    }

    private var openLabel: some View {
        HStack(spacing: 4) {
            Text("Open previews")
            Image(systemName: "arrow.up.right")
                .accessibilityHidden(true)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(fullColor ? mint : Color.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.85)
        .widgetAccentable()
    }
}

@main
struct SQLPasuyoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SQLPasuyoWidget", provider: TaskProvider()) { _ in
            SQLPasuyoWidgetView()
        }
        .configurationDisplayName("SQL Pasuyo")
        .description("Open SQL Pasuyo to preview SQL requests from Teamwork tasks.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
