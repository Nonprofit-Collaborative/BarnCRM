/**
 * R-VQ5 and R-VK4: deleting a person deletes the requirement rows and volunteer skills that name
 * them. Their person lookups are emptied by the platform, which cannot delete a row through a
 * lookup, so without this a background check would outlive its person with nobody named on it.
 *
 * Registered on Contact and on Account (`Volunteers_Person_Delete_Contact` and `..._Account`),
 * run by Core's own triggers, with Always Runs (ADR-0024): no switch, pause or bypass may leave a
 * background check behind. Before delete it notes the rows naming each record, since after
 * delete their lookups are already empty. After delete it deletes the rows noted for each record
 * whose MasterRecordId is empty: a merge loser carries one there, and the merge has moved its
 * rows, background checks included, to the record kept.
 *
 * Restoring a person from the Recycle Bin does not restore the rows (out of scope, R-VQ5).
 */
@NamespaceAccessible
public with sharing class VolunteerPersonDeleteHandler extends TriggerHandler {
    /** The rows noted before delete, by the record being deleted, until after delete. */
    private static Map<Id, Set<Id>> notedByPerson = new Map<Id, Set<Id>>();
    /**
     * Rows already deleted in this transaction: an account's contacts are deleted with it, and
     * should their triggers run too, a row is not deleted twice.
     */
    private static Set<Id> deleted = new Set<Id>();

    @NamespaceAccessible
    public VolunteerPersonDeleteHandler() {
        return;
    }

    public override String getName() {
        return 'VolunteerPersonDeleteHandler';
    }

    public override void beforeDelete() {
        Set<Id> contactIds = new Set<Id>();
        Set<Id> accountIds = new Set<Id>();
        for (SObject person : Trigger.old) {
            if (person.getSObjectType() == Contact.SObjectType) {
                contactIds.add(person.Id);
            } else {
                accountIds.add(person.Id);
            }
        }
        notedByPerson.putAll(
            VolunteerIntegritySelector.selectRowsNamingPeople(contactIds, accountIds)
        );
    }

    public override void afterDelete() {
        Set<Id> toDelete = new Set<Id>();
        for (SObject person : Trigger.old) {
            Set<Id> noted = notedByPerson.remove(person.Id);
            if (noted != null && person.get('MasterRecordId') == null) {
                toDelete.addAll(noted);
            }
        }
        toDelete.removeAll(deleted);
        if (toDelete.isEmpty()) {
            return;
        }
        new Purge().run(new List<Id>(toDelete));
        deleted.addAll(toDelete);
    }

    /**
     * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
     *
     * 1. **Permission enforced before this class is reached.** The platform has already deleted
     *    the person as the user, so the user was allowed to delete them.
     * 2. **Inputs validated by the caller.** The Ids are the rows the selector found naming the
     *    deleted records, nothing the user typed.
     * 3. **Only package owned records.** Requirement rows and volunteer skills, both Volunteers
     *    objects.
     * 4. **Reads that reach a user stay in user mode.** Nothing read here reaches the user.
     *
     * `without sharing` and system mode: requirements are private and a Team Member holds no
     * permission on them at all, yet must not leave a background check behind.
     */
    private without sharing class Purge {
        /** One delete per object: a list that alternates objects splits into too many chunks. */
        void run(List<Id> rowIds) {
            Map<Schema.SObjectType, List<Id>> byObject = new Map<Schema.SObjectType, List<Id>>();
            for (Id rowId : rowIds) {
                Schema.SObjectType rowType = rowId.getSObjectType();
                if (!byObject.containsKey(rowType)) {
                    byObject.put(rowType, new List<Id>());
                }
                byObject.get(rowType).add(rowId);
            }
            for (List<Id> sameObject : byObject.values()) {
                Database.delete(sameObject, true, AccessLevel.SYSTEM_MODE);
            }
        }
    }
}
