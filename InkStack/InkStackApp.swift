import SwiftData
import SwiftUI

@main
struct InkStackApp: App {
    var body: some Scene {
        WindowGroup {
            PriorityStackView()
        }
        .modelContainer(for: Card.self)
    }
}

