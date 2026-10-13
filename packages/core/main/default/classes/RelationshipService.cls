/**
 * Relationships (C-15, canonical model Section 27).
 *
 * The feature is not "create the other side". Creating it is four lines. The feature is
 * keeping it correct while people edit, retype, and delete relationships two hundred at a
 * time, and doing that without the write that maintains the other side re-entering the
 * trigger that made it.
 *
 * Three things carry that weight.
 *
 * 1. **The automation stands itself down while it writes.** Every write this class makes to
 *    Relationship__c happens inside a bypass of both automations this object ships, the
 *    maintenance one and the validation one, cleared in a finally block, which is exactly how
 *    HouseholdMergeService moves people without the membership handlers running. The bypass is
 *    per transaction and per automation, so the user's own next save in the same transaction
 *    still gets the full treatment. The validation automation is stood down as well because the
 *    mirror is built complete and already valid here, and running the duplicate check over a
 *    record this class just built would compare it against the very record it mirrors.
 * 2. **Because the handler is stood down, the mirror is built complete.** Nothing runs after
 *    us to fill in the reciprocal type or to settle the status against the dates, so every
 *    field on the mirrored record is set here, from the record it mirrors.
 * 3. **A pair is found before it is created.** Before the other side is inserted, this class
 *    looks for a relationship that already is the other side and is not paired with anything
 *    (R-RL4a). That is what stops an import that carried both sides, and a recycle bin
 *    restore that brought both sides back, from turning into duplicates.
 *
 * The person on each side is a Contact and Account pair with exactly one set (canonical model
 * Section 4), and mirroring swaps the pair whole: this side's two lookups become the other
 * side's two lookups and back again. Nothing branches on whether a person is held as a
 * contact or as an account, so a relationship between two people held as accounts, or between
 * one of each, mirrors through the same code as any other.
 */
