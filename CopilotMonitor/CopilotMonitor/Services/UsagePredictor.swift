//
//  UsagePredictor.swift
//  CopilotMonitor
//
//  Created by opencode on 2026-01-18.
//

import Foundation

/// 월말 사용량 예측 결과
struct UsagePrediction {
    let predictedMonthlyRequests: Double  // 월말 예상 총 요청
    let predictedBilledAmount: Double     // 예상 추가 비용
    let confidenceLevel: ConfidenceLevel  // low/medium/high
    let daysUsedForPrediction: Int        // 예측에 사용된 일수
}

/// 예측 정확도 레벨
enum ConfidenceLevel: String {
    case low = "예측 정확도 낮음"
    case medium = "예측 정확도 보통"
    case high = "예측 정확도 높음"
}

/// 사용량 예측 알고리즘 구현
/// - 최근 7일 가중치 기반 예측
/// - 요일별 패턴 고려 (주중/주말 차이)
class UsagePredictor {
    // UTC 캘린더 사용 (DailyUsage.date가 UTC이므로)
    private let utcCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()
    
    // 가중치 배열: 최신 데이터에 더 높은 가중치 부여
    // [오늘-1, 오늘-2, 오늘-3, 오늘-4, 오늘-5, 오늘-6, 오늘-7]
    private let weights: [Double] = [1.5, 1.5, 1.2, 1.2, 1.2, 1.0, 1.0]
    
    // 요청당 비용 (고정값)
    private let costPerRequest: Double = 0.04  // $0.04/request
    
    /// 월말 사용량 및 비용 예측
    /// - Parameters:
    ///   - history: 일별 사용량 히스토리
    ///   - currentUsage: 현재 사용량 정보 (limit 포함)
    /// - Returns: 예측 결과
    func predict(history: UsageHistory, currentUsage: CopilotUsage) -> UsagePrediction {
        let dailyData = history.days
        
        // Edge case: 데이터가 없는 경우
        guard !dailyData.isEmpty else {
            return UsagePrediction(
                predictedMonthlyRequests: 0,
                predictedBilledAmount: 0,
                confidenceLevel: .low,
                daysUsedForPrediction: 0
            )
        }
        
        // Step 1: 가중 평균 일일 사용량 계산
        let weightedAvgDailyUsage = calculateWeightedAverageDailyUsage(dailyData: dailyData)
        
        // Step 2: 주중/주말 패턴 보정
        let weekendRatio = calculateWeekendRatio(dailyData: dailyData)
        
        // Step 3: 남은 일수 계산
        let today = Date()  // UTC 기준 오늘 날짜
        let daysInMonth = utcCalendar.range(of: .day, in: .month, for: today)?.count ?? 30
        let currentDay = utcCalendar.component(.day, from: today)
        let remainingDays = daysInMonth - currentDay
        
        let (remainingWeekdays, remainingWeekends) = countRemainingWeekdaysAndWeekends(
            from: today,
            remainingDays: remainingDays
        )
        
        // Step 4: 월말 예상 총 사용량
        let predictedRemainingWeekdayUsage = weightedAvgDailyUsage * Double(remainingWeekdays)
        let predictedRemainingWeekendUsage = weightedAvgDailyUsage * weekendRatio * Double(remainingWeekends)
        
        let currentTotalUsage = history.totalIncludedRequests
        let predictedMonthlyTotal = currentTotalUsage + predictedRemainingWeekdayUsage + predictedRemainingWeekendUsage
        
        // Step 5: 예상 추가 비용 계산
        let limit = Double(currentUsage.limitRequests)
        let predictedBilledAmount: Double
        
        if predictedMonthlyTotal > limit {
            let excessRequests = predictedMonthlyTotal - limit
            predictedBilledAmount = excessRequests * costPerRequest
        } else {
            predictedBilledAmount = 0
        }
        
        // Step 6: Confidence Level 결정
        let daysUsed = dailyData.count
        let confidenceLevel: ConfidenceLevel
        
        if daysUsed < 3 {
            confidenceLevel = .low
        } else if daysUsed < 7 {
            confidenceLevel = .medium
        } else {
            confidenceLevel = .high
        }
        
        return UsagePrediction(
            predictedMonthlyRequests: predictedMonthlyTotal,
            predictedBilledAmount: predictedBilledAmount,
            confidenceLevel: confidenceLevel,
            daysUsedForPrediction: daysUsed
        )
    }
    
