import CoreGraphics
import Foundation

public struct AccessibilityRect: Equatable, Sendable {
    public let x: CGFloat
    public let y: CGFloat
    public let width: CGFloat
    public let height: CGFloat

    public init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct AccessibilityElement: Identifiable, Equatable, Sendable {
    public let id: String
    public let path: String
    public let label: String
    public let value: String
    public let role: String
    public let type: String
    public let enabled: Bool
    public let frame: AccessibilityRect

    public init(
        id: String,
        path: String,
        label: String,
        value: String,
        role: String,
        type: String,
        enabled: Bool,
        frame: AccessibilityRect
    ) {
        self.id = id
        self.path = path
        self.label = label
        self.value = value
        self.role = role
        self.type = type
        self.enabled = enabled
        self.frame = frame
    }
}

public struct AccessibilitySnapshot: Equatable, Sendable {
    public let screen: CGSize
    public let elements: [AccessibilityElement]

    public init(screen: CGSize, elements: [AccessibilityElement]) {
        self.screen = screen
        self.elements = elements
    }
}

public enum SimulatorAccessibility {
    public static func snapshot(deviceUDID: String, maxElements: Int = 500) throws -> AccessibilitySnapshot {
        let data = try AccessibilityBridge.shared.describeUI(udid: deviceUDID)
        let roots = try JSONDecoder().decode([RawAccessibilityNode].self, from: data)
        return normalize(roots: roots, maxElements: maxElements)
    }

    public static func rawJSON(deviceUDID: String) throws -> Data {
        try AccessibilityBridge.shared.describeUI(udid: deviceUDID)
    }

    private static func normalize(roots: [RawAccessibilityNode], maxElements: Int) -> AccessibilitySnapshot {
        let screenFrame = roots.first?.frame ?? AccessibilityRect(x: 0, y: 0, width: 1, height: 1)
        var elements: [AccessibilityElement] = []

        func visit(_ node: RawAccessibilityNode, path: String) {
            guard elements.count < maxElements else { return }

            let isScreenSized = sameRect(node.frame, screenFrame)
            if !isScreenSized {
                elements.append(
                    AccessibilityElement(
                        id: node.axUniqueId ?? path,
                        path: path,
                        label: node.axLabel ?? "",
                        value: node.axValue ?? "",
                        role: node.roleDescription,
                        type: node.type,
                        enabled: node.enabled,
                        frame: node.frame
                    )
                )
            }

            for (index, child) in node.children.enumerated() where elements.count < maxElements {
                visit(child, path: "\(path).\(index)")
            }
        }

        for (index, root) in roots.enumerated() where elements.count < maxElements {
            visit(root, path: "\(index)")
        }

        return AccessibilitySnapshot(
            screen: CGSize(width: screenFrame.width, height: screenFrame.height),
            elements: elements
        )
    }

    private static func sameRect(_ lhs: AccessibilityRect, _ rhs: AccessibilityRect) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 &&
            abs(lhs.y - rhs.y) < 0.5 &&
            abs(lhs.width - rhs.width) < 0.5 &&
            abs(lhs.height - rhs.height) < 0.5
    }
}

private struct RawAccessibilityNode: Decodable {
    let axUniqueId: String?
    let axLabel: String?
    let axValue: String?
    let enabled: Bool
    let frame: AccessibilityRect
    let roleDescription: String
    let type: String
    let children: [RawAccessibilityNode]

    private enum CodingKeys: String, CodingKey {
        case axUniqueId = "AXUniqueId"
        case axLabel = "AXLabel"
        case axValue = "AXValue"
        case enabled
        case frame
        case roleDescription = "role_description"
        case type
        case children
    }
}

extension AccessibilityRect: Decodable {
    private enum CodingKeys: String, CodingKey {
        case x
        case y
        case width
        case height
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            x: try container.decode(CGFloat.self, forKey: .x),
            y: try container.decode(CGFloat.self, forKey: .y),
            width: try container.decode(CGFloat.self, forKey: .width),
            height: try container.decode(CGFloat.self, forKey: .height)
        )
    }
}
