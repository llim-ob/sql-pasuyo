import SwiftUI
import WidgetKit

struct TaskEntry: TimelineEntry { let date: Date }
struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry { TaskEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) { completion(TaskEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        completion(Timeline(entries: [TaskEntry(date: .now)], policy: .never))
    }
}

struct SQLPasuyoWidgetView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("SQL Pasuyo", systemImage: "arrow.trianglehead.2.clockwise")
                .font(.headline)
            Text("Turn a Teamwork task into a GitHub SQL request.")
                .font(.caption).foregroundStyle(.secondary)
            Link("Open SQL Pasuyo", destination: URL(string: "sqlpasuyo://submit")!)
                .font(.callout.bold())
        }.padding()
    }
}

@main
struct SQLPasuyoWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SQLPasuyoWidget", provider: TaskProvider()) { _ in
            SQLPasuyoWidgetView()
        }
        .configurationDisplayName("SQL Pasuyo")
        .description("Open SQL Pasuyo to submit a Teamwork task.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
