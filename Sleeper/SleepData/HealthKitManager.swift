import Foundation
import HealthKit

class HealthKitManager {
    let healthStore = HKHealthStore()

    func requestSleepAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        healthStore.requestAuthorization(toShare: nil, read: [sleepType]) { success, error in
            if success {
                print("Allowed")
            } else if let error = error {
                print("Error: \(error.localizedDescription)")
            }
        }
    }

    // 昨晩の睡眠データを取得
    func fetchLastNightSleepData(completion: @escaping (TimeInterval, TimeInterval, TimeInterval) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        // 過去24時間
        let endDate = Date()
        let calendar = Calendar.current
        guard let startDate = calendar.date(byAdding: .hour, value: -24, to: endDate) else { return }
        
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, results, error in
            guard let samples = results as? [HKCategorySample], error == nil else {
                completion(0, 0, 0)
                return
            }
            
            var totalSleepTime: TimeInterval = 0
            var remSleepTime: TimeInterval = 0
            var nonRemSleepTime: TimeInterval = 0
            
            for sample in samples {
                let duration = sample.endDate.timeIntervalSince(sample.startDate)
                
                // 睡眠ステージの判定）
                switch sample.value {
                case HKCategoryValueSleepAnalysis.asleepREM.rawValue:
                    // レム睡眠
                    remSleepTime += duration
                    totalSleepTime += duration
                    
                case HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                     HKCategoryValueSleepAnalysis.asleepDeep.rawValue:
                    // ノンレム睡眠
                    nonRemSleepTime += duration
                    totalSleepTime += duration
                    
                case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue:
                    totalSleepTime += duration
                    
                default:
                    break
                }
            }
            
            DispatchQueue.main.async {
                completion(totalSleepTime, remSleepTime, nonRemSleepTime)
            }
        }
        
        healthStore.execute(query)
    }
}
