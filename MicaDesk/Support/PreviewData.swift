import SwiftData

@MainActor
enum PreviewData {
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Card.self, configurations: configuration)
        let context = container.mainContext
        let first = Card(sortIndex: 0, title: "Sketch the launch note", bodyText: "A quiet place for the day's work.")
        let second = Card(sortIndex: 1, title: "Review details")
        let child = Card(parentID: first.id, sortIndex: 0, title: "Make the first pass")
        context.insert(first)
        context.insert(second)
        context.insert(child)
        return container
    }()
}

