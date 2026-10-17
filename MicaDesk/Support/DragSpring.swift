import Foundation

/// Offsets are in screen points and are never written to the card model.
struct DragSpring {
    struct Node {
        let id: UUID
        let parentID: UUID
        var offset: CGPoint = .zero
        var velocity: CGPoint = .zero
    }

    var rootID: UUID
    var nodes: [Node] // Parent before child.
    var rootOffset: CGPoint = .zero
    var reduceMotion = false
    private let stiffness: CGFloat = 200
    private let damping: CGFloat = 20
    private let maximumLag: CGFloat = 80

    var isSettled: Bool {
        nodes.allSatisfy { node in
            hypot(node.offset.x - rootOffset.x, node.offset.y - rootOffset.y) < 0.5 &&
            hypot(node.velocity.x, node.velocity.y) < 5
        }
    }

    mutating func step(_ elapsed: CGFloat) {
        let dt = min(max(elapsed, 0), 1.0 / 30.0)
        var offsets = [rootID: rootOffset]
        for index in nodes.indices {
            let target = offsets[nodes[index].parentID] ?? rootOffset
            if reduceMotion {
                nodes[index].offset = rootOffset
                nodes[index].velocity = .zero
            } else {
                var node = nodes[index]
                node.velocity.x += (stiffness * (target.x - node.offset.x) - damping * node.velocity.x) * dt
                node.velocity.y += (stiffness * (target.y - node.offset.y) - damping * node.velocity.y) * dt
                node.offset.x += node.velocity.x * dt
                node.offset.y += node.velocity.y * dt
                // Bound total lag from the root, including deep descendants.
                let dx = node.offset.x - rootOffset.x
                let dy = node.offset.y - rootOffset.y
                let distance = hypot(dx, dy)
                if distance > maximumLag {
                    node.offset = CGPoint(x: rootOffset.x + dx * maximumLag / distance,
                                          y: rootOffset.y + dy * maximumLag / distance)
                }
                nodes[index] = node
            }
            offsets[nodes[index].id] = nodes[index].offset
        }
    }
}
