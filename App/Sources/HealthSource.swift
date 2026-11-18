import HealthKit
import LoggerCore

/// Reads sleep and workouts from Apple Health, and asks Health to wake the
/// app when new ones are saved (for example when Withings or your watch syncs
/// a night).
final class HealthSource {
    static let shared = HealthSource()
    let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let workoutType = HKObjectType.workoutType()

    var available: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [sleepType, workoutType])
    }

    /// Sets up the wake-ups. Must run at every launch, before the app finishes launching.
    func startObserving() {
        guard available else { return }
        for type in [sleepType, workoutType] as [HKSampleType] {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                guard error == nil else { completion(); return }
                Task {
                    await SyncCoordinator.shared.syncHealth(reason: "New data in Apple Health")
                    completion()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
        }
    }

    func sleepSamples(from: Date, to: Date) async throws -> [SleepSample] {
        let samples = try await samples(sleepType, from: from, to: to)
        return samples.compactMap { s -> SleepSample? in
            guard let c = s as? HKCategorySample, let stage = Self.stage(c.value) else { return nil }
            return SleepSample(
                uuid: c.uuid.uuidString,
                start: Int64(c.startDate.timeIntervalSince1970 * 1000),
                end: Int64(c.endDate.timeIntervalSince1970 * 1000),
                stage: stage,
                source: c.sourceRevision.source.name)
        }
    }

    func workouts(from: Date, to: Date) async throws -> [WorkoutInfo] {
        let samples = try await samples(workoutType, from: from, to: to)
        return samples.compactMap { s -> WorkoutInfo? in
            guard let w = s as? HKWorkout else { return nil }
            return WorkoutInfo(
                uuid: w.uuid.uuidString,
                name: Self.name(w.workoutActivityType),
                start: Int64(w.startDate.timeIntervalSince1970 * 1000),
                end: Int64(w.endDate.timeIntervalSince1970 * 1000),
                source: w.sourceRevision.source.name)
        }
    }

    private func samples(_ type: HKSampleType, from: Date, to: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { cont in
            let predicate = HKQuery.predicateForSamples(withStart: from, end: to, options: [])
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, results, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: results ?? []) }
            }
            store.execute(q)
        }
    }

    private static func stage(_ value: Int) -> SleepSample.Stage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleep
        case .asleepCore: return .core
        case .asleepDeep: return .deep
        case .asleepREM: return .rem
        case .awake: return .awake
        default: return nil
        }
    }

    /// Names as the Android app writes them, so calendar titles match.
    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .badminton: return "Badminton"
        case .baseball: return "Baseball"
        case .basketball: return "Basketball"
        case .cycling: return "Bike ride"
        case .boxing: return "Boxing"
        case .cricket: return "Cricket"
        case .socialDance, .cardioDance: return "Dance"
        case .elliptical: return "Elliptical"
        case .golf: return "Golf"
        case .highIntensityIntervalTraining: return "HIIT"
        case .hiking: return "Hike"
        case .martialArts: return "Martial arts"
        case .pilates: return "Pilates"
        case .climbing: return "Climbing"
        case .rowing: return "Rowing"
        case .running: return "Run"
        case .downhillSkiing, .crossCountrySkiing: return "Skiing"
        case .snowboarding: return "Snowboarding"
        case .soccer: return "Soccer"
        case .squash: return "Squash"
        case .stairClimbing, .stairs: return "Stair climb"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength training"
        case .flexibility: return "Stretching"
        case .surfingSports: return "Surfing"
        case .swimming: return "Swim"
        case .tableTennis: return "Table tennis"
        case .tennis: return "Tennis"
        case .volleyball: return "Volleyball"
        case .walking: return "Walk"
        case .yoga: return "Yoga"
        case .coreTraining: return "Core training"
        case .mixedCardio: return "Cardio"
        default: return "Workout"
        }
    }
}
