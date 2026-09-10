// Unit tests for the after-edit half of app/Shared/Views/StepStack.swift and
// app/Shared/Views/StepControls.swift — the focus table and the two VoiceOver
// announcements that replace the animation §Motion deliberately removes.
//
// Run via (macOS, safe locally — no UI-test target is built):
//   xcodebuild test -project app/App.xcodeproj -scheme App-macOS \
//     -configuration Debug -destination 'platform=macOS' \
//     -only-testing:AppMacOSTests/StepFocusTests \
//     CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO
//
// WHAT THESE CASES EXIST TO CATCH, and it is not "does the code run". Neither
// the announcement nor the focus move has ANY visual symptom: a wrong sentence
// is spoken to somebody who is not looking at the screen, and a focus target
// naming a card that does not exist simply does nothing. There is no screenshot
// that fails. So the arithmetic behind both is asserted here, host-based, and
// the surfaces are DRIVEN rather than imitated — the WR-01 shape: a test that
// rebuilds a surface's rule by hand asserts its own copy of the rule.
//
// THE ONE THAT MATTERS MOST IS `focusIsOffsetIndependent`. `modelOffset` is 1
// on Hashing and 0 on the other two, and a focus table written in
// `Pipeline.steps` indexes would name a card one place off on exactly the
// surface where the extra element is the chain root. The cases below assert
// that the SAME card of the SAME stack answers the SAME focus target on all
// three surfaces, which is false the moment a `modelIndex` leaks into the
// answer.
//
// Every AppModel is built through `AppModel.isolated()` — both unit bundles are
// host-based, so a bare `AppModel()` binds the shipping app's defaults domain
// and one case's writes leak into another case's reads.

import Testing

/// The focus table and the two announcements, as pure functions of position.
struct StepFocusTests {
    /// A position in a stack of `count` appended cards, on a surface whose
    /// pipeline carries `offset` leading elements the cards do not.
    private func position(_ index: Int, of count: Int, offset: Int = 0) -> StepStackPosition {
        StepStackPosition(appendedIndex: index, appendedCount: count, modelOffset: offset)
    }

    // MARK: - Focus after a move

    /// Focus FOLLOWS the step: the same control, at the index it now occupies.
    ///
    /// The failure this excludes is the tempting one — leaving focus at the old
    /// index. That lands the user on the card that moved the OTHER way, under
    /// the control they just pressed, which reads as the app having done
    /// nothing at all.
    @Test("a move keeps focus on the same control of the moved step, at its new index")
    func moveKeepsFocusOnTheMovedStep() {
        #expect(position(2, of: 4).focusAfterMove(.up) == .control(.moveUp, appendedIndex: 1))
        #expect(position(2, of: 4).focusAfterMove(.down) == .control(.moveDown, appendedIndex: 3))
        #expect(position(1, of: 4).focusAfterMove(.up) == .control(.moveUp, appendedIndex: 0))
    }

    /// A move the pipeline refuses moves no focus and says nothing.
    ///
    /// Both ends, both directions. `destinationIndex(_:)` answers the card's own
    /// index there, which is the same expression `Pipeline.moving(from:to:)`
    /// rejects as non-adjacent — so "the move was refused" is decided once and
    /// not re-derived here.
    @Test("a refused move at either end announces nothing and moves no focus")
    func refusedMoveIsSilent() {
        #expect(position(0, of: 3).focusAfterMove(.up) == nil)
        #expect(stepMovedAnnouncement(position(0, of: 3), .up) == nil)
        #expect(position(2, of: 3).focusAfterMove(.down) == nil)
        #expect(stepMovedAnnouncement(position(2, of: 3), .down) == nil)
        // The single-card stack: neither move is possible.
        #expect(position(0, of: 1).focusAfterMove(.up) == nil)
        #expect(position(0, of: 1).focusAfterMove(.down) == nil)
    }

    // MARK: - Focus after a removal

