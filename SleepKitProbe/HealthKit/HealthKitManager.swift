import Foundation
import Combine
import HealthKit
import SwiftUI
import UIKit

@MainActor
final class HealthKitManager: ObservableObject {
    @Published private(set) var healthDataAvailable: Bool
    @Published private(set) var permissionStatusDescription = "Not requested"
    @Published private(set) var observerRunning = false
    @Published private(set) var backgroundDeliveryStatus = "Not requested"
    @Published private(set) var activeSession: ProbeSession?
    @Published private(set) var samples: [SleepSampleRecord] = []
    @Published private(set) var observerEvents: [ObserverEventRecord] = []
    @Published private(set) var appEvents: [AppEventRecord] = []
    @Published private(set) var lastObserverTriggeredAt: Date?
    @Published private(set) var lastAnchoredAddedSampleCount = 0
    @Published private(set) var statusMessage = "Ready"
    @Published var exportedURLs: [URL] = []

    private let healthStore = HKHealthStore()
    private let sleepType: HKCategoryType?
    private let logger: ProbeLogger
    private var observerService: SleepObserverService?
    private var anchoredQueryService: SleepAnchoredQueryService?
    private static let observerEnabledKey = "SleepKitProbe.observerEnabled"

    convenience init() {
        self.init(logger: ProbeLogger())
    }

    init(logger: ProbeLogger) {
        self.logger = logger
        self.healthDataAvailable = HKHealthStore.isHealthDataAvailable()
        self.sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
        self.activeSession = Self.loadActiveSession()
        self.samples = logger.samples.sorted { $0.receivedAt > $1.receivedAt }
        self.observerEvents = logger.observerEvents.sorted { $0.triggeredAt > $1.triggeredAt }
        self.appEvents = logger.appEvents.sorted { $0.createdAt > $1.createdAt }

        if let sleepType {
            self.observerService = SleepObserverService(healthStore: healthStore, sleepType: sleepType)
            self.anchoredQueryService = SleepAnchoredQueryService(healthStore: healthStore, sleepType: sleepType)
        }
        logger.appendAppEvent(AppEventRecord(sessionId: activeSession?.id, name: "app_launch", detail: appStateDescription()))
        reloadFromLogger()

        if UserDefaults.standard.bool(forKey: Self.observerEnabledKey) {
            startObserver()
        }
    }

    var recordCount: Int {
        logger.recordCount
    }

    var logFileSizeDescription: String {
        ByteCountFormatter.string(fromByteCount: logger.logFileSize, countStyle: .file)
    }

    var totalAsleepDurationDescription: String {
        let end = Date()
        let start = end.addingTimeInterval(-86_400)
        return durationDescription(DurationAggregation.asleepDuration(records: samples, in: start...end))
    }

    var recentSamplesForDisplay: [SleepSampleRecord] {
        let cutoff = Date().addingTimeInterval(-7 * 86_400)
        return samples.filter { sample in
            sample.sampleEndDate >= cutoff || sample.receivedAt >= cutoff
        }
    }

