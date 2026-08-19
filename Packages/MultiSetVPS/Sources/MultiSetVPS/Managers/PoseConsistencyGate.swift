/*
Copyright (c) 2026 MultiSet AI. All rights reserved.
Licensed under the MultiSet License. You may not use this file except in compliance with the License. and you can't re-distribute this file without a prior notice
For license details, visit www.multiset.ai.
Redistribution in source or binary forms must retain this notice.
*/

import Foundation
import simd

internal final class PoseConsistencyGate {

    /// Why a response was turned down. The two cases need different handling: a
    /// false positive is a server mismatch the host app should be told about, while
    /// a re-establishing rejection only means ARKit invalidated our own reference.
    enum Rejection {
        /// The response contradicts a reference ARKit still vouches for — the query
        /// image was matched against a different part of the space.
        case falsePositive
        /// The reference predates an ARKit discontinuity, so it cannot be compared
        /// against any more. The gate is collecting agreeing fixes to re-anchor.
        case reestablishing
    }

    struct Decision {
        let accepted: Bool
        let rejection: Rejection?
        let reason: String
        let jumpMeters: Float
        let thresholdMeters: Float
        /// Contradicting fixes that have agreed with each other so far, and how many
        /// are needed before they overrule the current reference.
        let agreements: Int
        let agreementsRequired: Int

        var isFalsePositive: Bool { rejection == .falsePositive }
        var reestablishing: Bool { rejection == .reestablishing }
    }

    private var thresholdMeters: Float

    private var referenceAnchor: SIMD3<Float>?
    private var pendingAnchor: SIMD3<Float>?
    private var pendingAgreements = 0
    private var referenceIsStale = false

    /// After a session discontinuity the reference is untrustworthy anyway — ARKit may
    /// have moved the world origin under it — so one corroborating fix is enough to
    /// re-anchor on the new frame.
    ///
    /// There is deliberately no equivalent for a *fresh* reference. Two fixes that
    /// agree with each other and disagree with the reference are exactly what a
    /// repeatable false match produces (the same wrong pose returned twice from the
    /// same spot), and they are indistinguishable from genuine correction of a bad
    /// first fix. Rather than guess, the gate keeps rejecting and reports the streak in
    /// `Decision.agreements` — the host app can prompt the user, and
    /// `MultiSet.resetPoseConsistencyReference()` re-bootstraps on request.
    private static let agreementsToOverruleStaleReference = 1

    init(thresholdMeters: Float) {
        self.thresholdMeters = thresholdMeters
    }

    func updateTuning(thresholdMeters: Float) {
        self.thresholdMeters = thresholdMeters
    }

    var hasReference: Bool {
        return referenceAnchor != nil
    }

    func reset() {
        referenceAnchor = nil
        clearPending()
        referenceIsStale = false
    }

    /// Returns true only on the transition into the stale state, so the caller can
    /// reset its retry counter once per discontinuity instead of on every mark.
    @discardableResult
    func markSessionDiscontinuity() -> Bool {
        // Pending candidates are session-frame coordinates, so they expire with the
        // session frame — cleared on every discontinuity, not just the first one.
        clearPending()

        guard referenceAnchor != nil, !referenceIsStale else { return false }
        referenceIsStale = true
        print("MultiSetVPS >> Pose consistency reference marked stale (ARKit session discontinuity)")
        return true
    }

    func evaluate(anchor: SIMD3<Float>) -> Decision {
        guard let reference = referenceAnchor else {
            adopt(anchor)
            return accept(reason: "bootstrap", jump: 0)
        }

        let jump = simd_distance(anchor, reference)
        let wasStale = referenceIsStale
        // 0 means "cannot be overruled by agreement" — see the constant's note.
        let required = wasStale ? Self.agreementsToOverruleStaleReference : 0

        if jump <= thresholdMeters {
            adopt(anchor)
            return accept(
                reason: wasStale ? "ARKit relocalized, reference still valid" : "consistent with ARKit trajectory",
                jump: jump
            )
        }

        // The response contradicts the reference. Track how many contradicting fixes
        // have agreed with each other: after a discontinuity that agreement is what
        // re-anchors us, and otherwise it is the streak the host app reports to the user.
        if let candidate = pendingAnchor, simd_distance(anchor, candidate) <= thresholdMeters {
            pendingAgreements += 1
            pendingAnchor = anchor
        } else {
            pendingAnchor = anchor
            pendingAgreements = 0
        }

        if wasStale {
            if pendingAgreements >= required {
                adopt(anchor)
                return accept(reason: "re-anchored after session interruption", jump: jump)
            }

            return Decision(
                accepted: false,
                rejection: .reestablishing,
                reason: "awaiting \(required - pendingAgreements) more agreeing fix(es) to re-establish reference",
                jumpMeters: jump,
                thresholdMeters: thresholdMeters,
                agreements: pendingAgreements,
                agreementsRequired: required
            )
        }

        return Decision(
            accepted: false,
            rejection: .falsePositive,
            reason: "inconsistent with ARKit trajectory",
            jumpMeters: jump,
            thresholdMeters: thresholdMeters,
            agreements: pendingAgreements,
            agreementsRequired: required
        )
    }

    private func accept(reason: String, jump: Float) -> Decision {
        return Decision(
            accepted: true,
            rejection: nil,
            reason: reason,
            jumpMeters: jump,
            thresholdMeters: thresholdMeters,
            agreements: 0,
            agreementsRequired: 0
        )
    }

    private func adopt(_ anchor: SIMD3<Float>) {
        referenceAnchor = anchor
        clearPending()
        referenceIsStale = false
    }

    private func clearPending() {
        pendingAnchor = nil
        pendingAgreements = 0
    }
}
