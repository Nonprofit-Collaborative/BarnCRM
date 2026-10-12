/**
 * What a relationship record must be true of before it is saved (canonical model Section 27,
 * rules R-RL4 and R-RL5), and the two values BarnCRM fills in for the person saving it.
 *
 * This runs in the before contexts, where the records are still writable, and it runs on both
 * sides of a connection for the same reason every other rule does: the other side is an
 * ordinary record that an ordinary person can edit.
 *
 * It runs from RelationshipValidationHandler, which is its own registry row separate from the
 * one that maintains the other side, so these rules keep running when an administrator
 * switches that maintenance off.
 *
 * It does not run on the record this package writes itself. The reciprocal service stands both
 * of this object's automations down while it writes the other side (see RelationshipService),
 * so the mirror is built already valid rather than validated on the way in.
 */
public with sharing class RelationshipDomain {
    @TestVisible
    private static final String STATUS_CURRENT = 'Current';
    @TestVisible
    private static final String STATUS_FORMER = 'Former';

    /**
     * The two computed values: what this person is to the other one (R-RL3), and a status
     * that agrees with the dates (R-RL5).
     *
     * Status follows the end date in one direction only. An end date always means Former.
     * Clearing an end date returns the record to Current, because that is the edit that means
     * "this is on again". A record with no end date that someone deliberately marked Former is
     * left as they marked it: a connection can lapse without anyone knowing the day it did.
     */
    public static void applyDefaults(List<Relationship__c> records, Map<Id, SObject> previousById) {
        if (records == null) {
            return;
        }
        for (Relationship__c record : records) {
            record.Reciprocal_Type__c = RelationshipService.reciprocalOf(record.Type__c);
            if (String.isBlank(record.Status__c)) {
                record.Status__c = STATUS_CURRENT;
            }
            if (record.End_Date__c != null) {
                record.Status__c = STATUS_FORMER;
                continue;
            }
            Relationship__c previous = previousById == null
                ? null
                : (Relationship__c) previousById.get(record.Id);
            if (previous != null && previous.End_Date__c != null) {
                record.Status__c = STATUS_CURRENT;
            }
        }
    }

    /**
     * Refuses a relationship that names the same person twice, that does not name a person on
     * both sides, or that already exists (R-RL4).
     *
     * A duplicate is counted in one direction: this person, that person, this type. A to B as
     * Parent and B to A as Parent are two different relationships, which is what makes the
     * other side of A to B as Parent (B to A as Child) legal rather than a duplicate.
     */
    public static void validate(List<Relationship__c> records, Map<Id, SObject> previousById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        List<Relationship__c> wellFormed = new List<Relationship__c>();
        for (Relationship__c record : records) {
            if (!checkPeople(record)) {
                continue;
            }
            wellFormed.add(record);
        }
        if (wellFormed.isEmpty()) {
            return;
        }
        rejectDuplicates(wellFormed, previousById);
    }

    /**
     * Exactly one person on each side, and two different people. Returns false when the record
     * has been refused, so nothing downstream reads a reference that is not there.
     */
    private static Boolean checkPeople(Relationship__c record) {
        if (
            PersonReference.isAmbiguous(record.Contact__c, record.Person_Account__c) ||
            PersonReference.isAmbiguous(record.Related_Contact__c, record.Related_Person_Account__c)
        ) {
            record.addError(Label.Core_Relationship_PersonAmbiguous);
            return false;
        }
        if (
            !PersonReference.isComplete(record.Contact__c, record.Person_Account__c) ||
            !PersonReference.isComplete(record.Related_Contact__c, record.Related_Person_Account__c)
        ) {
            record.addError(Label.Core_Relationship_PersonRequired);
            return false;
        }
        if (
            PersonReference.isSamePerson(
                record.Contact__c,
                record.Person_Account__c,
                record.Related_Contact__c,
                record.Related_Person_Account__c
            )
        ) {
            record.addError(Label.Core_Relationship_SamePerson);
            return false;
        }
        return true;
    }

    /**
     * One query for the whole save. Every relationship already described from any of the
     * people in front of us is read once, keyed, and matched; records inside this same save
     * are matched against each other from the same map.
     */
    private static void rejectDuplicates(
        List<Relationship__c> records,
        Map<Id, SObject> previousById
    ) {
        Set<Id> fromPeople = new Set<Id>();
        for (Relationship__c record : records) {
            fromPeople.add(PersonReference.idOf(record.Contact__c, record.Person_Account__c));
        }
        Map<String, Relationship__c> existingByKey = new Map<String, Relationship__c>();
        Set<Id> beingSaved = new Set<Id>();
        for (Relationship__c record : records) {
            if (record.Id != null) {
                beingSaved.add(record.Id);
            }
        }
        for (Relationship__c existing : RelationshipSelector.selectByFromPersonIds(fromPeople)) {
            // A record in this same save is compared as it is about to be, not as it was.
            if (beingSaved.contains(existing.Id)) {
                continue;
            }
            String key = keyOf(existing);
            if (key != null && !existingByKey.containsKey(key)) {
                existingByKey.put(key, existing);
            }
        }
        Map<String, Relationship__c> seenInThisSave = new Map<String, Relationship__c>();
        for (Relationship__c record : records) {
            String key = keyOf(record);
            if (key == null) {
                continue;
            }
            if (previousById != null && unchangedKey(record, previousById)) {
                continue;
            }
            Relationship__c clash = existingByKey.get(key);
            if (clash != null) {
                record.addError(duplicateMessage(clash));
                continue;
            }
            if (seenInThisSave.containsKey(key)) {
                record.addError(duplicateMessageWithin());
                continue;
            }
            seenInThisSave.put(key, record);
        }
    }

    /**
     * True when this edit did not touch anything the duplicate key is made of, so a person
     * changing only a description is never told their own record is a duplicate of itself.
     */
    private static Boolean unchangedKey(Relationship__c record, Map<Id, SObject> previousById) {
        Relationship__c previous = (Relationship__c) previousById.get(record.Id);
        if (previous == null) {
            return false;
        }
        return keyOf(record) == keyOf(previous);
    }

    private static String keyOf(Relationship__c record) {
        String fromKey = PersonReference.keyOf(record.Contact__c, record.Person_Account__c);
        String toKey = PersonReference.keyOf(
            record.Related_Contact__c,
            record.Related_Person_Account__c
        );
        if (fromKey == null || toKey == null || String.isBlank(record.Type__c)) {
            return null;
        }
        return fromKey + '>' + toKey + '>' + record.Type__c.toLowerCase();
    }

    /**
     * The message names both people and the record already on file, so that the person reading
     * it can open the record instead of guessing which one it means. Both names are taken from
     * the record that already exists, which is the only one in this transaction that has them.
     */
    private static String duplicateMessage(Relationship__c existing) {
        return String.format(
            Label.Core_Relationship_Duplicate,
            new List<String>{
                nameOf(existing.Contact__r, existing.Person_Account__r),
                nameOf(existing.Related_Contact__r, existing.Related_Person_Account__r),
                existing.Name
            }
        );
    }

    private static String duplicateMessageWithin() {
        return Label.Core_Relationship_DuplicateInSave;
    }

    private static String nameOf(Contact asContact, Account asAccount) {
        if (asContact != null && String.isNotBlank(asContact.Name)) {
            return asContact.Name;
        }
        if (asAccount != null && String.isNotBlank(asAccount.Name)) {
            return asAccount.Name;
        }
        return Label.Core_Relationship_UnnamedPerson;
    }
}
