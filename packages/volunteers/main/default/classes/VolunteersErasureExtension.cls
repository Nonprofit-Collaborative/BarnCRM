/**
 * What erasing a person does to the Volunteers module's own records (canonical model R-ER8,
 * R-VQ4, R-VK5, R-VU5, R-VG10; ADR-0110 `0110-erase-a-person-anonymizes-in-place.md`). Core finds
 * this class by name in `PersonErasureExtensions.EXTENSION_CLASSES` and calls it inside the
 * erasure's own transaction, so a refusal here takes the whole erasure back.
 *
 * As Giving keeps gifts, the person's hours and sign-ups are kept, still credited to the
 * anonymized person, so every total, job and shift count stands, and the volunteer totals on the
 * person are kept with them (they are read only to everyone, and anonymous aggregates like a
 * donor level). What the module holds as typed text about the person is emptied: the notes on
 * their hours and sign-ups. A booking on a shift still to come is cancelled, so nobody expects
 * the person and the place is freed. The person's onboarding requirements and their skills and
 * interests are deleted: a background check result lives nowhere else, and a skill or interest
 * is a fact about the person. Core empties deleted records from the Recycle Bin once the erasure
 * commits and the Erasure record lists them by Id only.
 *
 * Records are read in system mode, so one is found whoever may see it, and changed as the user
 * (R-ER5): a person erasing without access to them is refused rather than leaving them behind.
 * Nothing here changes an entry's person, date or hours, so an Approved entry, which R-VG7 locks
 * against those changes, is erased like any other.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves
 * it with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class VolunteersErasureExtension implements PersonErasureExtension {
    /** Booked but not yet worked: a booking on a shift still to come is cancelled from these. */
    private static final Set<String> STILL_BOOKED = new Set<String>{ 'Signed up', 'Confirmed' };

    @NamespaceAccessible
    public VolunteersErasureExtension() {
        return;
    }

    /** The volunteer totals the module keeps on the person, read only to every user (29O). */
    public Set<Schema.SObjectField> fieldsToKeep(Schema.SObjectType personType) {
        if (personType == Account.SObjectType) {
            return new Set<Schema.SObjectField>{
                Account.Volunteer_Hours_Total__c,
                Account.Volunteer_Hours_This_Year__c,
                Account.Volunteer_Hours_Last_Year__c,
                Account.First_Volunteer_Date__c,
                Account.Last_Volunteer_Date__c
            };
        }
        return new Set<Schema.SObjectField>{
            Contact.Volunteer_Hours_Total__c,
            Contact.Volunteer_Hours_This_Year__c,
            Contact.Volunteer_Hours_Last_Year__c,
            Contact.First_Volunteer_Date__c,
            Contact.Last_Volunteer_Date__c
        };
    }

    public List<PersonErasure.Change> erase(Id personId) {
        Boolean isContact = personId.getSObjectType() == Contact.SObjectType;
        Set<Id> contacts = isContact ? new Set<Id>{ personId } : new Set<Id>();
        Set<Id> accounts = isContact ? new Set<Id>() : new Set<Id>{ personId };
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
        changes.addAll(eraseHours(contacts, accounts));
        changes.addAll(eraseSignups(contacts, accounts));
        changes.addAll(deleteRows(VolunteerErasureSelector.skillsOf(contacts, accounts)));
        changes.addAll(deleteRows(VolunteerErasureSelector.requirementsOf(contacts, accounts)));
        return changes;
    }

    /** Hours are kept and counted; the notes typed on them are emptied as the user. */
    private static List<PersonErasure.Change> eraseHours(Set<Id> contacts, Set<Id> accounts) {
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
        List<Volunteer_Hours__c> entries = VolunteerErasureSelector.hoursOf(contacts, accounts);
        if (entries.isEmpty()) {
            return changes;
        }
        String objectLabel = labelOf(Volunteer_Hours__c.SObjectType);
        changes.add(
            new PersonErasure.Change(
                PersonErasure.KEPT,
                objectLabel,
                entries.size(),
                Label.Volunteers_Erase_HoursKept
            )
        );
        List<Volunteer_Hours__c> cleared = new List<Volunteer_Hours__c>();
        for (Volunteer_Hours__c entry : entries) {
            if (String.isNotBlank(entry.Notes__c)) {
                cleared.add(new Volunteer_Hours__c(Id = entry.Id, Notes__c = null));
            }
        }
        if (!cleared.isEmpty()) {
            Database.update(cleared, true, AccessLevel.USER_MODE);
            changes.add(
                new PersonErasure.Change(
                    PersonErasure.CLEARED,
                    objectLabel,
                    idsOf(cleared),
                    new List<String>{ Volunteer_Hours__c.Notes__c.getDescribe().getLabel() }
                )
            );
        }
        return changes;
    }

    /**
     * Sign-ups are kept and counted; their notes are emptied, and a booking on a shift that has
     * not started is cancelled, in one save as the user.
     */
    private static List<PersonErasure.Change> eraseSignups(Set<Id> contacts, Set<Id> accounts) {
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
        List<Volunteer_Signup__c> signups = VolunteerErasureSelector.signupsOf(contacts, accounts);
        if (signups.isEmpty()) {
            return changes;
        }
        String objectLabel = labelOf(Volunteer_Signup__c.SObjectType);
        changes.add(
            new PersonErasure.Change(
                PersonErasure.KEPT,
                objectLabel,
                signups.size(),
                Label.Volunteers_Erase_SignupsKept
            )
        );
        Datetime now = Datetime.now();
        List<Volunteer_Signup__c> updates = new List<Volunteer_Signup__c>();
        List<Id> cancelled = new List<Id>();
        List<Id> cleared = new List<Id>();
        for (Volunteer_Signup__c signup : signups) {
            Volunteer_Signup__c updated = new Volunteer_Signup__c(Id = signup.Id);
            Datetime starts = signup.Volunteer_Shift__r?.Start_Time__c;
            Boolean upcoming = STILL_BOOKED.contains(signup.Status__c) && starts > now;
            Boolean hasNotes = String.isNotBlank(signup.Notes__c);
            if (upcoming) {
                updated.Status__c = VolunteerSignupService.STATUS_CANCELLED;
                cancelled.add(signup.Id);
            }
            if (hasNotes) {
                updated.Notes__c = null;
                cleared.add(signup.Id);
            }
            if (upcoming || hasNotes) {
                updates.add(updated);
            }
        }
        if (updates.isEmpty()) {
            return changes;
        }
        Database.update(updates, true, AccessLevel.USER_MODE);
        if (!cancelled.isEmpty()) {
            changes.add(
                new PersonErasure.Change(
                    PersonErasure.ENDED,
                    objectLabel,
                    cancelled,
                    new List<String>{ Volunteer_Signup__c.Status__c.getDescribe().getLabel() }
                )
            );
        }
        if (!cleared.isEmpty()) {
            changes.add(
                new PersonErasure.Change(
                    PersonErasure.CLEARED,
                    objectLabel,
                    cleared,
                    new List<String>{ Volunteer_Signup__c.Notes__c.getDescribe().getLabel() }
                )
            );
        }
        return changes;
    }

    /** Deletes these rows as the user and reports them for Core to empty from the Recycle Bin. */
    private static List<PersonErasure.Change> deleteRows(List<SObject> rows) {
        if (rows.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        Database.delete(rows, true, AccessLevel.USER_MODE);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.DELETED,
                labelOf(rows.getSObjectType()),
                idsOf(rows),
                null
            )
        };
    }

    private static List<Id> idsOf(List<SObject> rows) {
        List<Id> ids = new List<Id>();
        for (SObject row : rows) {
            ids.add(row.Id);
        }
        return ids;
    }

    private static String labelOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural();
    }
}