    /// All three rows of the removal half of the focus table.
    ///
    /// Row 2 is the card that TOOK the removed card's position — same index,
    /// different card. Row 3 is the removed-card-was-last case, which has no
    /// such successor and lands on the card that is now last. Row 4 is the
    /// empty case: D-100 leaves the pinned root no controls, so the header is
    /// the only element left to hold focus, and the alternative is the failure
    /// this whole section exists to prevent — focus dropping to the top of the
    /// screen after every single removal.
    @Test("a removal lands focus on a defined control, including when it empties the stack")
    func removalLandsFocusSomewhereDefined() {
        // Middle card of three: the card that took its position.
        #expect(position(1, of: 3).focusAfterRemoval == .control(.remove, appendedIndex: 1))
        // Last card of three: the card that is now last.
        #expect(position(2, of: 3).focusAfterRemoval == .control(.remove, appendedIndex: 1))
        // First card of two: the survivor slides into index 0.
        #expect(position(0, of: 2).focusAfterRemoval == .control(.remove, appendedIndex: 0))
        // The only appended card: nothing appended survives.
        #expect(position(0, of: 1).focusAfterRemoval == .rootHeader)
    }

    /// A focus target never names an index the surviving stack does not have.
    ///
    /// Swept rather than spot-checked, because an off-by-one here is a target
    /// that matches no element and therefore does nothing VISIBLE — the failure
    /// mode with no symptom.
    @Test("no removal target names a card that will not exist")
    func removalTargetIsAlwaysInRange() {
        for count in 1 ... 6 {
            for index in 0 ..< count {
                let target = position(index, of: count).focusAfterRemoval
                guard case let .control(kind, appendedIndex: landing) = target else {
                    #expect(count == 1, "rootHeader is only correct when nothing appended survives")
                    continue
                }
                #expect(kind == .remove, "a removal lands on a remove control")
                #expect(landing >= 0)
                #expect(landing < count - 1, "index \(landing) of \(count - 1) surviving cards")
            }
        }
    }

    // MARK: - Offset independence, which is the Hashing trap

