import SwiftUI

struct TaskStateDisplay {
    let icon: String
    let color: Color

    static func from(_ state: String) -> TaskStateDisplay {
        switch state {
        case "pending":
            return TaskStateDisplay(icon: "⏳", color: .secondary)
        case "routing":
            return TaskStateDisplay(icon: "🔍", color: .blue)
        case "scheduled":
            return TaskStateDisplay(icon: "📋", color: .blue)
        case "running":
            return TaskStateDisplay(icon: "⚙️", color: .orange)
        case "paused":
            return TaskStateDisplay(icon: "⏸️", color: .yellow)
        case "completed":
            return TaskStateDisplay(icon: "✅", color: .green)
        case "failed":
            return TaskStateDisplay(icon: "❌", color: .red)
        case "cancelled":
            return TaskStateDisplay(icon: "🚫", color: Color(.systemGray))
        default:
            return TaskStateDisplay(icon: "❓", color: .secondary)
        }
    }
}
