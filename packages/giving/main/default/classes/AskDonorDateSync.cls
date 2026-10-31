/**
 * Writes the earliest open ask's Target Date into the donor's Next Ask Date (canonical model
 * R-SO9), so the ask cadence pass (G-29) and its Who Is Due list follow the pipeline (G-26)
 * with no second job.
 *
 * For every donor an ask names before or after the change:
 * - with an open ask that has a Target Date, Next Ask Date becomes the earliest such date;
 * - with none left, a Next Ask Date that is blank or still holds the date the asks had set (the
 *   earliest open Target Date before the change) takes the future Next Ask Date of an ask this
 *   save closed, or is cleared when there is none. A date entered by hand is kept.
 *
 * DOCUMENTED EXCEPTION to the user-mode rule (plan Section 4.13, ADR-0021): the date is computed
 * here from every open ask of the donor, including asks the person saving cannot see when the
 * organization makes asks Private, and it is written only to a field this package owns. Reading
 * or writing as the person would leave a date that depends on who happened to save the last ask.
 * A donor that cannot be saved is logged; the ask's save is never refused for it.
 */
public without sharing class AskDonorDateSync {
    private static final String CONTEXT = 'Ask: donor Next Ask Date';

    /**
     * @param afterRows  the asks as saved (null on delete)
     * @param beforeRows the asks before the save (null on insert)
     */
    public static void sync(List<SObject> afterRows, List<SObject> beforeRows) {
        Map<Id, Ask__c> before = new Map<Id, Ask__c>();
        if (beforeRows != null) {
            for (SObject row : beforeRows) {
                before.put(row.Id, (Ask__c) row);
            }
        }
        Set<Id> askIds = new Set<Id>();
        Set<Id> donorIds = new Set<Id>();
        Map<Id, Date> earliestBefore = new Map<Id, Date>();
        Map<Id, Date> earliestAfter = new Map<Id, Date>();
        // Each donor's earliest future ask-again date from an ask this save closed.
        Map<Id, Date> askAgain = new Map<Id, Date>();
        if (afterRows != null) {
            for (SObject row : afterRows) {
                Ask__c ask = (Ask__c) row;
                Ask__c old = before.get(ask.Id);
                if (old != null && !matters(ask, old)) {
                    continue;
                }
                askIds.add(ask.Id);
                note(ask, donorIds, earliestAfter);
                if (old != null) {
                    note(old, donorIds, earliestBefore);
                    noteAskAgain(ask, old, askAgain);
                }
            }
        } else {
            for (Ask__c old : before.values()) {
                askIds.add(old.Id);
                note(old, donorIds, earliestBefore);
            }
        }
        donorIds.remove(null);
        if (donorIds.isEmpty()) {
            return;
        }
        // The donors' other open asks count on both sides of the change.
        Map<Id, Date> others = otherOpenAsks(donorIds, askIds);
        for (Id donorId : others.keySet()) {
            earliestBefore.put(donorId, earlier(earliestBefore.get(donorId), others.get(donorId)));
            earliestAfter.put(donorId, earlier(earliestAfter.get(donorId), others.get(donorId)));
        }
        save(changedDonors(donorIds, earliestBefore, earliestAfter, askAgain));
    }

    /** An ask this save closed carries its own Next Ask Date to its donors when it is ahead. */
    private static void noteAskAgain(Ask__c ask, Ask__c old, Map<Id, Date> askAgain) {
        Boolean closedNow =
            old.Outcome__c == AskRules.OUTCOME_OPEN &&
            ask.Outcome__c != AskRules.OUTCOME_OPEN;
        if (!closedNow || ask.Next_Ask_Date__c == null || ask.Next_Ask_Date__c <= Date.today()) {
            return;
        }
        for (Id donorId : new List<Id>{ ask.Donor_Contact__c, ask.Donor_Account__c }) {
            if (donorId != null) {
                askAgain.put(donorId, earlier(askAgain.get(donorId), ask.Next_Ask_Date__c));
            }
        }
    }

    /** True when the save changed something R-SO9 reads. */
    private static Boolean matters(Ask__c ask, Ask__c old) {
        return ask.Target_Date__c != old.Target_Date__c ||
            ask.Outcome__c != old.Outcome__c ||
            ask.Donor_Contact__c != old.Donor_Contact__c ||
            ask.Donor_Account__c != old.Donor_Account__c;
    }

    /** Adds the ask's donors, and its Target Date when it is open, to the running earliest. */
    private static void note(Ask__c ask, Set<Id> donorIds, Map<Id, Date> earliest) {
        for (Id donorId : new List<Id>{ ask.Donor_Contact__c, ask.Donor_Account__c }) {
            if (donorId == null) {
                continue;
            }
            donorIds.add(donorId);
            if (ask.Outcome__c == AskRules.OUTCOME_OPEN && ask.Target_Date__c != null) {
                earliest.put(donorId, earlier(earliest.get(donorId), ask.Target_Date__c));
            }
        }
    }

    private static Date earlier(Date a, Date b) {
        if (a == null) {
            return b;
        }
        if (b == null) {
            return a;
        }
        return a < b ? a : b;
    }

    /** The earliest open Target Date per donor among the asks not in this save. */
    private static Map<Id, Date> otherOpenAsks(Set<Id> donorIds, Set<Id> askIds) {
        Map<Id, Date> earliest = new Map<Id, Date>();
        String open = AskRules.OUTCOME_OPEN;
        for (AggregateResult row : [
            SELECT Donor_Contact__c donor, MIN(Target_Date__c) earliest
            FROM Ask__c
            WHERE
                Donor_Contact__c IN :donorIds
                AND Outcome__c = :open
                AND Target_Date__c != NULL
                AND Id NOT IN :askIds
            WITH SYSTEM_MODE
            GROUP BY Donor_Contact__c
        ]) {
            earliest.put((Id) row.get('donor'), (Date) row.get('earliest'));
        }
        for (AggregateResult row : [
            SELECT Donor_Account__c donor, MIN(Target_Date__c) earliest
            FROM Ask__c
            WHERE
                Donor_Account__c IN :donorIds
                AND Outcome__c = :open
                AND Target_Date__c != NULL
                AND Id NOT IN :askIds
            WITH SYSTEM_MODE
            GROUP BY Donor_Account__c
        ]) {
            earliest.put((Id) row.get('donor'), (Date) row.get('earliest'));
        }
        return earliest;
    }

    /** The donors whose Next Ask Date has to change, carrying only that field. */
    private static List<SObject> changedDonors(
        Set<Id> donorIds,
        Map<Id, Date> earliestBefore,
        Map<Id, Date> earliestAfter,
        Map<Id, Date> askAgain
    ) {
        // Contacts first, then Accounts: one update takes the two types as two chunks.
        List<SObject> current = new List<SObject>();
        current.addAll(
            [SELECT Id, Next_Ask_Date__c FROM Contact WHERE Id IN :donorIds WITH SYSTEM_MODE]
        );
        current.addAll(
            [SELECT Id, Next_Ask_Date__c FROM Account WHERE Id IN :donorIds WITH SYSTEM_MODE]
        );
        List<SObject> changed = new List<SObject>();
        for (SObject donor : current) {
            Date held = (Date) donor.get('Next_Ask_Date__c');
            Date target = earliestAfter.get(donor.Id);
            if (target == null) {
                // No open ask left. A date entered by hand is never touched; a blank date or the
                // date the asks had set takes the closed ask's ask-again date, or is cleared.
                Date setByAsks = earliestBefore.get(donor.Id);
                Boolean askDerived = held == null || held == setByAsks;
                target = askAgain.get(donor.Id);
                if (!askDerived || held == target) {
                    continue;
                }
            } else if (held == target) {
                continue;
            }
            SObject stamp = donor.getSObjectType().newSObject(donor.Id);
            stamp.put('Next_Ask_Date__c', target);
            changed.add(stamp);
        }
        return changed;
    }

    private static void save(List<SObject> donors) {
        if (donors.isEmpty()) {
            return;
        }
        List<String> refusals = new List<String>();
        List<Database.SaveResult> results = Database.update(donors, false, AccessLevel.SYSTEM_MODE);
        for (Database.SaveResult result : results) {
            if (!result.isSuccess()) {
                refusals.add(result.getErrors()[0].getMessage());
            }
        }
        if (!refusals.isEmpty()) {
            ErrorLogger.logMessages(refusals, CONTEXT, ErrorLogger.SEVERITY_ERROR);
        }
    }
}
