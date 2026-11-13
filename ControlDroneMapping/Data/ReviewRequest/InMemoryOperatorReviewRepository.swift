import Foundation

public final class InMemoryOperatorReviewRepository: OperatorReviewRepository, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [PlantationReviewRequest]

    public init(initialRequests: [PlantationReviewRequest] = []) {
        self.requests = initialRequests
    }

    public func fetchAllRequests() async throws -> [PlantationReviewRequest] {
        lock.withLock {
            requests
        }
    }

    public func fetchRequest(recordName: String) async throws -> PlantationReviewRequest? {
        lock.withLock {
            requests.first { $0.recordName == recordName }
        }
    }

    public func dispatchCompletedReview(_ payload: ReviewDispatchPayload) async throws -> PlantationReviewRequest {
        lock.withLock {
            guard let index = requests.firstIndex(where: {
                $0.recordName == payload.recordName || $0.id == payload.requestID
            }) else {
                let fallback = PlantationReviewRequest(
                    id: payload.requestID,
                    recordName: payload.recordName,
                    farmer: FarmerContact(name: "Demo Petani", phone: "-", address: "-"),
                    garden: GardenSummary(id: payload.requestID, name: "Kebun Demo", locationName: "-", areaHectares: 1.0),
                    boundary: [],
                    agronomy: AgronomicProfile(
                        plantingYear: 2018,
                        soilType: .mineral,
                        fertilizingFrequencyPerYear: 2,
                        fertilizationBudgetPerHa: 5_000_000
                    ),
                    status: ReviewStatus(progressionStatus: payload.writer.progressionStatus ?? .finished),
                    progressionEvents: (payload.writer.progressionStatusDetail ?? []).map {
                        ReviewProgressionEvent(contractEvent: $0)
                    },
                    timeline: ReviewTimeline(
                        submittedAt: Date(),
                        plannedOperatorVisitDate: payload.writer.plannedOperatorVisitDate,
                        resultSentAt: payload.writer.resultSentAt
                    ),
                    result: payload.summaryResult
                )
                requests.append(fallback)
                return fallback
            }

            if let progressionStatus = payload.writer.progressionStatus {
                requests[index].status = ReviewStatus(progressionStatus: progressionStatus)
            }
            if let details = payload.writer.progressionStatusDetail {
                requests[index].progressionEvents = details.map { ReviewProgressionEvent(contractEvent: $0) }
            }
            requests[index].timeline.plannedOperatorVisitDate = payload.writer.plannedOperatorVisitDate
            requests[index].timeline.resultSentAt = payload.writer.resultSentAt ?? payload.summaryResult.completedAt
            requests[index].result = payload.summaryResult
            return requests[index]
        }
    }

    public func observeIncomingRequests() -> AsyncStream<[PlantationReviewRequest]> {
        AsyncStream { continuation in
            continuation.yield(self.currentRequests())
        }
    }

    private func currentRequests() -> [PlantationReviewRequest] {
        lock.withLock {
            requests
        }
    }

    public static var demoRequests: [PlantationReviewRequest] {
        let now = Date()
        let submittedAt = now.addingTimeInterval(-2 * 86_400)
        let boundary = [
            CoordinatePoint(latitude: 1.0010, longitude: 104.3740),
            CoordinatePoint(latitude: 1.0010, longitude: 104.3760),
            CoordinatePoint(latitude: 0.9990, longitude: 104.3760),
            CoordinatePoint(latitude: 0.9990, longitude: 104.3740),
        ]
        let demoID = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!
        let sample = PlantationReviewRequest(
            id: demoID,
            recordName: demoID.uuidString,
            farmer: FarmerContact(
                name: "Budi Santoso",
                phone: "+62 812-3456-7890",
                address: "Jl. Trans Barelang KM 12, Batam"
            ),
            garden: GardenSummary(
                id: demoID,
                name: "Kebun Sawit Barelang (Demo)",
                locationName: "Nongsa, Kota Batam, Kepulauan Riau",
                areaHectares: 4.5,
                circumferenceMeters: 860
            ),
            boundary: boundary,
            agronomy: AgronomicProfile(
                plantingYear: 2018,
                plantingMonth: 5,
                soilType: .mineral,
                fertilizingFrequencyPerYear: 2,
                fertilizationBudgetPerHa: 5_000_000,
                fertilizerRecords: [
                    FertilizerUsage(
                        contractType: .dolomite,
                        composition: [],
                        doseKgPerTree: 1.5,
                        rawDosageText: "1.5 kg/pohon"
                    ),
                    FertilizerUsage(
                        contractType: .npk15_15_15,
                        composition: [
                            FertilizerCompositionElement(name: "N", value: 15),
                            FertilizerCompositionElement(name: "P", value: 15),
                            FertilizerCompositionElement(name: "K", value: 15),
                            FertilizerCompositionElement(name: "Mg", value: 0),
                        ],
                        doseKgPerTree: 1.0,
                        rawDosageText: "1.0 kg/pohon"
                    ),
                ],
                harvestRecord: HarvestYield(frequencyPerMonth: 2, latestWeightKg: 1450)
            ),
            status: .sent,
            progressionEvents: [
                ReviewProgressionEvent(
                    dateTime: submittedAt,
                    title: "Permintaan Dikirim",
                    desc: "Data batas kebun dan agronomi dikirim oleh petani."
                )
            ],
            timeline: ReviewTimeline(submittedAt: submittedAt)
        )
        return [sample]
    }
}
