/**
 * The writes that keep the other side of a relationship in step (C-15, R-RL1).
 *
 * ADR-0021 (system mode writes for package owned data), category 2, is the authority for this
 * class, as extended by `NEXT-relationship-mirror-upkeep-in-system-mode.md`. The other side of a
 * relationship is a record the package builds and maintains from the side a person saved:
 * every value on it is copied or computed by `RelationshipService`, and none is typed there by
 * a person. Under private sharing it usually belongs to another user, and under a narrower
 * permission set the saver may not edit its package fields, so writing it with the saver's
 * access turned an ordinary save into a raw error. These writes run in
 * `AccessLevel.SYSTEM_MODE`.
 *
 * The conditions of ADR-0021 hold:
 *
 * - It is reached only from `RelationshipService`, after the platform has authorized the
 *   user's own save, edit, delete or restore of their side in user mode.
 * - It writes the mirror record that side implies, and the Reciprocal Relationship back
 *   pointer on the saved side. Nothing else.
 * - Nothing else in the transaction is elevated. The side the person saved, and every screen
 *   read, stay in user mode.
 * - It is `without sharing` because the other side is the record the saver may not own.
 *
 * Unlike `HouseholdWriter`, a delete is covered. A mirror is not a person's record: it exists
 * only because its partner does, and the delete that removes it follows a delete of the
 * partner that the platform has just allowed. Refusing it would leave a one-sided pair the
 * saver cannot even see.
 */
public without sharing class RelationshipUpkeepWriter {
    /**
     * Brings other sides back from the recycle bin when their partner has just been restored
     * (PEOPLE-21), for the same reason a delete is covered: the restore follows one the
     * platform has just allowed on the partner.
     */
    public static void restoreMirrors(List<Relationship__c> mirrors) {
        if (mirrors == null || mirrors.isEmpty()) {
            return;
        }
        Database.undelete(mirrors, true, AccessLevel.SYSTEM_MODE);
    }

    /** Creates other sides. */
    public static void insertMirrors(List<Relationship__c> mirrors) {
        if (mirrors == null || mirrors.isEmpty()) {
            return;
        }
        Database.insert(mirrors, true, AccessLevel.SYSTEM_MODE);
    }

    /** Updates other sides, and the back pointer on the side that was saved. */
    public static void updatePairs(List<Relationship__c> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        Database.update(records, true, AccessLevel.SYSTEM_MODE);
    }

    /** Deletes the other sides of relationships the user has just deleted. */
    public static void deleteMirrors(List<Relationship__c> mirrors) {
        if (mirrors == null || mirrors.isEmpty()) {
            return;
        }
        Database.delete(mirrors, true, AccessLevel.SYSTEM_MODE);
    }
}
