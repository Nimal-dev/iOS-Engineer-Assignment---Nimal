//
//  ios_Engineer_AssignementApp.swift
//  ios Engineer Assignement
//
//  Created by nikhil  on 21/07/26.
//

import SwiftUI
import CoreData

@main
struct ios_Engineer_AssignementApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
