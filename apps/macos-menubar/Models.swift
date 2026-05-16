import Foundation

struct DeviceRegistrationRequest: Encodable {
    let deviceName: String
    let runtimeType: String
    let permissionScope: String

    enum CodingKeys: String, CodingKey {
        case deviceName = "device_name"
        case runtimeType = "runtime_type"
        case permissionScope = "permission_scope"
    }
}

struct DeviceRegistrationResponse: Decodable {
    let device: RegisteredDevice
    let apiKey: String

    enum CodingKeys: String, CodingKey {
        case device
        case apiKey = "api_key"
    }
}

struct RegisteredDevice: Decodable {
    let deviceId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
    }
}

struct TaskSubmissionRequest: Encodable {
    let schemaVersion: String
    let intent: String
    let goal: TaskGoal
    let requiredTools: [String]
    let requiredCapabilities: [String]
    let complexityHint: String
    let permissionLevel: String
    let rawInput: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case intent
        case goal
        case requiredTools = "required_tools"
        case requiredCapabilities = "required_capabilities"
        case complexityHint = "complexity_hint"
        case permissionLevel = "permission_level"
        case rawInput = "raw_input"
    }
}

struct TaskGoal: Encodable {
    let description: String
}

struct TaskListResponse: Decodable {
    let tasks: [GemmaTask]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case tasks
        case nextCursor = "next_cursor"
    }
}

struct GemmaTask: Codable, Identifiable, Equatable {
    var id: String { taskId }

    let schemaVersion: String?
    let taskId: String
    let accountId: String?
    let taskTitle: String
    let intentSummary: String
    let permissionLevel: String?
    let currentState: String
    let currentRuntime: String?
    let requiredTools: [String]
    let requiredCapabilities: [String]
    let complexityHint: String?
    let submittedBy: String?
    let createdAt: String
    let lastUpdatedAt: String?
    let pendingApproval: Bool
    let totalRunCount: Int

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case taskId = "task_id"
        case accountId = "account_id"
        case taskTitle = "task_title"
        case intentSummary = "intent_summary"
        case permissionLevel = "permission_level"
        case currentState = "current_state"
        case currentRuntime = "current_runtime"
        case requiredTools = "required_tools"
        case requiredCapabilities = "required_capabilities"
        case complexityHint = "complexity_hint"
        case submittedBy = "submitted_by"
        case createdAt = "created_at"
        case lastUpdatedAt = "last_updated_at"
        case pendingApproval = "pending_approval"
        case totalRunCount = "total_run_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion)
        taskId = try container.decode(String.self, forKey: .taskId)
        accountId = try container.decodeIfPresent(String.self, forKey: .accountId)
        intentSummary = try container.decodeIfPresent(String.self, forKey: .intentSummary) ?? ""
        taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle) ?? intentSummary
        permissionLevel = try container.decodeIfPresent(String.self, forKey: .permissionLevel)
        currentState = try container.decode(String.self, forKey: .currentState)
        currentRuntime = try container.decodeIfPresent(String.self, forKey: .currentRuntime)
        requiredTools = try container.decodeIfPresent([String].self, forKey: .requiredTools) ?? []
        requiredCapabilities = try container.decodeIfPresent([String].self, forKey: .requiredCapabilities) ?? []
        complexityHint = try container.decodeIfPresent(String.self, forKey: .complexityHint)
        submittedBy = try container.decodeIfPresent(String.self, forKey: .submittedBy)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        lastUpdatedAt = try container.decodeIfPresent(String.self, forKey: .lastUpdatedAt)
        pendingApproval = try container.decodeIfPresent(Bool.self, forKey: .pendingApproval) ?? false
        totalRunCount = try container.decodeIfPresent(Int.self, forKey: .totalRunCount) ?? 0
    }
}

extension GemmaTask {
    var statusIcon: String {
        switch currentState {
        case "pending":
            return "⏳"
        case "routing":
            return "🔍"
        case "scheduled":
            return "📋"
        case "running":
            return "⚙️"
        case "paused":
            return "⏸️"
        case "completed":
            return "✅"
        case "failed":
            return "❌"
        case "cancelled":
            return "🚫"
        default:
            return "❓"
        }
    }

    var displaySummary: String {
        let summary = taskTitle.isEmpty ? intentSummary : taskTitle
        guard summary.count > 48 else {
            return summary
        }
        return String(summary.prefix(48)) + "..."
    }

    var isRunning: Bool {
        currentState == "running"
    }

    var isTerminal: Bool {
        ["completed", "failed", "cancelled"].contains(currentState)
    }
}

struct TaskEventsResponse: Codable {
    let events: [TaskEvent]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

struct TaskEvent: Codable, Identifiable, Equatable {
    var id: String { eventId }

    let eventId: String
    let eventType: String
    let payload: [String: JSONValue]

    enum CodingKeys: String, CodingKey {
        case eventId = "event_id"
        case eventType = "event_type"
        case payload
    }
}

enum JSONValue: Codable, Equatable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }
}

extension JSONValue {
    var displayString: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return values.map(\.displayString).joined(separator: ", ")
        case .object(let object):
            return object
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value.displayString)" }
                .joined(separator: ", ")
        case .null:
            return "null"
        }
    }
}
