/**
 * Every write the acknowledgment feature makes to package owned data.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `AcknowledgmentController` checks
 *    `Send_Acknowledgments` before anything here runs on a person's request, and the gift
 *    handler reaches only `claimKey` and `releaseKeys`, which write nothing a person could not
 *    have caused by saving the gift they were already allowed to save.
 * 2. **Inputs validated by the caller.** Every field written is computed by package code from
 *    records the running user was already allowed to read. The only free text stored is a failure
 *    reason the platform produced, never used in a query or a dynamic field name.
 * 3. **Only package owned fields.** The two fields written on `Gift__c` are
 *    `Acknowledgment_Status__c` and `Acknowledgment_Date__c`, which are the package's summary of
 *    its own ledger (R-AK6) and are written from it. Nothing else on the gift is touched, so the
 *    receipt lock (R-G4) has nothing to object to.
 * 4. **Reads that reach a user stay in user mode.** `AcknowledgmentSelector` runs
 *    `WITH USER_MODE`, so what a person sees on screen is what their sharing lets them see.
 *
 * `without sharing` rather than `with sharing`: a nightly send thanks donors the scheduling user
 * may not personally be able to see, and a thank you that quietly did not go out is worse than
 * one sent on behalf of somebody who cannot open the gift.
 */
public without sharing class AcknowledgmentWriter {
    public static void insertAcknowledgments(List<Acknowledgment__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Database.insert(rows, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Inserts rows one at a time, keeping the ones that went in and reporting the ones that did
     * not. This is how the claim key does its work (R-AK7): a row whose gift already has a
     * standing acknowledgment fails on the unique key, and that failure is the answer "already
     * thanked" rather than an error.
     */
    public static List<Database.SaveResult> claim(List<Acknowledgment__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return new List<Database.SaveResult>();
        }
        return Database.insert(rows, false, AccessLevel.SYSTEM_MODE);
    }

    public static void updateAcknowledgments(List<Acknowledgment__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        Database.update(rows, true, AccessLevel.SYSTEM_MODE);
    }

    public static void insertRun(Acknowledgment_Run__c run) {
        Database.insert(new List<Acknowledgment_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    public static void updateRun(Acknowledgment_Run__c run) {
        Database.update(new List<Acknowledgment_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Stamps the summary the ledger owns: the gift's acknowledgment status and date (R-AK6).
     * Nothing else on the gift is written here, ever.
     */
    public static void stampGifts(List<Gift__c> gifts) {
        if (gifts == null || gifts.isEmpty()) {
            return;
        }
        Database.update(gifts, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Stores one letter merge file and links it to its run, and returns the document id the run
     * record keeps so that the run and its file find each other without a query on the link
     * table.
     *
     * This is fifteen lines rather than a call into `ReceiptWriter.storeDocument` on purpose
     * (ADR-0032): a receipt's file is immutable and its store exists to guarantee that, while a
     * merge file is a working document that may be replaced or deleted. Sharing the method would
     * have meant sharing that guarantee's justification with a case it does not apply to.
     *
     * The link's visibility follows the receipt's rule (ADR-0034), because the file holds donor
     * names and addresses: `InternalUsers` first, so no Experience Cloud user reaches it, and
     * `AllUsers` only when the platform refuses that, which it does in an org with no external
     * users, where the two reach the same people (2026-10-28 security review, G-L2).
     */
    public static Id storeMergeFile(String title, String csv, Id runId) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.csv',
            VersionData = Blob.valueOf(csv),
            Origin = 'H'
        );
        Database.insert(new List<ContentVersion>{ version }, true, AccessLevel.SYSTEM_MODE);

        Id documentId = [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
            WITH SYSTEM_MODE
            LIMIT 1
        ]
        .ContentDocumentId;

        try {
            linkMergeFile(documentId, runId, VISIBILITY_INTERNAL);
        } catch (DmlException refused) {
            if (!ReceiptWriter.refusedVisibility(refused)) {
                throw refused;
            }
            internalOnlyRefused = true;
            linkMergeFile(documentId, runId, VISIBILITY_ALL);
        }
        return documentId;
    }

    private static final String VISIBILITY_INTERNAL = 'InternalUsers';
    private static final String VISIBILITY_ALL = 'AllUsers';

    /** True once the platform refused an `InternalUsers` link in this transaction. */
    @TestVisible
    private static Boolean internalOnlyRefused = false;

    private static void linkMergeFile(Id documentId, Id runId, String visibility) {
        Database.insert(
            new List<ContentDocumentLink>{
                new ContentDocumentLink(
                    ContentDocumentId = documentId,
                    LinkedEntityId = runId,
                    ShareType = 'V',
                    Visibility = visibility
                )
            },
            true,
            AccessLevel.SYSTEM_MODE
        );
    }
}
