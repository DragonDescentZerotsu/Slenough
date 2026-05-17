import Foundation

enum ProbeLogLine: Codable {
    case sleepSample(SleepSampleRecord)
    case observerEvent(ObserverEventRecord)
    case appEvent(AppEventRecord)

    enum CodingKeys: String, CodingKey {
        case type
        case payload
    }

    enum LineType: String, Codable {
        case sleepSample = "sleep_sample"
        case observerEvent = "observer_event"
        case appEvent = "app_event"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(LineType.self, forKey: .type)
        switch type {
        case .sleepSample:
            self = .sleepSample(try container.decode(SleepSampleRecord.self, forKey: .payload))
        case .observerEvent:
            self = .observerEvent(try container.decode(ObserverEventRecord.self, forKey: .payload))
        case .appEvent:
            self = .appEvent(try container.decode(AppEventRecord.self, forKey: .payload))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sleepSample(let record):
            try container.encode(LineType.sleepSample, forKey: .type)
            try container.encode(record, forKey: .payload)
        case .observerEvent(let record):
            try container.encode(LineType.observerEvent, forKey: .type)
            try container.encode(record, forKey: .payload)
        case .appEvent(let record):
            try container.encode(LineType.appEvent, forKey: .type)
            try container.encode(record, forKey: .payload)
        }
    }
}