    func requestHealthKitPermission() {
        guard healthDataAvailable else {
            permissionStatusDescription = "Health data is not available on this device"
            return
        }
        guard let sleepType else {
            permissionStatusDescription = "Sleep Analysis type is unavailable"
            return
        }

        healthStore.requestAuthorization(toShare: [], read: [sleepType]) { [weak self] success, error in
            guard let manager = self else { return }
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                if success {
                    manager.permissionStatusDescription = "Requested. HealthKit does not expose read permission status directly."
                    manager.statusMessage = "HealthKit permission request finished"
                    manager.logger.appendAppEvent(AppEventRecord(sessionId: manager.activeSession?.id, name: "healthkit_permission_requested", detail: nil))
                    manager.enableBackgroundDelivery()
                } else {
                    manager.permissionStatusDescription = "Request failed: \(errorDescription ?? "unknown error")"
                    manager.statusMessage = manager.permissionStatusDescription
                    manager.logger.appendAppEvent(AppEventRecord(sessionId: manager.activeSession?.id, name: "healthkit_permission_failed", detail: errorDescription))
                }
                manager.reloadFromLogger()
            }
        }
    }

    func enableBackgroundDelivery() {
        guard let sleepType else { return }
        healthStore.enableBackgroundDelivery(for: sleepType, frequency: .immediate) { [weak self] success, error in
            guard let manager = self else { return }
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                if success {
                    manager.backgroundDeliveryStatus = "Enabled (.immediate requested; iOS still controls actual timing)"
                } else {
                    manager.backgroundDeliveryStatus = "Failed: \(errorDescription ?? "unknown error")"
                }
                manager.logger.appendAppEvent(
                    AppEventRecord(
                        sessionId: manager.activeSession?.id,
                        name: "background_delivery",
                        detail: manager.backgroundDeliveryStatus
                    )
                )
                manager.reloadFromLogger()
            }
        }
    }

    func startObserver() {
        guard let observerService, let anchoredQueryService else {
            statusMessage = "Sleep Analysis HealthKit type is unavailable"
            return
        }

        statusMessage = "Preparing HealthKit anchor"
        anchoredQueryService.bootstrapAnchorIfNeeded { [weak self] bootstrapResult in
            Task { @MainActor in
                guard let manager = self else { return }
                if let error = bootstrapResult.error {
                    manager.statusMessage = "Anchor setup failed: \(error.localizedDescription)"
                    manager.logger.appendAppEvent(
                        AppEventRecord(
                            sessionId: manager.activeSession?.id,
                            name: "observer_anchor_bootstrap_failed",
                            detail: error.localizedDescription
                        )
                    )
                    manager.reloadFromLogger()
                    return
                }

                if bootstrapResult.historicalSampleCount > 0 || bootstrapResult.deletedObjectCount > 0 {
                    manager.logger.appendAppEvent(
                        AppEventRecord(
                            sessionId: manager.activeSession?.id,
                            name: "observer_anchor_bootstrapped",
                            detail: "Skipped \(bootstrapResult.historicalSampleCount) historical samples and \(bootstrapResult.deletedObjectCount) deleted objects"
                        )
                    )
                }

                manager.startObserverAfterAnchorBootstrap(observerService: observerService, anchoredQueryService: anchoredQueryService)
            }
        }
    }

    private func startObserverAfterAnchorBootstrap(
        observerService: SleepObserverService,
        anchoredQueryService: SleepAnchoredQueryService
    ) {
        observerService.start { [weak self, weak anchoredQueryService] triggeredAt, observerError, completion in
            guard let manager = self, let anchoredQueryService else {
                completion()
                return
            }
            Task { @MainActor in
                manager.lastObserverTriggeredAt = triggeredAt
                manager.statusMessage = "Observer triggered at \(DateFormatters.displayString(triggeredAt))"

                anchoredQueryService.fetchUpdates(
                    queryTriggeredAt: triggeredAt,
                    sessionId: manager.activeSession?.id,
                    syncSource: "observerAnchoredQuery"
                ) { result in
                    Task { @MainActor in
                        let errorDescription = observerError?.localizedDescription ?? result.error?.localizedDescription
                        manager.lastAnchoredAddedSampleCount = result.samples.count
                        manager.logger.appendSamples(result.samples)
                        manager.logger.appendObserverEvent(
                            ObserverEventRecord(
                                sessionId: manager.activeSession?.id,
                                triggeredAt: triggeredAt,
                                anchoredQueryStartedAt: result.queryStartedAt,
                                anchoredQueryFinishedAt: result.queryFinishedAt,
                                addedSampleCount: result.samples.count,
                                deletedObjectCount: result.deletedObjectCount,
                                errorDescription: errorDescription,
                                appStateDescription: manager.appStateDescription()
                            )
                        )
                        manager.statusMessage = "Anchored query read \(result.samples.count) samples"
                        manager.reloadFromLogger()
                        completion()
                    }
                }
            }
        }
        observerRunning = true
        UserDefaults.standard.set(true, forKey: Self.observerEnabledKey)
        statusMessage = "Observer started"
        logger.appendAppEvent(AppEventRecord(sessionId: activeSession?.id, name: "observer_started", detail: nil))
        enableBackgroundDelivery()
        reloadFromLogger()
    }

    func manualRefreshLast24Hours() {
        manualRefresh(daysBack: 1, syncSource: "manualRefresh")
    }

    func manualRefreshLast7Days() {
        manualRefresh(daysBack: 7, syncSource: "manualRefresh7d")
    }

    func startNightProbe() {
        let session = ProbeSession()
        activeSession = session
        Self.saveActiveSession(session)
        logger.appendAppEvent(AppEventRecord(sessionId: session.id, name: "probe_session_started", detail: nil))
        statusMessage = "Night probe started"
        reloadFromLogger()
    }

    func endNightProbe() {
        guard var session = activeSession else { return }
        session.endedAt = Date()
        activeSession = nil
        UserDefaults.standard.set(false, forKey: Self.observerEnabledKey)
        Self.clearActiveSession()
        logger.appendAppEvent(AppEventRecord(sessionId: session.id, name: "probe_session_ended", detail: nil))
        statusMessage = "Night probe ended"
        reloadFromLogger()
    }

    func exportCSV() {
        do {
            exportedURLs = try logger.writeCSVExports()
            logger.appendAppEvent(AppEventRecord(sessionId: activeSession?.id, name: "export_csv", detail: exportedURLs.map(\.lastPathComponent).joined(separator: ", ")))
            statusMessage = "CSV export ready"
            reloadFromLogger()
        } catch {
            statusMessage = "CSV export failed: \(error.localizedDescription)"
        }
    }

    func exportJSONL() {
        do {
            exportedURLs = [try logger.writeJSONLExport()]
            logger.appendAppEvent(AppEventRecord(sessionId: activeSession?.id, name: "export_jsonl", detail: exportedURLs.first?.lastPathComponent))
            statusMessage = "JSONL export ready"
            reloadFromLogger()
        } catch {
            statusMessage = "JSONL export failed: \(error.localizedDescription)"
        }
    }

    func clearLocalLogs() {
        observerService?.stop()
        observerRunning = false
        logger.clear()
        anchoredQueryService?.resetAnchor()
        activeSession = nil
        Self.clearActiveSession()
        lastObserverTriggeredAt = nil
        lastAnchoredAddedSampleCount = 0
        statusMessage = "Local logs and HealthKit anchor cleared"
        reloadFromLogger()
    }

    private func manualRefresh(daysBack: Int, syncSource: String) {
        guard let sleepType else {
            statusMessage = "Sleep Analysis HealthKit type is unavailable"
            return
        }
        let startedAt = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBack, to: startedAt) ?? startedAt.addingTimeInterval(-Double(daysBack) * 86_400)
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: startedAt, options: [])
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(
            sampleType: sleepType,
            predicate: predicate,
            limit: HKObjectQueryNoLimit,
            sortDescriptors: [sort]
        ) { [weak self] _, samplesOrNil, error in
            guard let manager = self else { return }
            let receivedAt = Date()
            let errorDescription = error?.localizedDescription
            Task { @MainActor in
                if let errorDescription {
                    manager.statusMessage = "Manual refresh failed: \(errorDescription)"
                    manager.logger.appendAppEvent(AppEventRecord(sessionId: manager.activeSession?.id, name: "manual_refresh_failed", detail: errorDescription))
                    manager.reloadFromLogger()
                    return
                }

                let records = (samplesOrNil ?? [])
                    .compactMap { $0 as? HKCategorySample }
                    .map {
                        SleepSampleMapper.map(
                            sample: $0,
                            receivedAt: receivedAt,
                            queryTriggeredAt: startedAt,
                            sessionId: manager.activeSession?.id,
                            syncSource: syncSource
                        )
                    }
                manager.logger.appendSamples(records)
                manager.logger.appendAppEvent(AppEventRecord(sessionId: manager.activeSession?.id, name: syncSource, detail: "\(records.count) samples"))
                manager.statusMessage = "Manual refresh read \(records.count) samples"
                manager.reloadFromLogger()
            }
        }
        statusMessage = "Manual refresh started"
        healthStore.execute(query)
    }

    private func reloadFromLogger() {
        samples = logger.samples.sorted { $0.receivedAt > $1.receivedAt }
        observerEvents = logger.observerEvents.sorted { $0.triggeredAt > $1.triggeredAt }
        appEvents = logger.appEvents.sorted { $0.createdAt > $1.createdAt }
    }

    private func durationDescription(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }

    private func appStateDescription() -> String {
        switch UIApplication.shared.applicationState {
        case .active:
            return "active"
        case .inactive:
            return "inactive"
        case .background:
            return "background"
        @unknown default:
            return "unknown"
        }
    }

    private static var activeSessionURL: URL {
        FileStore.applicationSupportDirectory.appendingPathComponent("active_session.json")
    }

    private static func loadActiveSession() -> ProbeSession? {
        guard let data = try? Data(contentsOf: activeSessionURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .formatted(DateFormatters.iso8601)
        return try? decoder.decode(ProbeSession.self, from: data)
    }

    private static func saveActiveSession(_ session: ProbeSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .formatted(DateFormatters.iso8601)
        guard let data = try? encoder.encode(session) else { return }
        try? data.write(to: activeSessionURL, options: [.atomic])
    }

    private static func clearActiveSession() {
        try? FileManager.default.removeItem(at: activeSessionURL)
    }
}
