import Foundation

/// What a Cancel in the street download sheet may do. A rule with no view in
/// it, so it can be tested: it decides whether streets the person has are
/// deleted.
public enum DownloadCancel: Equatable, Sendable {
    /// Nothing: the download already finished and was handed to the host
    /// (which, for an update, has already deleted the old area), or a cancel
    /// is already under way. Deleting now would lose the new area too.
    case ignore
    /// Close without deleting: nothing was begun, or the area is an older
    /// unfinished one from the Maps list, which stays for Try again.
    case close
    /// Delete the area the sheet began, once its download has stopped
    /// writing, then close.
    case deleteThenClose(UUID)

    /// - Parameters:
    ///   - finished: the download returned its area and the host was told.
    ///   - cancelling: a cancel is already waiting.
    ///   - sheetBeganArea: the area was begun by this sheet (a new area or an
    ///     update), not handed to it for a retry.
    ///   - areaID: the area the sheet is filling, once begun.
    public static func decide(finished: Bool, cancelling: Bool, sheetBeganArea: Bool,
                              areaID: UUID?) -> DownloadCancel {
        if finished || cancelling { return .ignore }
        guard sheetBeganArea, let areaID else { return .close }
        return .deleteThenClose(areaID)
    }
}
