import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var parentID: UUID?
    var sortIndex: Int
    var title: String
    var bodyText: String
    @Attribute(.externalStorage) var drawingData: Data
    var isCollapsed: Bool
    var isCompleted: Bool
    // Optional so existing stores migrate without requiring a value for old rows.
    var colorName: String?
    var positionX: Double?
    var positionY: Double?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        sortIndex: Int = 0,
        title: String = "",
        bodyText: String = "",
        drawingData: Data = Data(),
        isCollapsed: Bool = false,
        isCompleted: Bool = false,
        colorName: String? = nil,
        positionX: Double? = nil,
        positionY: Double? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.parentID = parentID
        self.sortIndex = sortIndex
        self.title = title
        self.bodyText = bodyText
        self.drawingData = drawingData
        self.isCollapsed = isCollapsed
        self.isCompleted = isCompleted
        self.colorName = colorName
        self.positionX = positionX
        self.positionY = positionY
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

