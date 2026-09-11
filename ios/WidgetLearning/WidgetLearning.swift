//
//  WidgetLearning.swift
//  WidgetLearning
//
//  Created by Arun k on 28/04/26.
//

import WidgetKit
import SwiftUI
import AppIntents

@available(iOS 17.0, *)
struct SimpleEntry: TimelineEntry {
    let date: Date
    let configuration: ConfigurationAppIntent
    let currentValue: String
    let maxValue: String
    let remainingBudget: String
    let progress: Int
    let monthName: String
    let cardName: String
    let pieChartPath: String?
    let lineChartPath: String?
}

@available(iOS 17.0, *)
struct WidgetLearningEntryView : View {
    var entry: Provider.Entry

    var body: some View {
        Group {
            if let piePath = entry.pieChartPath, !piePath.isEmpty, entry.configuration.favoriteEmoji == "🍕" {
                chartView(path: piePath, title: "SPENDING SPLIT")
            } else if let linePath = entry.lineChartPath, !linePath.isEmpty, entry.configuration.favoriteEmoji == "📈" {
                chartView(path: linePath, title: "SPENDING TREND")
            } else {
                cardView
            }
        }
        .containerBackground(
            LinearGradient(
                colors: [Color.white, Color(red: 0.95, green: 0.98, blue: 1.0)],
                startPoint: .bottom,
                endPoint: .top
            ),
            for: .widget
        )
    }

    var cardView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.cardName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(intent: SyncIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("₹")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.black.opacity(0.5))
                Text(entry.currentValue)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .padding(.top, 2)
            
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("LIMIT")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.secondary.opacity(0.8))
                    Text("₹\(entry.maxValue)")
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                Spacer()
                
                Text(entry.monthName)
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black)
                    .foregroundColor(.white)
                    .cornerRadius(4)
            }
            .padding(.top, 4)
            
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(white: 0.92))
                        .frame(height: 8)
                    
                    RoundedRectangle(cornerRadius: 10)
                        .fill(progressGradient(for: entry.currentValue))
                        .frame(width: geometry.size.width * CGFloat(min(max(Double(entry.progress) / 100.0, 0), 1.0)), height: 8)
                }
            }
            .frame(height: 8)
            .padding(.top, 6)
        }
        .padding(16)
    }

    func chartView(path: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.secondary)
                Spacer()
                Button(intent: SyncIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
            
            if let uiImage = UIImage(contentsOfFile: path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
                Text("No data")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding(16)
    }
    
    private func progressGradient(for valueStr: String) -> LinearGradient {
        let value = Double(valueStr) ?? 0
        if value <= 8000 { return LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing) }
        if value <= 12000 { return LinearGradient(colors: [.green, .mint], startPoint: .leading, endPoint: .trailing) }
        if value <= 18000 { return LinearGradient(colors: [.orange, .yellow], startPoint: .leading, endPoint: .trailing) }
        return LinearGradient(colors: [.red, .orange], startPoint: .leading, endPoint: .trailing)
    }
}

@available(iOS 17.0, *)
struct WidgetLearning: Widget {
    let kind: String = "WidgetLearning"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ConfigurationAppIntent.self, provider: Provider()) { entry in
            WidgetLearningEntryView(entry: entry)
        }
        .configurationDisplayName("Budget Widget")
        .description("Keep track of your spending.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(iOS 17.0, *)
struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SimpleEntry {
        SimpleEntry(date: Date(), configuration: ConfigurationAppIntent(), currentValue: "0", maxValue: "21000", remainingBudget: "21000", progress: 0, monthName: "JAN", cardName: "Total", pieChartPath: nil, lineChartPath: nil)
    }

    func snapshot(for configuration: ConfigurationAppIntent, in context: Context) async -> SimpleEntry {
        let userDefaults = UserDefaults(suiteName: "group.nagavalliApp")
        return SimpleEntry(
            date: Date(),
            configuration: configuration,
            currentValue: userDefaults?.string(forKey: "current_value") ?? "0",
            maxValue: userDefaults?.string(forKey: "max_value") ?? "21000",
            remainingBudget: userDefaults?.string(forKey: "remaining_budget") ?? "21000",
            progress: userDefaults?.integer(forKey: "progress") ?? 0,
            monthName: userDefaults?.string(forKey: "month_name") ?? "JAN",
            cardName: userDefaults?.string(forKey: "card_name") ?? "Total",
            pieChartPath: userDefaults?.string(forKey: "pie_chart_path"),
            lineChartPath: userDefaults?.string(forKey: "line_chart_path")
        )
    }
    
    func timeline(for configuration: ConfigurationAppIntent, in context: Context) async -> Timeline<SimpleEntry> {
        let userDefaults = UserDefaults(suiteName: "group.nagavalliApp")
        let entry = SimpleEntry(
            date: Date(),
            configuration: configuration,
            currentValue: userDefaults?.string(forKey: "current_value") ?? "0",
            maxValue: userDefaults?.string(forKey: "max_value") ?? "21000",
            remainingBudget: userDefaults?.string(forKey: "remaining_budget") ?? "21000",
            progress: userDefaults?.integer(forKey: "progress") ?? 0,
            monthName: userDefaults?.string(forKey: "month_name") ?? "JAN",
            cardName: userDefaults?.string(forKey: "card_name") ?? "Total",
            pieChartPath: userDefaults?.string(forKey: "pie_chart_path"),
            lineChartPath: userDefaults?.string(forKey: "line_chart_path")
        )
        return Timeline(entries: [entry], policy: .atEnd)
    }
}

@available(iOS 17.0, *)
extension ConfigurationAppIntent {
    fileprivate static var smiley: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "😀"
        return intent
    }
    
    fileprivate static var starEyes: ConfigurationAppIntent {
        let intent = ConfigurationAppIntent()
        intent.favoriteEmoji = "🤩"
        return intent
    }
}

#Preview(as: .systemSmall) {
    WidgetLearning()
} timeline: {
    SimpleEntry(date: .now, configuration: .smiley, currentValue: "8000", maxValue: "21000", remainingBudget: "13000", progress: 38, monthName: "JAN", cardName: "Total", pieChartPath: nil, lineChartPath: nil)
    SimpleEntry(date: .now, configuration: .starEyes, currentValue: "15000", maxValue: "21000", remainingBudget: "6000", progress: 71, monthName: "FEB", cardName: "Total", pieChartPath: nil, lineChartPath: nil)
}
