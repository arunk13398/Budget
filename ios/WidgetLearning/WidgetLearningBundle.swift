//
//  WidgetLearningBundle.swift
//  WidgetLearning
//
//  Created by Arun k on 28/04/26.
//

import WidgetKit
import SwiftUI

@main
struct WidgetLearningBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOS 17.0, *) {
            WidgetLearning()
        }
        if #available(iOS 18.0, *) {
            WidgetLearningControl()
        }
        if #available(iOS 16.1, *) {
            WidgetLearningLiveActivity()
        }
    }
}
