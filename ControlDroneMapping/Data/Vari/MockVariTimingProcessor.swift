import Foundation

/// Demo-mode timing processor returning a realistic sample `krops_vari.timing` payload
/// through the same JSON encoding/decoding pipeline and persisting artifacts on disk.
public struct MockVariTimingProcessor: VariTimingProcessing {
    public init() {}

    public func runTiming(
        request: VariTimingRequest,
        options: VariTimingRunOptions,
        outputFolder: URL
    ) async throws -> VariTimingExecutionResult {
        try await Task.sleep(nanoseconds: 500_000_000)
        try Task.checkCancellation()

        let fm = FileManager.default
        try fm.createDirectory(at: outputFolder, withIntermediateDirectories: true)

        let requestURL = outputFolder.appendingPathComponent(LocalVariTimingProcessor.requestFileName)
        let outputURL = outputFolder.appendingPathComponent(LocalVariTimingProcessor.outputFileName)
        let cacheDir = VariTimingWeatherSettings.writableWeatherCacheDirectory(demo: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)

        let dolomiteID =
            request.fertilizers.first(where: { VariTimingBuilder.isDolomiteProduct($0.name) })?.id
            ?? "A01C2E47-5D6B-4B95-9D31-6A1C8217D045"
        let npkID =
            request.fertilizers.first(where: { $0.name.lowercased().contains("npk") })?.id
            ?? "D828E19B-7B72-4E11-A35D-B1B7D2F9C304"
        let ureaID =
            request.fertilizers.first(where: { VariTimingBuilder.isUreaProduct($0.name) })?.id
            ?? "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8"

        let sampleJSON = Self.makeSampleOutputJSON(skipDaily: options.skipDaily)
            .replacingOccurrences(of: "A01C2E47-5D6B-4B95-9D31-6A1C8217D045", with: dolomiteID)
            .replacingOccurrences(of: "D828E19B-7B72-4E11-A35D-B1B7D2F9C304", with: npkID)
            .replacingOccurrences(of: "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8", with: ureaID)
        guard let outputData = sampleJSON.data(using: .utf8) else {
            throw VariTimingError.invalidJSON("Gagal menyusun JSON demo.")
        }
        try outputData.write(to: outputURL, options: .atomic)

        let schedule = try JSONDecoder().decode(VariTimingSchedule.self, from: outputData)
        return VariTimingExecutionResult(
            request: request,
            schedule: schedule,
            requestJSONURL: requestURL,
            resultJSONURL: outputURL,
            cacheDirectoryURL: cacheDir,
            ranAt: Date()
        )
    }

    public func loadCachedResult(in outputFolder: URL) -> VariTimingExecutionResult? {
        let fm = FileManager.default
        let outputURL = outputFolder.appendingPathComponent(LocalVariTimingProcessor.outputFileName)
        guard fm.fileExists(atPath: outputURL.path),
            let data = try? Data(contentsOf: outputURL),
            let schedule = try? JSONDecoder().decode(VariTimingSchedule.self, from: data)
        else {
            return nil
        }

        let requestURL = outputFolder.appendingPathComponent(LocalVariTimingProcessor.requestFileName)
        guard let reqData = try? Data(contentsOf: requestURL),
            let request = try? JSONDecoder().decode(VariTimingRequest.self, from: reqData)
        else {
            return nil
        }

        let modified =
            (try? fm.attributesOfItem(atPath: outputURL.path)[.modificationDate] as? Date)
            ?? Date()

        return VariTimingExecutionResult(
            request: request,
            schedule: schedule,
            requestJSONURL: requestURL,
            resultJSONURL: outputURL,
            cacheDirectoryURL: VariTimingWeatherSettings.writableWeatherCacheDirectory(demo: true),
            ranAt: modified
        )
    }

    // MARK: - Demo Sample JSON Matching `krops_vari.timing` Schema 1.0