    /// The SAME card of the SAME stack answers the SAME focus target on all
    /// three surfaces, whatever their `modelOffset`.
    ///
    /// 0 on Encode, 0 on Timestamps, **1 on Hashing** — where `steps.first` is
    /// the chain root. A focus table written in `Pipeline.steps` indexes would
    /// be off by one on exactly the surface where the extra element is the one
    /// a mistake destroys. This case is false the instant a `modelIndex` leaks
    /// into either answer.
    @Test("focus targets are offset-independent, so Hashing answers what Encode answers")
    func focusIsOffsetIndependent() {
        for offset in [0, 1, 2] {
            for count in 1 ... 5 {
                for index in 0 ..< count {
                    let subject = position(index, of: count, offset: offset)
                    let reference = position(index, of: count, offset: 0)
                    #expect(
                        subject.focusAfterRemoval == reference.focusAfterRemoval,
                        "removal target drifted at offset \(offset), card \(index) of \(count)"
                    )
                    #expect(subject.focusAfterMove(.up) == reference.focusAfterMove(.up))
                    #expect(subject.focusAfterMove(.down) == reference.focusAfterMove(.down))
                }
            }
        }
    }

    /// The announcements are offset-independent for the same reason, and the
    /// counts they carry are CARD counts rather than array counts.
    @Test("announcements are offset-independent and count cards, not array elements")
    func announcementsAreOffsetIndependent() {
        for offset in [0, 1, 2] {
            for count in 1 ... 5 {
                for index in 0 ..< count {
                    let subject = position(index, of: count, offset: offset)
                    let reference = position(index, of: count, offset: 0)
                    #expect(stepRemovedAnnouncement(subject) == stepRemovedAnnouncement(reference))
                    #expect(stepMovedAnnouncement(subject, .up) == stepMovedAnnouncement(reference, .up))
                    #expect(stepMovedAnnouncement(subject, .down) == stepMovedAnnouncement(reference, .down))
                }
            }
        }
    }

    // MARK: - What the two announcements actually say

    /// The move announcement carries the position AFTER the edit.
    ///
    /// Distinct numbers throughout, so a transposed format cannot pass by
    /// symmetry, and the two directions are asserted separately because a
    /// sign error would make one of them right.
    @Test("the move announcement states the position the step now has")
    func moveAnnouncementStatesTheNewPosition() {
        // Card 3 of a 5-card stack (4 appended) moving up becomes card 2.
        #expect(stepMovedAnnouncement(position(1, of: 4), .up) == "Moved to position 2 of 5.")
        // The same card moving down becomes card 4.
        #expect(stepMovedAnnouncement(position(1, of: 4), .down) == "Moved to position 4 of 5.")
    }

    /// The removal announcement counts the cards that REMAIN, plural-correct.
    ///
    /// The middle case is the one that catches a flat catalog entry: a hand
    /// written `"Step removed. %lld steps remain."` renders "1 steps remain" to
    /// a VoiceOver user and passes any non-empty check.
    ///
    /// Removing the only appended card leaves the pinned root, so the honest
    /// count is 1 rather than 0 — the same number that card's own
    /// "Step 1 of 1" label reads.
    @Test("the removal announcement counts remaining CARDS and picks the singular at one")
    func removalAnnouncementCountsRemainingCards() {
        #expect(stepRemovedAnnouncement(position(0, of: 1)) == "Step removed. 1 step remains.")
        #expect(stepRemovedAnnouncement(position(0, of: 2)) == "Step removed. 2 steps remain.")
        #expect(stepRemovedAnnouncement(position(2, of: 4)) == "Step removed. 4 steps remain.")
    }

    /// Neither announcement leaves a format specifier on the screen.
    ///
    /// A key that resolved to ITSELF contains no `%`; a row that dropped an
    /// argument does. Neither should reach a screen reader.
    @Test("neither announcement leaves a residual format specifier")
    func announcementsLeaveNoResidualSpecifier() {
        let moved = stepMovedAnnouncement(position(1, of: 4), .up) ?? "%"
        let removed = stepRemovedAnnouncement(position(1, of: 4))
        for sentence in [moved, removed] {
            #expect(!sentence.contains("%"), "residual format specifier in \(sentence)")
            #expect(!sentence.hasPrefix("step.announce"), "the key resolved to itself: \(sentence)")
        }
    }

    // MARK: - Driven through the three surfaces, not imitated

    /// Each surface's OWN `appendedCards` produces positions whose focus and
    /// announcements agree with the offset-free reference.
    ///
    /// The surfaces are driven rather than reconstructed. `HashingSurface`
    /// passes `stepOffset: 1`; if that offset ever reached a focus target, this
    /// case goes red on Hashing alone while the other two stay green, which is
    /// exactly the signal a source sweep cannot produce.
    @MainActor
    @Test("all three surfaces agree on the focus target for the same card of the same stack")
    func surfacesAgreeOnFocusTargets() {
        // THREE appended cards, not two, and that is not arbitrary. With two,
        // exactly one card survives a removal and `min(_, remaining - 1)`
        // clamps every answer to 0 — so a target that had wrongly picked up
        // `modelOffset` would still read 0 and this case would pass on the
        // broken tree. Measured: the mutation that makes `focusAfterRemoval`
        // answer `modelIndex` is invisible here at two cards and red at three.
        let model = AppModel.isolated()
        model.encode.input = "hello"
        model.encode = model.encode.appending(.base64Encode).appending(.base64Encode).appending(.base64Encode)
        model.hashing.input = "hello"
        model.hashing = Pipeline(
            input: "hello",
            steps: [
                Step(operation: .sha256), Step(operation: .base64Encode),
                Step(operation: .base64Encode), Step(operation: .base64Encode)
            ]
        )
        model.timestampsChainRoot = .iso8601
        model.timestamps.input = "0"
        model.timestamps = model.timestamps
            .appending(.base64Encode).appending(.base64Encode).appending(.base64Encode)

        let stacks: [String: [AppendedStepCard]] = [
            "encode": EncodeSurface(model: model).appendedCards,
            "hashing": HashingSurface(model: model).appendedCards,
            "timestamps": TimestampsSurface(model: model).appendedCards
        ]
        for (name, cards) in stacks {
            #expect(cards.count == 3, "\(name) did not build the three-appended-card stack this case needs")
            for card in cards {
                let reference = position(card.position.appendedIndex, of: card.position.appendedCount)
                #expect(card.position.focusAfterRemoval == reference.focusAfterRemoval, "\(name) removal focus")
                #expect(card.position.focusAfterMove(.up) == reference.focusAfterMove(.up), "\(name) move-up focus")
                #expect(
                    stepRemovedAnnouncement(card.position) == stepRemovedAnnouncement(reference),
                    "\(name) removal announcement"
                )
            }
        }
        // The offset is still carried where it BELONGS — the model index —
        // so this case cannot pass by the offset having been dropped.
        #expect(HashingSurface(model: model).appendedCards.first?.position.modelOffset == 1)
        #expect(EncodeSurface(model: model).appendedCards.first?.position.modelOffset == 0)
        #expect(TimestampsSurface(model: model).appendedCards.first?.position.modelOffset == 0)
    }
}
