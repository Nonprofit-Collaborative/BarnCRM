/**
 * All SOQL against `Gift_Batch__c` and `Gift_Batch_Row__c` (G-17). Every query runs in user
 * mode, so a person only reads the batches and lines they may read (plan Section 4.13).
 *
 * The entered total is summed from the lines rather than stored: R-GB2 keeps it out of the
 * database, because a stored copy of the one sum this feature checks is a second place for it
 * to be wrong.
 */
public with sharing class GiftBatchSelector {
    /** One batch without its lines, or null when it does not exist or cannot be seen. */
    public static Gift_Batch__c selectById(Id batchId) {
        List<Gift_Batch__c> batches = [
            SELECT Id, Name, Status__c, Control_Total__c, Default_Gift_Date__c
            FROM Gift_Batch__c
            WHERE Id = :batchId
            WITH USER_MODE
        ];
        return batches.isEmpty() ? null : batches[0];
    }

    /**
     * One batch, read with a row lock, before anything is written to it. A second post of the
     * same batch waits here and then reads the status the first one wrote, which is what makes
     * a double post impossible (R-GB4). A save from a stale second tab waits the same way, so it
     * cannot delete or change lines of a batch that was posted a moment before.
     */
    public static Gift_Batch__c selectForUpdate(Id batchId) {
        List<Gift_Batch__c> batches = [
            SELECT
                Id,
                Status__c,
                Control_Total__c,
                Default_Gift_Date__c,
                Default_Payment_Method__c,
                Default_Fund__c,
                Default_Appeal__c
            FROM Gift_Batch__c
            WHERE Id = :batchId
            WITH USER_MODE
            FOR UPDATE
        ];
        return batches.isEmpty() ? null : batches[0];
    }

    /**
     * Whether the running user may type into and post this batch: create and edit access to
     * lines, and edit access to this batch's own record. Lines are controlled by their batch,
     * so a person who can only read someone else's batch cannot change its lines either, and
     * the grid says so instead of letting the database refuse.
     */
    public static Boolean canEdit(Id batchId) {
        if (
            batchId == null ||
            !Schema.SObjectType.Gift_Batch_Row__c.isCreateable() ||
            !Schema.SObjectType.Gift_Batch_Row__c.isUpdateable()
        ) {
            return false;
        }
        Id userId = UserInfo.getUserId();
        List<UserRecordAccess> access = [
            SELECT RecordId
            FROM UserRecordAccess
            WHERE UserId = :userId AND RecordId = :batchId AND HasEditAccess = TRUE
            WITH USER_MODE
        ];
        return !access.isEmpty();
    }

    /** The lines of one batch, in the order they were entered, with the gift each produced. */
    public static List<Gift_Batch_Row__c> selectRows(Id batchId) {
        return [
            SELECT
                Id,
                Name,
                Donor_Contact__c,
                Donor_Account__c,
                Amount__c,
                Gift_Date__c,
                Payment_Method__c,
                Payment_Reference__c,
                Fund__c,
                Appeal__c,
                Installment__c,
                Gift__c,
                Gift__r.Name
            FROM Gift_Batch_Row__c
            WHERE Gift_Batch__c = :batchId
            WITH USER_MODE
            ORDER BY Name ASC
        ];
    }
}
