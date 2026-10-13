/**
 * The two writes primary affiliation upkeep makes (C-16, R-AF2).
 *
 * ADR-0021 (system mode writes for package owned data), category 2, is the authority for this
 * class. Both values are computed by `AffiliationService` from the affiliations a person has:
 * the primary flag taken off the affiliations that lost it, and the organization copied to the
 * person's Primary Affiliation field. A staff user adding an affiliation must not need edit
 * access on the person, or on that person's other affiliations, for the package to keep its
 * own bookkeeping straight. Writing them with the user's access turned an ordinary save into a
 * raw DML error under private sharing or a narrower permission set, so these writes run in
 * `AccessLevel.SYSTEM_MODE`.
 *
 * The conditions of ADR-0021 hold:
 *
 * - It is reached only from `AffiliationService`, after the platform has authorized the user's
 *   own affiliation save in user mode.
 * - Only package owned values are written: `Is_Primary__c` set to false on another affiliation
 *   of the same person, and `Primary_Affiliation__c` on Contact or Account. Every value is
 *   computed by the package; none is typed by a person.
 * - Nothing else in the transaction is elevated. The affiliation the user saved, and every
 *   screen read, stay in user mode.
 * - It is `without sharing` because the records it corrects (the person, and their other
 *   affiliations) are the ones the saving user may not be able to edit.
 */
public without sharing class AffiliationUpkeepWriter {
    /** Takes the primary flag off affiliations that lost it. */
    public static void clearPrimaryFlags(List<Affiliation__c> flagsToClear) {
        if (flagsToClear == null || flagsToClear.isEmpty()) {
            return;
        }
        Database.update(flagsToClear, true, AccessLevel.SYSTEM_MODE);
    }

    /** Writes the Primary Affiliation field on people held as contacts or as accounts. */
    public static void savePrimaries(List<SObject> people) {
        if (people == null || people.isEmpty()) {
            return;
        }
        Database.update(people, true, AccessLevel.SYSTEM_MODE);
    }
}
