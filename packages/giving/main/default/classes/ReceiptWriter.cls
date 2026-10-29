/**
 * Every write the receipting feature makes to package owned receipt data.
 *
 * DOCUMENTED EXCEPTION to the "user mode DML" rule (plan Section 4.13), under ADR-0021.
 *
 * ADR-0016 says issued receipts and their files are read only to everyone, and the packaged
 * permission sets say so: no role, including BarnCRM Admin, holds Create, Edit or Delete on
 * `Receipt__c`, `Receipt_Run__c` or `Receipt_Number_Sequence__c`. A user mode write would
 * therefore fail for every user in every org, including the one issuing the receipt. The package
 * writes these records; a person never does, which is the point.
 *
 * The four ADR-0021 conditions:
 *
 * 1. **Permission enforced before this class is reached.** `ReceiptService` and `ReceiptController`
 *    check `Issue_Receipts` before any call here. The one write that is not about issuing,
 *    `insertTemplates`, is reached only after `ReceiptTemplateService` has checked
 *    `Manage_BarnCRM_Settings` or `Issue_Receipts`, or from the post-install script, where there
 *    is no running user to check (ADR-0034).
 * 2. **Inputs validated by the caller.** Every field written is computed by package code from
 *    records the running user was already allowed to read: amounts from gifts, numbers from the
 *    sequence, dates from the clock. The only user typed text that reaches a record is a void
 *    reason, which is stored and never used in a query or a dynamic field name.
 * 3. **Only package owned fields.** The gift's receipt number is written by `ReceiptService` in
 *    user mode, not here, because the gift is the running user's record to save.
 * 4. **Reads that reach a user stay in user mode.** `ReceiptSelector` runs `WITH USER_MODE`, so
 *    what a person sees on screen is what their sharing lets them see. The reads in this class are
 *    upkeep: they exist to write the next value, never to display one.
 *
 * `without sharing` rather than `with sharing`: a year end run issues documents for donors the
 * running user may not personally be able to see, and a receipt that quietly did not get issued is
 * worse than one issued by an administrator who cannot open it.
 */
