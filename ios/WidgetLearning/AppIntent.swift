//
//  AppIntent.swift
//  WidgetLearning
//
//  Created by Arun k on 28/04/26.
//

import WidgetKit
import AppIntents

@available(iOS 17.0, *)
struct ConfigurationAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Configuration" }
    static var description: IntentDescription { "This is an example widget." }

    // An example configurable parameter.
    @Parameter(title: "Widget Type", default: "💳")
    var favoriteEmoji: String
}

@available(iOS 17.0, *)
struct SyncIntent: AppIntent {
    static var title: LocalizedStringResource { "Sync Data" }
    static var description: IntentDescription { "Triggers a sync of your spending data." }

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: "group.nagavalliApp")?.set(true, forKey: "trigger_sync")
        return .result()
    }
}