    // MARK: - Step 1: 가중 평균 계산
    
    /// 가중치 기반 평균 일일 사용량 계산
    /// - Parameter dailyData: 일별 사용량 배열 (최신순 정렬 필요)
    /// - Returns: 가중 평균 일일 사용량
    private func calculateWeightedAverageDailyUsage(dailyData: [DailyUsage]) -> Double {
        // 최신순으로 정렬 (date 내림차순)
        let sortedData = dailyData.sorted { $0.date > $1.date }
        
        var weightedSum: Double = 0
        var totalWeight: Double = 0
        
        // 최대 7일까지만 사용 (weights 배열 크기)
        let daysToUse = min(sortedData.count, weights.count)
        
        for i in 0..<daysToUse {
            let usage = sortedData[i].includedRequests  // Already Double
            let weight = weights[i]
            weightedSum += usage * weight
            totalWeight += weight
        }
        
        // 가중치합이 0인 경우 방지
        guard totalWeight > 0 else {
            return 0
        }
        
        return weightedSum / totalWeight
    }
    
    // MARK: - Step 2: 주중/주말 패턴 보정
    
    /// 주중 대비 주말 사용량 비율 계산
    /// - Parameter dailyData: 일별 사용량 배열
    /// - Returns: 주말 비율 (주말평균 / 주중평균)
    private func calculateWeekendRatio(dailyData: [DailyUsage]) -> Double {
        var weekdaySum: Double = 0
        var weekendSum: Double = 0
        var weekdayCount: Int = 0
        var weekendCount: Int = 0
        
        for day in dailyData {
            let weekday = utcCalendar.component(.weekday, from: day.date)
            
            // weekday: 1=일요일, 2=월요일, ..., 7=토요일
            if weekday == 1 || weekday == 7 {
                // 주말 (일, 토)
                weekendSum += day.includedRequests
                weekendCount += 1
            } else {
                // 주중 (월-금)
                weekdaySum += day.includedRequests
                weekdayCount += 1
            }
        }
        
        let weekdayAvg = weekdayCount > 0 ? weekdaySum / Double(weekdayCount) : 0
        let weekendAvg = weekendCount > 0 ? weekendSum / Double(weekendCount) : 0
        
        // Fallback 처리
        if weekendAvg == 0 && weekdayAvg > 0 {
            return 0.1  // 주말 데이터 없으면 주중의 10%로 가정
        }
        
        if weekdayAvg == 0 {
            return 1.0  // 주중 데이터 없으면 1:1 비율
        }
        
        return weekendAvg / weekdayAvg
    }
    
    // MARK: - Step 3: 남은 일수 계산
    
    /// 남은 주중/주말 일수 계산
    /// - Parameters:
    ///   - today: 현재 날짜 (UTC)
    ///   - remainingDays: 월말까지 남은 총 일수
    /// - Returns: (남은 주중 일수, 남은 주말 일수)
    private func countRemainingWeekdaysAndWeekends(from today: Date, remainingDays: Int) -> (weekdays: Int, weekends: Int) {
        var weekdays = 0
        var weekends = 0
        
        for dayOffset in 1...remainingDays {
            guard let futureDate = utcCalendar.date(byAdding: .day, value: dayOffset, to: today) else {
                continue
            }
            
            let weekday = utcCalendar.component(.weekday, from: futureDate)
            
            if weekday == 1 || weekday == 7 {
                weekends += 1
            } else {
                weekdays += 1
            }
        }
        
        return (weekdays, weekends)
    }
}
