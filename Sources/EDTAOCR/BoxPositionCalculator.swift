import Foundation

struct BoxPositionCalculator {
    /// Calculate box number and hole position for a given bullet number.
    /// - Parameters:
    ///   - bulletNumber: the bullet tube number (e.g. 1801)
    ///   - minBullet: the smallest bullet number in the database
    ///   - firstBox: the box number where the smallest bullet is placed
    ///   - firstHole: the hole position (1-81) where the smallest bullet is placed
    /// - Returns: (box, hole) or nil if inputs are invalid
    static func calculate(bulletNumber: Int, minBullet: Int, firstBox: Int, firstHole: Int) -> (box: Int, hole: Int)? {
        guard firstBox > 0, firstHole >= 1, firstHole <= 81 else { return nil }
        let offset = bulletNumber - minBullet
        let globalPos = (firstBox - 1) * 81 + (firstHole - 1) + offset
        guard globalPos >= 0 else { return nil }
        let box = globalPos / 81 + 1
        let hole = globalPos % 81 + 1
        return (box, hole)
    }

    /// Parse bullet number string to Int, handling non-numeric values
    static func parseBulletNumber(_ str: String) -> Int? {
        let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed)
    }
}
