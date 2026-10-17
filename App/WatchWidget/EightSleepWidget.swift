import SwiftUI
import WidgetKit

/// The complication only launches the watch app. Temperature controls stay in the app.
struct LaunchEntry: TimelineEntry {
    let date: Date
}

struct LaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> LaunchEntry {
        LaunchEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LaunchEntry) -> Void) {
        completion(LaunchEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LaunchEntry>) -> Void) {
        let timeline = Timeline(entries: [LaunchEntry(date: .now)], policy: .never)
        completion(timeline)
    }
}

struct LaunchWidgetView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .widgetAccentable()
            .widgetURL(URL(string: "eightsleepgrok://open"))
            .containerBackground(for: .widget) {
                AccessoryWidgetBackground()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "thermometer.medium")
                .font(.title3)
                .widgetLabel("Bed")
        case .accessoryInline:
            Label("Bed", systemImage: "thermometer.medium")
        default:
            Image(systemName: "thermometer.medium")
                .font(.title2)
        }
    }
}

@main
struct LaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "com.chasemc67.eightsleepwatch.grok.launch", provider: LaunchProvider()) { _ in
            LaunchWidgetView()
        }
        .configurationDisplayName("Eight Sleep Grok")
        .description("Opens bed temperature controls.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}
