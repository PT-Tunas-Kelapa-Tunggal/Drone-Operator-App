import Foundation

/// Rounds fertilizer doses to practical field increments.
///
/// Formula (step s = 0.5 kg):
///   r(x) = 0                                              if x <= 0
///   r(x) = max(s, s * round_half_away_from_zero(x / s))   if x > 0
public enum VariDoseRounding {
    /// Smallest dose increment, in kilograms.
    public static let halfKgStep: Double = 0.5

    /// Rounds `kilograms` to the nearest 0.5 kg (halves round up, e.g. 1.25 → 1.5).
    /// Any positive amount is raised to at least 0.5 kg (e.g. 0.1 → 0.5).
    /// Zero, negative values and NaN return 0.
    public static func roundToHalfKg(_ kilograms: Double) -> Double {
        guard kilograms > 0 else { return 0 }
        let step = halfKgStep
        let rounded = (kilograms / step).rounded(.toNearestOrAwayFromZero) * step
        return max(step, rounded)
    }
}

extension VariProductRow {
    /// `combinedKg` rounded via `VariDoseRounding.roundToHalfKg(_:)`.
    /// Computed, so it is not stored or persisted (not in JSON or CSV).
    public var roundedCombinedKg: Double {
        VariDoseRounding.roundToHalfKg(combinedKg)
    }
}

