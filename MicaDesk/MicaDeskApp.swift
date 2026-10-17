import SwiftData
import SwiftUI

@main
struct MicaDeskApp: App {
    var body: some Scene {
        WindowGroup {
            PriorityStackView()
        }
        .modelContainer(for: Card.self)
    }
}

