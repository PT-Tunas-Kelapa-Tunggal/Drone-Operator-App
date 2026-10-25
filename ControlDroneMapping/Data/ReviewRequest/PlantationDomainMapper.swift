import Foundation

public struct PlantationDomainMapper {
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init() {}

    public func toDTO(from domain: PlantationReviewRequest, assetURL: URL? = nil) throws -> PlantationScanRequestRecordDTO {
        let boundaryDTOs = domain.boundary.map { CoordinatePointDTO(lat: $0.latitude, lon: $0.longitude) }
        let boundaryData = try encoder.encode(boundaryDTOs)
        let boundaryJSON = String(decoding: boundaryData, as: UTF8.self)

        let agroDTO = AgronomicProfileDTO(
            year: domain.agronomy.plantingYear,
            month: domain.agronomy.plantingMonth,
            soil: domain.agronomy.soilType,
            fertilizers: domain.agronomy.fertilizerRecords.map {
                FertilizerUsageDTO(
                    id: $0.id.uuidString,
                    name: $0.name,
                    bagKg: $0.bagWeightKg,
                    bags: $0.bagCount,
                    dosePerTree: $0.doseKgPerTree
                )
            },
            harvest: domain.agronomy.harvestRecord.map {
                HarvestYieldDTO(freq: $0.frequencyPerMonth, weightKg: $0.latestWeightKg)
            }
        )
        let agroData = try encoder.encode(agroDTO)
        let agronomicJSON = String(decoding: agroData, as: UTF8.self)

        var resultJSON: String?
        if let result = domain.result {
            let resultDTO = PlantationReviewResultDTO(
                completedAt: result.completedAt,
                nutrients: result.nutrients.map { NutrientMetricDTO(name: $0.name, current: $0.current, target: $0.target) },
                costs: result.costs.map { CostEstimateDTO(name: $0.name, quantity: $0.quantity, cost: $0.cost) },
                totalCostFormatted: result.totalCostFormatted,
                areas: result.allocationAreas.map { area in
                    AreaPlanDTO(
                        areaID: area.id,
                        periods: area.periods.map { period in
                            PeriodPlanDTO(
                                title: period.title,
                                dateRange: period.dateRange,
                                lines: period.lines.map {
                                    DoseLineDTO(name: $0.name, total: $0.total, dosage: $0.dosage)
                                }
                            )
                        }
                    )
                }
            )
            let resultData = try encoder.encode(resultDTO)
            resultJSON = String(decoding: resultData, as: UTF8.self)
        }

        return PlantationScanRequestRecordDTO(
            recordName: domain.id.uuidString,
            farmerName: domain.farmer.name,
            farmerPhone: domain.farmer.phone,
            farmerAddress: domain.farmer.address,
            gardenID: domain.garden.id.uuidString,
            gardenName: domain.garden.name,
            locationName: domain.garden.locationName,
            areaHectares: domain.garden.areaHectares,
            boundaryJSON: boundaryJSON,
            agronomicJSON: agronomicJSON,
            statusCode: domain.status.rawValue,
            submittedAt: domain.timeline.submittedAt,
            scheduledFor: domain.timeline.scheduledFor,
            inReviewAt: domain.timeline.inReviewAt,
            completedAt: domain.timeline.completedAt,
            operatorNotes: domain.operatorNotes,
            resultJSON: resultJSON,
            orthomosaicAssetURL: assetURL ?? domain.result?.orthomosaicImageURL
        )
    }

    public func toDomain(from dto: PlantationScanRequestRecordDTO) throws -> PlantationReviewRequest {
        guard let id = UUID(uuidString: dto.recordName),
              let gardenID = UUID(uuidString: dto.gardenID),
              let status = ReviewStatus(rawValue: dto.statusCode)
        else {
            throw DomainMappingError.invalidIdentifiers
        }

        let boundaryDTOs = try decoder.decode([CoordinatePointDTO].self, from: Data(dto.boundaryJSON.utf8))
        let boundary = boundaryDTOs.map { CoordinatePoint(latitude: $0.lat, longitude: $0.lon) }

        let agroDTO = try decoder.decode(AgronomicProfileDTO.self, from: Data(dto.agronomicJSON.utf8))
        let agronomy = AgronomicProfile(
            plantingYear: agroDTO.year,
            plantingMonth: agroDTO.month,
            soilType: agroDTO.soil,
            fertilizerRecords: agroDTO.fertilizers.compactMap {
                guard let fID = UUID(uuidString: $0.id) else { return nil }
                return FertilizerUsage(
                    id: fID,
                    name: $0.name,
                    bagWeightKg: $0.bagKg,
                    bagCount: $0.bags,
                    doseKgPerTree: $0.dosePerTree
                )
            },
            harvestRecord: agroDTO.harvest.map {
                HarvestYield(frequencyPerMonth: $0.freq, latestWeightKg: $0.weightKg)
            }
        )

        var result: PlantationReviewResult?
        if let resultJSON = dto.resultJSON {
            let resDTO = try decoder.decode(PlantationReviewResultDTO.self, from: Data(resultJSON.utf8))
            result = PlantationReviewResult(
                completedAt: resDTO.completedAt,
                nutrients: resDTO.nutrients.map { NutrientMetric(name: $0.name, current: $0.current, target: $0.target) },
                costs: resDTO.costs.map { CostEstimate(name: $0.name, quantity: $0.quantity, cost: $0.cost) },
                totalCostFormatted: resDTO.totalCostFormatted,
                allocationAreas: resDTO.areas.map { area in
                    FertilizerAreaPlan(
                        id: area.areaID,
                        periods: area.periods.map { period in
                            FertilizerPeriodPlan(
                                title: period.title,
                                dateRange: period.dateRange,
                                lines: period.lines.map {
                                    FertilizerDoseLine(name: $0.name, total: $0.total, dosage: $0.dosage)
                                }
                            )
                        }
                    )
                },
                orthomosaicImageURL: dto.orthomosaicAssetURL
            )
        }

        return PlantationReviewRequest(
            id: id,
            farmer: FarmerContact(name: dto.farmerName, phone: dto.farmerPhone, address: dto.farmerAddress),
            garden: GardenSummary(id: gardenID, name: dto.gardenName, locationName: dto.locationName, areaHectares: dto.areaHectares),
            boundary: boundary,
            agronomy: agronomy,
            status: status,
            timeline: ReviewTimeline(
                submittedAt: dto.submittedAt,
                scheduledFor: dto.scheduledFor,
                inReviewAt: dto.inReviewAt,
                completedAt: dto.completedAt
            ),
            operatorNotes: dto.operatorNotes,
            result: result
        )
    }
}

public enum DomainMappingError: LocalizedError {
    case invalidIdentifiers

    public var errorDescription: String? {
        switch self {
        case .invalidIdentifiers:
            return "ID permintaan tidak valid."
        }
    }
}
