import Foundation

/// Mirrors `WeightUnit`/`DistanceUnit` exactly. Amounts are stored
/// canonically in grams; this handles display conversion only, at the view
/// layer.
public enum ServingUnit: String, Codable, CaseIterable {
    case grams, ounces

    private static let gramsPerOunce = 28.3495

    public var abbreviation: String { self == .grams ? "g" : "oz" }

    public func fromGrams(_ grams: Double) -> Double {
        self == .grams ? grams : grams / Self.gramsPerOunce
    }

    public func toGrams(_ value: Double) -> Double {
        self == .grams ? value : value * Self.gramsPerOunce
    }
}

/// Mirrors `WeightUnit` exactly. Distance is stored canonically in meters;
/// this handles display conversion only, at the view layer.
public enum DistanceUnit: String, Codable, CaseIterable {
    case miles, kilometers

    private static let metersPerMile = 1609.344

    public var abbreviation: String { self == .kilometers ? "km" : "mi" }

    public func fromMeters(_ meters: Double) -> Double {
        self == .kilometers ? meters / 1000 : meters / Self.metersPerMile
    }

    public func toMeters(_ value: Double) -> Double {
        self == .kilometers ? value * 1000 : value * Self.metersPerMile
    }
}

public enum WeightUnit: String, Codable, CaseIterable {
    case pounds, kilograms

    public var abbreviation: String { self == .kilograms ? "kg" : "lb" }

    public func fromKilograms(_ kg: Double) -> Double {
        self == .kilograms ? kg : kg * 2.2046226218
    }

    public func toKilograms(_ value: Double) -> Double {
        self == .kilograms ? value : value / 2.2046226218
    }
}
