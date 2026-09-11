//
//  WidgetLearningLiveActivity.swift
//  WidgetLearning
//
//  Created by Arun k on 28/04/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

@available(iOS 16.1, *)
struct WidgetLearningAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

@available(iOS 16.1, *)
struct WidgetLearningLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WidgetLearningAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

@available(iOS 16.1, *)
extension WidgetLearningAttributes {
    fileprivate static var preview: WidgetLearningAttributes {
        WidgetLearningAttributes(name: "World")
    }
}

@available(iOS 16.1, *)
extension WidgetLearningAttributes.ContentState {
    fileprivate static var smiley: WidgetLearningAttributes.ContentState {
        WidgetLearningAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: WidgetLearningAttributes.ContentState {
         WidgetLearningAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: WidgetLearningAttributes.preview) {
   WidgetLearningLiveActivity()
} contentStates: {
    WidgetLearningAttributes.ContentState.smiley
    WidgetLearningAttributes.ContentState.starEyes
}
