/**
 * The platform account merge behind a household merge, and nothing else.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class, as
 * extended by ADR-0134 (a household merge runs in system mode once BarnCRM has authorized
 * it). The platform's account merge deletes the household that goes away, so in user mode it
 * needs Delete on Account, and under sharing it needs delete access to that one record, which
 * only its owner and the owner's managers hold. BarnCRM staff are deliberately not given
 * Delete on Account (owner decision, 2026-10-25): a person who may edit two households is
 * trusted to combine them, not to delete households at will. So the merge runs here, in
 * `AccessLevel.SYSTEM_MODE` and `without sharing`.
 *
 * The exception is kept narrow:
 *
 * - It is reached only from `HouseholdMergeService.mergeHouseholds`, after BarnCRM's own
 *   checks have passed: the person has Edit on Account, and the platform's record access view
 *   (`UserRecordAccess`, read in user mode) says they may edit both households. The Duplicates
 *   panel adds its own `Manage_BarnCRM_Settings` check before that.
 * - Both records have already been read in user mode and confirmed as two different BarnCRM
 *   households that are not Nonprofit Cloud households, so an organization or any other
 *   account cannot be folded in through here.
 * - Nothing a person typed reaches it: it takes two record ids the service has validated.
 * - Everything else in the merge (moving the people, writing the chosen values, every read a
 *   screen shows) stays in user mode.
 */
public without sharing class HouseholdMergeWriter {
    /**
     * Folds the second household into the first with the platform's own merge, so that
     * activities, files, notes and every lookup any package points at it follow it. Answers
     * with the platform's result rather than throwing, so the caller can roll back and say
     * why.
     */
    public static Database.MergeResult mergeInto(Id survivorId, Id victimId) {
        return Database.merge(
            new Account(Id = survivorId),
            victimId,
            false,
            AccessLevel.SYSTEM_MODE
        );
    }
}