    private static func makeSampleOutputJSON(skipDaily: Bool) -> String {
        let dailyBlock: String
        let step1Schedule: String
        let step2Schedule: String
        let step3Schedule: String
        let flagsJSON: String

        if skipDaily {
            dailyBlock = "null"
            step1Schedule = ""
            step2Schedule = ""
            step3Schedule = ""
            flagsJSON = """
                ["Mode demo (--no-daily): prakiraan 10 hari dan curah hujan P30 dilewati."]
                """
        } else {
            dailyBlock = """
                {
                  "checked_on": "2027-01-19",
                  "reference_day": "2027-01-19",
                  "l5": {
                    "p30_mm": 164.2,
                    "p30_start_date": "2026-12-20",
                    "p30_end_date": "2027-01-18",
                    "p30_source": "nasa-power",
                    "water_stress": false,
                    "p30_quality": "fallback",
                    "p30_missing_days": {
                      "weatherkit-history": 30,
                      "nasa-power": 0
                    }
                  },
                  "l8": {
                    "state": "jendela_tabur",
                    "month_gate": {
                      "month": 1,
                      "avg_mm": 215.7,
                      "gate": "open"
                    },
                    "safe_days": [
                      "2027-01-19",
                      "2027-01-20",
                      "2027-01-21",
                      "2027-01-24",
                      "2027-01-25"
                    ],
                    "removed": {
                      "heavy": ["2027-01-23"],
                      "day_before_heavy": ["2027-01-22"],
                      "last_cached": ["2027-01-28"]
                    }
                  },
                  "wait": null
                }
                """
            step1Schedule = """
                ,"schedule": { "status": "done", "date": "2027-01-05", "not_before": null, "wait": null }
                """
            step2Schedule = """
                ,"schedule": { "status": "done", "date": "2027-01-19", "not_before": null, "wait": null }
                """
            step3Schedule = """
                ,"schedule": { "status": "planned", "date": "2027-01-20", "not_before": null, "wait": null }
                """
            flagsJSON = """
                ["Mode demo aktif: data simulasi putaran berjalan dengan jendela L8 & P30 NASA POWER."]
                """
        }

        return """
            {
              "schema_version": "1.0",
              "plan_year": 2027,
              "today": "2027-01-19",
              "rounds_per_year": 3,
              "rounds": [
                {
                  "round": 1,
                  "start_month": 1,
                  "start_month_name": "Januari",
                  "end_month": 2,
                  "end_month_name": "Februari",
                  "start_date": "2027-01-01",
                  "end_date": "2027-02-28",
                  "status": "ongoing",
                  "days_until_start": 0,
                  "day_of_round": 19,
                  "total_days": 59,
                  "card": {
                    "state": "started",
                    "started_on": "2027-01-05"
                  },
                  "daily": \(dailyBlock),
                  "steps": [
                    {
                      "step": 1,
                      "fertilizer_id": "A01C2E47-5D6B-4B95-9D31-6A1C8217D045",
                      "name": "Dolomite",
                      "display_name": "Dolomit",
                      "dose_kg": 400.0,
                      "annual_dose_kg": 1200.0,
                      "bag_kg": 50,
                      "wait_after_days": {
                        "min": 14,
                        "max": 28,
                        "state": "done",
                        "until": null
                      },
                      "card": {
                        "state": "done",
                        "done_on": "2027-01-05"
                      }
                      \(step1Schedule)
                    },
                    {
                      "step": 2,
                      "fertilizer_id": "D828E19B-7B72-4E11-A35D-B1B7D2F9C304",
                      "name": "NPK",
                      "display_name": "NPK 15-15-15",
                      "dose_kg": 120.0,
                      "annual_dose_kg": 360.0,
                      "bag_kg": 50,
                      "wait_after_days": {
                        "min": 1,
                        "max": null,
                        "state": "counting",
                        "until": "2027-01-20"
                      },
                      "card": {
                        "state": "done",
                        "done_on": "2027-01-19"
                      }
                      \(step2Schedule)
                    },
                    {
                      "step": 3,
                      "fertilizer_id": "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8",
                      "name": "Urea",
                      "display_name": "Urea",
                      "dose_kg": 100.0,
                      "annual_dose_kg": 300.0,
                      "bag_kg": 50,
                      "wait_after_days": null,
                      "card": {
                        "state": "waiting",
                        "available_from": "2027-01-20"
                      }
                      \(step3Schedule)
                    }
                  ]
                },
                {
                  "round": 2,
                  "start_month": 5,
                  "start_month_name": "Mei",
                  "end_month": 6,
                  "end_month_name": "Juni",
                  "start_date": "2027-05-01",
                  "end_date": "2027-06-30",
                  "status": "upcoming",
                  "days_until_start": 102,
                  "day_of_round": null,
                  "total_days": 61,
                  "card": {
                    "state": "upcoming",
                    "days_until_start": 102
                  },
                  "daily": null,
                  "steps": [
                    {
                      "step": 1,
                      "fertilizer_id": "A01C2E47-5D6B-4B95-9D31-6A1C8217D045",
                      "name": "Dolomite",
                      "display_name": "Dolomit",
                      "dose_kg": 400.0,
                      "annual_dose_kg": 1200.0,
                      "bag_kg": 50,
                      "wait_after_days": { "min": 14, "max": 28, "state": "idle", "until": null },
                      "card": { "state": "locked" }
                    },
                    {
                      "step": 2,
                      "fertilizer_id": "D828E19B-7B72-4E11-A35D-B1B7D2F9C304",
                      "name": "NPK",
                      "display_name": "NPK 15-15-15",
                      "dose_kg": 120.0,
                      "annual_dose_kg": 360.0,
                      "bag_kg": 50,
                      "wait_after_days": { "min": 1, "max": null, "state": "idle", "until": null },
                      "card": { "state": "locked" }
                    },
                    {
                      "step": 3,
                      "fertilizer_id": "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8",
                      "name": "Urea",
                      "display_name": "Urea",
                      "dose_kg": 100.0,
                      "annual_dose_kg": 300.0,
                      "bag_kg": 50,
                      "wait_after_days": null,
                      "card": { "state": "locked" }
                    }
                  ]
                },
                {
                  "round": 3,
                  "start_month": 9,
                  "start_month_name": "September",
                  "end_month": 10,
                  "end_month_name": "Oktober",
                  "start_date": "2027-09-01",
                  "end_date": "2027-10-31",
                  "status": "upcoming",
                  "days_until_start": 225,
                  "day_of_round": null,
                  "total_days": 61,
                  "card": {
                    "state": "upcoming",
                    "days_until_start": 225
                  },
                  "daily": null,
                  "steps": [
                    {
                      "step": 1,
                      "fertilizer_id": "A01C2E47-5D6B-4B95-9D31-6A1C8217D045",
                      "name": "Dolomite",
                      "display_name": "Dolomit",
                      "dose_kg": 400.0,
                      "annual_dose_kg": 1200.0,
                      "bag_kg": 50,
                      "wait_after_days": { "min": 14, "max": 28, "state": "idle", "until": null },
                      "card": { "state": "locked" }
                    },
                    {
                      "step": 2,
                      "fertilizer_id": "D828E19B-7B72-4E11-A35D-B1B7D2F9C304",
                      "name": "NPK",
                      "display_name": "NPK 15-15-15",
                      "dose_kg": 120.0,
                      "annual_dose_kg": 360.0,
                      "bag_kg": 50,
                      "wait_after_days": { "min": 1, "max": null, "state": "idle", "until": null },
                      "card": { "state": "locked" }
                    },
                    {
                      "step": 3,
                      "fertilizer_id": "5F3B9C1A-2E7D-4C8B-A6F0-91D4E2B7C3A8",
                      "name": "Urea",
                      "display_name": "Urea",
                      "dose_kg": 100.0,
                      "annual_dose_kg": 300.0,
                      "bag_kg": 50,
                      "wait_after_days": null,
                      "card": { "state": "locked" }
                    }
                  ]
                }
              ],
              "weather_basis": {
                "rule": "L8 Stage A: a month is open when its average rain is 100–300 mm (weather/krops_rules.py); rounds go in open months 4 months apart, the set with the highest in-band (100–200 mm) share",
                "period": [1991, 2020],
                "months": {
                  "1": { "name": "Januari", "avg_mm": 215.7, "in_band_share": 0.4, "gate": "open" },
                  "2": { "name": "Februari", "avg_mm": 107.9, "in_band_share": 0.367, "gate": "open" },
                  "3": { "name": "Maret", "avg_mm": 171.5, "in_band_share": 0.367, "gate": "open" },
                  "4": { "name": "April", "avg_mm": 205.4, "in_band_share": 0.433, "gate": "open" },
                  "5": { "name": "Mei", "avg_mm": 207.1, "in_band_share": 0.4, "gate": "open" },
                  "6": { "name": "Juni", "avg_mm": 174.5, "in_band_share": 0.7, "gate": "open" },
                  "7": { "name": "Juli", "avg_mm": 172.5, "in_band_share": 0.433, "gate": "open" },
                  "8": { "name": "Agustus", "avg_mm": 167.9, "in_band_share": 0.567, "gate": "open" },
                  "9": { "name": "September", "avg_mm": 162.9, "in_band_share": 0.6, "gate": "open" },
                  "10": { "name": "Oktober", "avg_mm": 209.7, "in_band_share": 0.333, "gate": "open" },
                  "11": { "name": "November", "avg_mm": 298.8, "in_band_share": 0.1, "gate": "open" },
                  "12": { "name": "Desember", "avg_mm": 318.7, "in_band_share": 0.1, "gate": "tunda" }
                },
                "candidate_sets": [
                  { "months": ["Januari", "Mei", "September"], "in_band_share": 1.4 },
                  { "months": ["Februari", "Juni", "Oktober"], "in_band_share": 1.4 },
                  { "months": ["Maret", "Juli", "November"], "in_band_share": 0.9 }
                ],
                "note": "climate averages (1991–2020) set the months; the days inside an active round's window come from the 10-day forecast (L8 Stage B) and P30 (L5), in that round's `daily`"
              },
              "flags": \(flagsJSON)
            }
            """
    }
}