public with sharing class RelationshipService {
    /** The maintenance registry row this feature ships, and the name its bypass is keyed on. */
    public static final String AUTOMATION_NAME = 'Relationship_Reciprocal';

    /**
     * The validation registry row, stood down alongside the maintenance one while this class
     * writes. The two are separate rows so an administrator can switch the maintenance off and
     * keep the checks (see the registry descriptions), but the package's own writes are exempt
     * from both.
     */
    public static final String VALIDATION_AUTOMATION_NAME = 'Relationship_Validation';

    @TestVisible
    private static final String STATUS_CURRENT = 'Current';
    @TestVisible
    private static final String TYPE_OTHER = 'Other';

    private static Map<String, String> reciprocalByType;

    /**
     * Whether the org asks BarnCRM to keep both sides in step (R-RL1). An org that has
     * never saved its settings gets the shipped default, which is on, from
     * `SettingsService.SHIPPED_DEFAULTS`: the field's own `defaultValue` is not what Apex
     * reads back, and this feature did nothing at all on a fresh org until that was fixed
     * (ADR-0035). Only an explicit false switches the upkeep off.
     */
    public static Boolean isAutoReciprocalOn() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        return settings == null || settings.Relationship_Auto_Reciprocal__c != false;
    }

    /**
     * The type the other side of a connection takes, from the shipped mapping (R-RL3).
     * Anything the mapping does not carry becomes Other, so a type added by a later release
     * still produces a usable other side rather than an empty one.
     */
    public static String reciprocalOf(String type) {
        if (String.isBlank(type)) {
            return null;
        }
        if (reciprocalByType == null) {
            loadTypeMappings();
        }
        String mapped = reciprocalByType.get(type.toLowerCase());
        return String.isBlank(mapped) ? TYPE_OTHER : mapped;
    }

    @TestVisible
    private static void clearTypeCache() {
        reciprocalByType = null;
    }

    private static void loadTypeMappings() {
        reciprocalByType = new Map<String, String>();
        for (Relationship_Type__mdt mapping : RelationshipSelector.selectTypeMappings()) {
            if (
                String.isNotBlank(mapping.Type__c) && String.isNotBlank(mapping.Reciprocal_Type__c)
            ) {
                reciprocalByType.put(mapping.Type__c.toLowerCase(), mapping.Reciprocal_Type__c);
            }
        }
    }

    // ------------------------------------------------------------------ the other side

    /**
     * Gives every relationship that should have another side one: by pairing it with a record
     * that already is that side, or by creating it.
     *
     * Called after insert, after undelete, and from the update path for a relationship that
     * has just become managed or has just been given the second person it was missing.
     */
    public static void ensureReciprocals(List<Relationship__c> records) {
        if (records == null || records.isEmpty() || !isAutoReciprocalOn()) {
            return;
        }
        List<Relationship__c> eligible = new List<Relationship__c>();
        Set<Id> otherPeople = new Set<Id>();
        for (Relationship__c record : records) {
            if (!needsOtherSide(record)) {
                continue;
            }
            eligible.add(record);
            otherPeople.add(
                PersonReference.idOf(record.Related_Contact__c, record.Related_Person_Account__c)
            );
        }
        if (eligible.isEmpty()) {
            return;
        }

        Map<String, Relationship__c> unpairedByKey = unpairedCandidates(otherPeople, eligible);
        Set<Id> pairedInThisRun = new Set<Id>();
        Map<Id, Relationship__c> updates = new Map<Id, Relationship__c>();
        List<Relationship__c> toCreate = new List<Relationship__c>();
        List<Relationship__c> creators = new List<Relationship__c>();

        for (Relationship__c record : eligible) {
            if (pairedInThisRun.contains(record.Id)) {
                continue;
            }
            Relationship__c partner = unpairedByKey.get(otherSideKey(record));
            if (
                partner != null &&
                partner.Id != record.Id &&
                !pairedInThisRun.contains(partner.Id)
            ) {
                pairedInThisRun.add(record.Id);
                pairedInThisRun.add(partner.Id);
                updates.put(
                    record.Id,
                    new Relationship__c(Id = record.Id, Reciprocal_Relationship__c = partner.Id)
                );
                updates.put(
                    partner.Id,
                    new Relationship__c(Id = partner.Id, Reciprocal_Relationship__c = record.Id)
                );
                continue;
            }
            toCreate.add(mirrorOf(record));
            creators.add(record);
        }

        withoutReentry(new List<Relationship__c>(updates.values()), toCreate, creators, null);
    }

    /**
     * Keeps the other side equal to the side that was edited: the two people the other way
     * round, the matching type, and the same status, dates, and description (R-RL1).
     *
     * A relationship whose Keep Both Sides In Step is clear is left alone and keeps its
     * pairing (R-RL2). A relationship whose other side has been deleted out from under it is
     * given a new one rather than throwing.
     */
    public static void syncReciprocals(
        List<Relationship__c> records,
        Map<Id, SObject> previousById
    ) {
        if (records == null || records.isEmpty() || !isAutoReciprocalOn()) {
            return;
        }
        List<Relationship__c> toEnsure = new List<Relationship__c>();
        List<Relationship__c> toPropagate = new List<Relationship__c>();
        Set<Id> mirrorIds = new Set<Id>();
        Set<Id> changedIds = new Set<Id>();
        for (Relationship__c record : records) {
            changedIds.add(record.Id);
        }
        for (Relationship__c record : records) {
            Relationship__c previous = previousById == null
                ? null
                : (Relationship__c) previousById.get(record.Id);
            if (record.Is_Reciprocal_Managed__c != true) {
                continue;
            }
            if (record.Reciprocal_Relationship__c == null) {
                toEnsure.add(record);
                continue;
            }
            if (previous != null && !mirroredValuesChanged(record, previous)) {
                continue;
            }
            // Both sides of one pair edited in the same save would otherwise write over each
            // other in an order nobody chose. The record with the lower id wins, which is
            // arbitrary but the same every time.
            if (
                changedIds.contains(record.Reciprocal_Relationship__c) &&
                String.valueOf(record.Id)
                    .compareTo(String.valueOf(record.Reciprocal_Relationship__c)) > 0
            ) {
                continue;
            }
            toPropagate.add(record);
            mirrorIds.add(record.Reciprocal_Relationship__c);
        }

        List<Relationship__c> updates = new List<Relationship__c>();
        if (!toPropagate.isEmpty()) {
            Map<Id, Relationship__c> mirrors = new Map<Id, Relationship__c>(
                RelationshipSelector.selectByIds(mirrorIds)
            );
            for (Relationship__c record : toPropagate) {
                Relationship__c mirror = mirrors.get(record.Reciprocal_Relationship__c);
                if (mirror == null) {
                    // The other side is gone: rebuild it rather than fail the save. A copy,
                    // because a record in an after context is read only and the rebuild has
                    // to see the pairing as empty.
                    Relationship__c rebuild = record.clone(true, true, true, true);
                    rebuild.Reciprocal_Relationship__c = null;
                    toEnsure.add(rebuild);
                    continue;
                }
                Relationship__c wanted = mirrorOf(record);
                if (alreadyEqual(mirror, wanted)) {
                    continue;
                }
                wanted.Id = mirror.Id;
                updates.add(wanted);
            }
        }
        withoutReentry(updates, null, null, null);

        if (!toEnsure.isEmpty()) {
            ensureReciprocals(toEnsure);
        }
    }

    /**
     * Deletes the other side when a relationship is deleted (R-RL1). A pair deleted together
     * is not deleted twice: anything already in this delete is left out.
     */
    public static void deleteReciprocals(List<Relationship__c> deleted) {
        if (deleted == null || deleted.isEmpty() || !isAutoReciprocalOn()) {
            return;
        }
        Set<Id> deletedIds = new Set<Id>();
        for (Relationship__c record : deleted) {
            deletedIds.add(record.Id);
        }
        Set<Id> mirrorIds = new Set<Id>();
        for (Relationship__c record : deleted) {
            if (
                record.Is_Reciprocal_Managed__c == true &&
                record.Reciprocal_Relationship__c != null &&
                !deletedIds.contains(record.Reciprocal_Relationship__c)
            ) {
                mirrorIds.add(record.Reciprocal_Relationship__c);
            }
        }
        if (mirrorIds.isEmpty()) {
            return;
        }
        // Read them back first: one of them may already have been deleted by hand in this
        // same transaction, and deleting an id that is gone throws.
        List<Relationship__c> stillThere = RelationshipSelector.selectByIds(mirrorIds);
        if (stillThere.isEmpty()) {
            return;
        }
        withoutReentry(null, null, null, stillThere);
    }

    // ------------------------------------------------------------------ helpers

    /**
     * Every write this class makes, inside one bypass of both of this object's automations.
     * The maintenance handler that would run on these records is this same handler, so without
     * the bypass an insert of the other side would ask for the other side of the other side,
     * and a delete would chase its own tail. The validation handler is stood down with it
     * because the mirror is built complete here, so there is nothing left for it to fill in and
     * nothing to check that was not already checked on the side the person actually saved.
     */
    private static void withoutReentry(
        List<Relationship__c> updates,
        List<Relationship__c> inserts,
        List<Relationship__c> creators,
        List<Relationship__c> deletes
    ) {
        Boolean hasWork =
            (updates != null && !updates.isEmpty()) ||
            (inserts != null && !inserts.isEmpty()) ||
            (deletes != null && !deletes.isEmpty());
        if (!hasWork) {
            return;
        }
        AutomationControl.bypass(AUTOMATION_NAME);
        AutomationControl.bypass(VALIDATION_AUTOMATION_NAME);
        try {
            if (inserts != null && !inserts.isEmpty()) {
                Database.insert(inserts, AccessLevel.USER_MODE);
                List<Relationship__c> backPointers = new List<Relationship__c>();
                for (Integer i = 0; i < inserts.size(); i++) {
                    backPointers.add(
                        new Relationship__c(
                            Id = creators[i].Id,
                            Reciprocal_Relationship__c = inserts[i].Id
                        )
                    );
                }
                Database.update(backPointers, AccessLevel.USER_MODE);
            }
            if (updates != null && !updates.isEmpty()) {
                Database.update(updates, AccessLevel.USER_MODE);
            }
            if (deletes != null && !deletes.isEmpty()) {
                Database.delete(deletes, AccessLevel.USER_MODE);
            }
        } finally {
            AutomationControl.clearBypass(AUTOMATION_NAME);
            AutomationControl.clearBypass(VALIDATION_AUTOMATION_NAME);
        }
    }

    private static Boolean needsOtherSide(Relationship__c record) {
        return record.Id != null &&
            record.Is_Reciprocal_Managed__c == true &&
            record.Reciprocal_Relationship__c == null &&
            PersonReference.isComplete(record.Contact__c, record.Person_Account__c) &&
            PersonReference.isComplete(
                record.Related_Contact__c,
                record.Related_Person_Account__c
            ) &&
            String.isNotBlank(record.Type__c);
    }

    /**
     * The relationships that could already be the other side of one of these: described from
     * the person on the far side, paired with nothing, and managed. An unmanaged record is
     * never taken over, because clearing that box is how an org says "leave this one alone".
     */
    private static Map<String, Relationship__c> unpairedCandidates(
        Set<Id> otherPeople,
        List<Relationship__c> eligible
    ) {
        Map<String, Relationship__c> byKey = new Map<String, Relationship__c>();
        Set<Id> eligibleIds = new Set<Id>();
        for (Relationship__c record : eligible) {
            eligibleIds.add(record.Id);
        }
        for (Relationship__c candidate : RelationshipSelector.selectByFromPersonIds(otherPeople)) {
            if (
                candidate.Reciprocal_Relationship__c != null ||
                candidate.Is_Reciprocal_Managed__c != true
            ) {
                continue;
            }
            String key = ownSideKey(candidate);
            if (key != null && !byKey.containsKey(key)) {
                byKey.put(key, candidate);
            }
        }
        return byKey;
    }

    /** How this record identifies itself: this person, that person, this type. */
    private static String ownSideKey(Relationship__c record) {
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

    /** What the other side of this record would call itself. */
    private static String otherSideKey(Relationship__c record) {
        String fromKey = PersonReference.keyOf(record.Contact__c, record.Person_Account__c);
        String toKey = PersonReference.keyOf(
            record.Related_Contact__c,
            record.Related_Person_Account__c
        );
        String reciprocal = reciprocalOf(record.Type__c);
        if (fromKey == null || toKey == null || String.isBlank(reciprocal)) {
            return null;
        }
        return toKey + '>' + fromKey + '>' + reciprocal.toLowerCase();
    }

    /**
     * The other side of this relationship, complete. The people swap whole, which is what
     * makes a person held as an account need no special case.
     *
     * The mirror's reciprocal type is this record's own type rather than a second lookup
     * through the mapping. They agree for every symmetric pair, and where a shipped row is
     * deliberately asymmetric (Employer contact maps to Colleague, and Colleague maps to
     * itself) taking it from the record is the one that stays true to the connection.
     */
    @TestVisible
    private static Relationship__c mirrorOf(Relationship__c record) {
        return new Relationship__c(
            Contact__c = record.Related_Contact__c,
            Person_Account__c = record.Related_Person_Account__c,
            Related_Contact__c = record.Contact__c,
            Related_Person_Account__c = record.Person_Account__c,
            Type__c = reciprocalOf(record.Type__c),
            Reciprocal_Type__c = record.Type__c,
            Status__c = String.isBlank(record.Status__c) ? STATUS_CURRENT : record.Status__c,
            Start_Date__c = record.Start_Date__c,
            End_Date__c = record.End_Date__c,
            Description__c = record.Description__c,
            Is_Reciprocal_Managed__c = true,
            Reciprocal_Relationship__c = record.Id
        );
    }

    /** Whether anything the other side copies actually moved. */
    private static Boolean mirroredValuesChanged(Relationship__c record, Relationship__c previous) {
        return record.Type__c != previous.Type__c ||
            record.Status__c != previous.Status__c ||
            record.Start_Date__c != previous.Start_Date__c ||
            record.End_Date__c != previous.End_Date__c ||
            record.Description__c != previous.Description__c ||
            record.Contact__c != previous.Contact__c ||
            record.Person_Account__c != previous.Person_Account__c ||
            record.Related_Contact__c != previous.Related_Contact__c ||
            record.Related_Person_Account__c != previous.Related_Person_Account__c ||
            record.Is_Reciprocal_Managed__c != previous.Is_Reciprocal_Managed__c;
    }

    /**
     * True when the other side already says what we were about to write. Checked even though
     * the bypass makes recursion impossible, because a save that writes nothing is a save
     * that cannot fail, cannot fill the debug log, and cannot count against a limit.
     */
    private static Boolean alreadyEqual(Relationship__c mirror, Relationship__c wanted) {
        return mirror.Contact__c == wanted.Contact__c &&
            mirror.Person_Account__c == wanted.Person_Account__c &&
            mirror.Related_Contact__c == wanted.Related_Contact__c &&
            mirror.Related_Person_Account__c == wanted.Related_Person_Account__c &&
            mirror.Type__c == wanted.Type__c &&
            mirror.Reciprocal_Type__c == wanted.Reciprocal_Type__c &&
            mirror.Status__c == wanted.Status__c &&
            mirror.Start_Date__c == wanted.Start_Date__c &&
            mirror.End_Date__c == wanted.End_Date__c &&
            mirror.Description__c == wanted.Description__c &&
            mirror.Reciprocal_Relationship__c == wanted.Reciprocal_Relationship__c;
    }
}
