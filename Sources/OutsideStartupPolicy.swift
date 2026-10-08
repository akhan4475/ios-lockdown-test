enum OutsideStartupPolicy {
    static func canRestoreData(holding: Bool, acknowledgements: Int, lastError: String) -> Bool {
        holding && acknowledgements > 0 && lastError.isEmpty
    }

    static func validCoordinates(latitude: Double, longitude: Double) -> Bool {
        latitude.isFinite && longitude.isFinite &&
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}
