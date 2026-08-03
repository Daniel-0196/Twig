import Foundation
import SwiftData

public enum EdgeType: String, Codable {
    case sequence, reference
}

@Model
public final class Edge {
    public var type: EdgeType
    public var from: Goal?
    public var to: Goal?

    public init(type: EdgeType, from: Goal, to: Goal) {
        self.type = type
        self.from = from
        self.to = to
    }
}
