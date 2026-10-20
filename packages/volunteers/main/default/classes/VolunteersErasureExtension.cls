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
 * is a fact about the person. The hour letters and certificates BarnCRM generated for the person
 * are deleted too (amends D-108): they print the person's name. Core empties deleted records from
 * the Recycle Bin once the erasure commits and the Erasure record lists them by Id only.
 *
 * Records are read in system mode, so one is found whoever may see it, and changed as the user
 * (R-ER5): a person erasing without Volunteers Admin or Volunteers Coordinator is refused, with
 * that reason, rather than leaving them behind.
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

    /**
     * Reads everything the module holds about the person first, and refuses with a plain reason,
     * before changing anything, a person erasing who lacks the Volunteers access the changes
     * need. A person with no Volunteers records is erased by anyone Core allows.
     */
    public List<PersonErasure.Change> erase(Id personId) {
        Boolean isContact = personId.getSObjectType() == Contact.SObjectType;
        Set<Id> contacts = isContact ? new Set<Id>{ personId } : new Set<Id>();
        Set<Id> accounts = isContact ? new Set<Id>() : new Set<Id>{ personId };
        List<Volunteer_Hours__c> hours = VolunteerErasureSelector.hoursOf(contacts, accounts);
        List<Volunteer_Signup__c> signups = VolunteerErasureSelector.signupsOf(contacts, accounts);
        List<Volunteer_Skill__c> skills = VolunteerErasureSelector.skillsOf(contacts, accounts);
        List<Volunteer_Requirement__c> requirements = VolunteerErasureSelector.requirementsOf(
            contacts,
            accounts
        );
        List<Id> letters = generatedLetters(personId);
        if (
            !(hours.isEmpty() &&
            signups.isEmpty() &&
            skills.isEmpty() &&
            requirements.isEmpty() &&
            letters.isEmpty())
        ) {
            requireVolunteersAccess();
        }
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
        changes.addAll(eraseHours(hours));
        changes.addAll(eraseSignups(signups));
        changes.addAll(deleteRows(skills));
        changes.addAll(deleteRows(requirements));
        changes.addAll(deleteLetters(letters));
        return changes;
    }

    /**
     * The changes need Manage Volunteers (Volunteers Admin and Volunteers Coordinator hold it),
     * edit on hours and sign-ups and delete on skills and requirements. Without them a user
     * would be refused by the platform part way, with its own wording.
     */
    private static void requireVolunteersAccess() {
        Boolean allowed =
            VolunteerHoursService.canManage() &&
            Schema.SObjectType.Volunteer_Hours__c.isUpdateable() &&
            Schema.SObjectType.Volunteer_Hours__c.fields.Notes__c.isUpdateable() &&
            Schema.SObjectType.Volunteer_Signup__c.isUpdateable() &&
            Schema.SObjectType.Volunteer_Signup__c.fields.Status__c.isUpdateable() &&
            Schema.SObjectType.Volunteer_Signup__c.fields.Notes__c.isUpdateable() &&
            Schema.SObjectType.Volunteer_Skill__c.isDeletable() &&
            Schema.SObjectType.Volunteer_Requirement__c.isDeletable();
        if (!allowed) {
            throw new PersonErasure.ErasureException(Label.Volunteers_Erase_NeedVolunteersAccess);
        }
    }

    /**
     * The hour letters and certificates BarnCRM generated for the person (R-VL4): files saved
     * under the letter file name, first published on the person, whose title starts as a letter
     * template's letters do. Any other file is left to Core, which lists it as Kept.
     */
    private static List<Id> generatedLetters(Id personId) {
        List<Id> letters = new List<Id>();
        List<ContentDocumentLink> candidates = VolunteerErasureSelector.letterFilesOf(personId);
        if (candidates.isEmpty()) {
            return letters;
        }
        List<String> prefixes = new List<String>();
        for (String templateName : VolunteerErasureSelector.letterTemplateNames()) {
            prefixes.add(VolunteerLetterService.titlePrefix(templateName));
        }
        for (ContentDocumentLink candidate : candidates) {
            String title = candidate.ContentDocument.Title;
            for (String prefix : prefixes) {
                if (title != null && title.startsWith(prefix)) {
                    letters.add(candidate.ContentDocumentId);
                    break;
                }
            }
        }
        return letters;
    }

    /**
     * Deletes the generated letters (amends D-108): they print the person's name and hours. In
     * system mode, because each file belongs to whoever generated it and a coordinator may not
     * delete a colleague's file as themselves; only files identified exactly as generated
     * letters are taken, and only after `requireVolunteersAccess`.
     */
    private static List<PersonErasure.Change> deleteLetters(List<Id> documentIds) {
        if (documentIds.isEmpty()) {
            return new List<PersonErasure.Change>();
        }
        new LetterRemover().remove(documentIds);
        return new List<PersonErasure.Change>{
            new PersonErasure.Change(
                PersonErasure.DELETED,
                Label.Volunteers_Erase_LettersLabel,
                documentIds,
                null
            )
        };
    }

    /** Deletes files whoever owns them; see `deleteLetters`. */
    private without sharing class LetterRemover {
        void remove(List<Id> documentIds) {
            List<ContentDocument> documents = new List<ContentDocument>();
            for (Id documentId : documentIds) {
                documents.add(new ContentDocument(Id = documentId));
            }
            Database.delete(documents, true, AccessLevel.SYSTEM_MODE);
        }
    }

    /**
     * Hours are kept and counted; the notes typed on them are emptied as the user. A Rejection
     * Reason is kept, and listed as kept.
     */
    private static List<PersonErasure.Change> eraseHours(List<Volunteer_Hours__c> entries) {
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
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
        Integer withReason = 0;
        for (Volunteer_Hours__c entry : entries) {
            if (String.isNotBlank(entry.Notes__c)) {
                cleared.add(new Volunteer_Hours__c(Id = entry.Id, Notes__c = null));
            }
            if (String.isNotBlank(entry.Rejection_Reason__c)) {
                withReason++;
            }
        }
        if (withReason > 0) {
            changes.add(
                new PersonErasure.Change(
                    PersonErasure.KEPT,
                    objectLabel,
                    withReason,
                    Label.Volunteers_Erase_RejectionReasonKept
                )
            );
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
    private static List<PersonErasure.Change> eraseSignups(List<Volunteer_Signup__c> signups) {
        List<PersonErasure.Change> changes = new List<PersonErasure.Change>();
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
