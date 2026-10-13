/**
 * What an affiliation must be true of before it is saved (canonical model Section 28, rules
 * R-AF1 and R-AF4).
 *
 * Two of the three rules here are about not letting a record say two things at once: a person
 * held as a contact and as an account at the same time, and a connection that has ended while
 * still being the one the person is chiefly associated with. The third, the overlap check,
 * exists because the honest way to record someone who was on the board twice is two
 * affiliations with two date ranges, and the easy mistake is two open ended ones.
 *
 * It runs from AffiliationValidationHandler, which is its own registry row separate from the
 * one that settles who is primary, so these rules keep running when an administrator switches
 * that maintenance off.
 */
public with sharing class AffiliationDomain {
    @TestVisible
    private static final String STATUS_CURRENT = 'Current';
    @TestVisible
    private static final String STATUS_FORMER = 'Former';

    /**
     * Settles the status against the dates, and takes the primary flag off anything that has
     * ended (R-AF4). A former affiliation is never the primary one: a field that still names
     * an employer someone left last year is worse than an empty field.
     */
    public static void applyDefaults(List<Affiliation__c> records, Map<Id, SObject> previousById) {
        if (records == null) {
            return;
        }
        for (Affiliation__c record : records) {
            if (String.isBlank(record.Status__c)) {
                record.Status__c = STATUS_CURRENT;
            }
            if (record.End_Date__c != null) {
                record.Status__c = STATUS_FORMER;
            } else {
                Affiliation__c previous = previousById == null
                    ? null
                    : (Affiliation__c) previousById.get(record.Id);
                if (previous != null && previous.End_Date__c != null) {
                    record.Status__c = STATUS_CURRENT;
                }
            }
            if (record.Status__c == STATUS_FORMER) {
                record.Is_Primary__c = false;
            }
        }
    }

    /**
     * Refuses an affiliation that does not name one person and one organization, or that
     * covers dates another affiliation for the same person, organization, and role already
     * covers (R-AF1).
     */
    public static void validate(List<Affiliation__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        List<Affiliation__c> wellFormed = new List<Affiliation__c>();
        for (Affiliation__c record : records) {
            if (PersonReference.isAmbiguous(record.Contact__c, record.Person_Account__c)) {
                record.addError(Label.Core_Affiliation_PersonAmbiguous);
                continue;
            }
            if (!PersonReference.isComplete(record.Contact__c, record.Person_Account__c)) {
                record.addError(Label.Core_Affiliation_PersonRequired);
                continue;
            }
            if (record.Organization__c == null) {
                record.addError(Label.Core_Affiliation_OrganizationRequired);
                continue;
            }
            if (
                PersonReference.isSamePerson(
                    record.Contact__c,
                    record.Person_Account__c,
                    null,
                    record.Organization__c
                )
            ) {
                record.addError(Label.Core_Affiliation_SelfAffiliation);
                continue;
            }
            wellFormed.add(record);
        }
        if (!wellFormed.isEmpty()) {
            rejectOverlaps(wellFormed, previousById);
        }
    }

    /**
     * One query for the whole save: every affiliation these people already have, matched
     * against the ones being saved and against each other.
     */
    private static void rejectOverlaps(
        List<Affiliation__c> records,
        Map<Id, SObject> previousById
    ) {
        Set<Id> personIds = new Set<Id>();
        Set<Id> beingSaved = new Set<Id>();
        for (Affiliation__c record : records) {
            personIds.add(PersonReference.idOf(record.Contact__c, record.Person_Account__c));
            if (record.Id != null) {
                beingSaved.add(record.Id);
            }
        }
        Map<String, List<Affiliation__c>> existingByKey = new Map<String, List<Affiliation__c>>();
        for (Affiliation__c existing : AffiliationSelector.selectByPersonIds(personIds)) {
            if (beingSaved.contains(existing.Id)) {
                continue;
            }
            addTo(existingByKey, roleKey(existing), existing);
        }
        Map<String, List<Affiliation__c>> inThisSave = new Map<String, List<Affiliation__c>>();
        for (Affiliation__c record : records) {
            String key = roleKey(record);
            if (key == null) {
                continue;
            }
            if (overlapInputsUnchanged(record, key, previousById)) {
                // Nothing the rule reads changed (Make primary, a description), so an overlap
                // that was already there is not this edit's to refuse (PEOPLE-23). It still
                // counts against the other rows in this save.
                addTo(inThisSave, key, record);
                continue;
            }
            Affiliation__c clash = firstOverlap(existingByKey.get(key), record);
            if (clash != null) {
                record.addError(overlapMessage(clash));
                continue;
            }
            if (firstOverlap(inThisSave.get(key), record) != null) {
                record.addError(Label.Core_Affiliation_OverlapInSave);
                continue;
            }
            addTo(inThisSave, key, record);
        }
    }

    /** True for an edit that changed neither the person, the organization, the role nor a date. */
    private static Boolean overlapInputsUnchanged(
        Affiliation__c record,
        String key,
        Map<Id, SObject> previousById
    ) {
        if (previousById == null || record.Id == null) {
            return false;
        }
        Affiliation__c previous = (Affiliation__c) previousById.get(record.Id);
        return previous != null &&
            key == roleKey(previous) &&
            record.Start_Date__c == previous.Start_Date__c &&
            record.End_Date__c == previous.End_Date__c;
    }

    private static void addTo(
        Map<String, List<Affiliation__c>> grouped,
        String key,
        Affiliation__c record
    ) {
        if (key == null) {
            return;
        }
        if (!grouped.containsKey(key)) {
            grouped.put(key, new List<Affiliation__c>());
        }
        grouped.get(key).add(record);
    }

    private static Affiliation__c firstOverlap(
        List<Affiliation__c> candidates,
        Affiliation__c record
    ) {
        if (candidates == null) {
            return null;
        }
        for (Affiliation__c candidate : candidates) {
            if (overlaps(candidate, record)) {
                return candidate;
            }
        }
        return null;
    }

    /**
     * Whether two date ranges touch. An empty start date is open at the beginning and an empty
     * end date is open at the end, so two affiliations with no dates at all do overlap, which
     * is the case the rule is really there to catch.
     */
    @TestVisible
    private static Boolean overlaps(Affiliation__c first, Affiliation__c second) {
        Boolean firstStartsBeforeSecondEnds =
            first.Start_Date__c == null ||
            second.End_Date__c == null ||
            first.Start_Date__c <= second.End_Date__c;
        Boolean secondStartsBeforeFirstEnds =
            second.Start_Date__c == null ||
            first.End_Date__c == null ||
            second.Start_Date__c <= first.End_Date__c;
        return firstStartsBeforeSecondEnds && secondStartsBeforeFirstEnds;
    }

    /** This person, this organization, this role, compared the way a person would read it. */
    private static String roleKey(Affiliation__c record) {
        String person = PersonReference.keyOf(record.Contact__c, record.Person_Account__c);
        if (person == null || record.Organization__c == null) {
            return null;
        }
        String role = String.isBlank(record.Role__c) ? '' : record.Role__c.trim().toLowerCase();
        return person + '>' + String.valueOf(record.Organization__c) + '>' + role;
    }

    private static String overlapMessage(Affiliation__c existing) {
        return String.format(
            Label.Core_Affiliation_Overlap,
            new List<String>{
                personName(existing),
                existing.Organization__r == null ? '' : existing.Organization__r.Name,
                String.isBlank(existing.Role__c) ? Label.Core_Affiliation_NoRole : existing.Role__c,
                existing.Name
            }
        );
    }

    private static String personName(Affiliation__c record) {
        if (record.Contact__r != null && String.isNotBlank(record.Contact__r.Name)) {
            return record.Contact__r.Name;
        }
        if (record.Person_Account__r != null && String.isNotBlank(record.Person_Account__r.Name)) {
            return record.Person_Account__r.Name;
        }
        return Label.Core_Affiliation_UnnamedPerson;
    }
}