public without sharing class ReceiptWriter {
    public static void insertReceipts(List<Receipt__c> receipts) {
        if (receipts == null || receipts.isEmpty()) {
            return;
        }
        Database.insert(receipts, true, AccessLevel.SYSTEM_MODE);
    }

    public static void updateReceipts(List<Receipt__c> receipts) {
        if (receipts == null || receipts.isEmpty()) {
            return;
        }
        Database.update(receipts, true, AccessLevel.SYSTEM_MODE);
    }

    public static void insertRun(Receipt_Run__c run) {
        Database.insert(new List<Receipt_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    public static void updateRun(Receipt_Run__c run) {
        Database.update(new List<Receipt_Run__c>{ run }, true, AccessLevel.SYSTEM_MODE);
    }

    public static void insertSequence(Receipt_Number_Sequence__c sequence) {
        Database.insert(
            new List<Receipt_Number_Sequence__c>{ sequence },
            true,
            AccessLevel.SYSTEM_MODE
        );
    }

    public static void updateSequence(Receipt_Number_Sequence__c sequence) {
        Database.update(
            new List<Receipt_Number_Sequence__c>{ sequence },
            true,
            AccessLevel.SYSTEM_MODE
        );
    }

    /**
     * The shipped letters, materialized from custom metadata.
     *
     * System mode for the same reason as everything else here, and for one more: this insert runs
     * in the post-install script, whose platform user holds no permission set at all, so a user
     * mode insert could not create the two letters an org is supposed to arrive with (ADR-0029,
     * ADR-0034). Every field written comes from `Receipt_Template_Default__mdt`, which is packaged
     * and cannot be edited in a subscriber org, so no user typed text reaches a record here.
     *
     * `ReceiptTemplateService` is the only caller, and it checks a permission before every path
     * that reaches this method except the post-install one, which has no user to check.
     */
    public static void insertTemplates(List<Receipt_Template__c> templates) {
        if (templates == null || templates.isEmpty()) {
            return;
        }
        Database.insert(templates, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * Stores one rendered document and links it to the records that govern who may read it.
     *
     * **A `ContentDocumentLink` grants access through the linked record, not through
     * `Receipt__c`.** So the list of links is the access control list for a donor's tax document,
     * and it may name only records whose object permissions the Giving permission sets control:
     * the receipt, and the gift on a per gift receipt (ADR-0034). Linking the donor Contact or
     * Account, which every Core role can read, handed the year end statement of every donor to
     * program staff and volunteer coordinators who hold no Giving permission set at all. The
     * guard below is here rather than in the caller because the rule is one rule, and a caller
     * adding a fourth link is exactly how it was broken the first time.
     *
     * `ShareType = 'V'` is deliberate and stays. Viewer is the ceiling the link can grant, which
     * is what an immutable document needs (ADR-0010, R-RC1): `'I'` would infer the permission from
     * the linked record instead, and Giving Staff holds Edit on `Gift__c`. `Visibility` separates
     * internal users from external ones rather than one internal role from another, so
     * `InternalUsers` is not the fix for anything here; it is asked for because a receipt is an
     * internal document and no Experience Cloud user should ever reach one through a link this
     * package created (ADR-0009). An org with no external users has nothing to separate, and the
     * platform refuses `InternalUsers` there ("Visibility InternalUsers is not permitted for this
     * linked record"); on that refusal alone the links are written with `AllUsers`, which in such
     * an org reaches exactly the internal users `InternalUsers` would have (ADR-0034).
     *
     * The bytes are passed in and dropped on return: nothing here holds a PDF beyond the call,
     * which is what keeps a batch chunk inside the async heap limit.
     */
    public static Id storeDocument(String title, Blob bytes, List<Id> linkTo) {
        // Checked before anything is stored, so a refused link leaves no orphan file behind.
        for (Id target : linkTo) {
            if (target != null) {
                requireGoverningRecord(target);
            }
        }
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.pdf',
            VersionData = bytes,
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

        Set<Id> targets = new Set<Id>();
        for (Id target : linkTo) {
            if (target != null) {
                targets.add(target);
            }
        }
        if (targets.isEmpty()) {
            return documentId;
        }
        if (orgRefusesInternalOnlyLinks != true) {
            try {
                insertLinks(documentId, targets, VISIBILITY_INTERNAL);
                orgRefusesInternalOnlyLinks = false;
                return documentId;
            } catch (DmlException refused) {
                if (!refusedVisibility(refused)) {
                    throw refused;
                }
                // The whole insert rolled back, so nothing is half linked. Remembered for the
                // transaction, so a year end chunk asks the platform once rather than per donor.
                orgRefusesInternalOnlyLinks = true;
            }
        }
        insertLinks(documentId, targets, VISIBILITY_ALL);
        return documentId;
    }

    private static final String VISIBILITY_INTERNAL = 'InternalUsers';
    private static final String VISIBILITY_ALL = 'AllUsers';

    /**
     * True once the platform has refused an `InternalUsers` link in this transaction, which it
     * does on an org with no external users. Null until the first link is written.
     */
    @TestVisible
    private static Boolean orgRefusesInternalOnlyLinks;

    private static void insertLinks(Id documentId, Set<Id> targets, String visibility) {
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();
        for (Id target : targets) {
            links.add(
                new ContentDocumentLink(
                    ContentDocumentId = documentId,
                    LinkedEntityId = target,
                    ShareType = 'V',
                    Visibility = visibility
                )
            );
        }
        Database.insert(links, true, AccessLevel.SYSTEM_MODE);
    }

    /**
     * True when the save was refused over the Visibility value and nothing else. The letter
     * merge file's link asks the same (`AcknowledgmentWriter.storeMergeFile`).
     */
    public static Boolean refusedVisibility(DmlException refused) {
        for (Integer i = 0; i < refused.getNumDml(); i++) {
            if (
                refused.getDmlType(i) != StatusCode.INVALID_FIELD_FOR_INSERT_UPDATE ||
                !refused.getDmlFieldNames(i).contains('Visibility')
            ) {
                return false;
            }
        }
        return refused.getNumDml() > 0;
    }

    /** Raised when a caller asks for a link that would widen who can read a receipt. */
    public class ReceiptFileLinkException extends Exception {
    }

    /**
     * The two objects a receipt document may be linked to, and why only these two: a user reaches
     * either one only through a Giving permission set, and all three Giving sets grant read and
     * nothing more on `Receipt__c` (R-RC10). Anything else, and a donor's tax document is governed
     * by permissions that were never granted with it in mind.
     *
     * No custom permission is checked here. This is not an authorization decision made per user:
     * it is a shape the stored document always has, and getting it wrong is a code defect, which
     * is why it throws rather than quietly dropping the link.
     */
    private static void requireGoverningRecord(Id target) {
        Schema.SObjectType linked = target.getSObjectType();
        if (linked != Receipt__c.SObjectType && linked != Gift__c.SObjectType) {
            throw new ReceiptFileLinkException(
                'A receipt document is linked only to its receipt and its gift, not to ' +
                    String.valueOf(linked) +
                    '. Access to the file follows the linked record (ADR-0034).'
            );
        }
    }
}
