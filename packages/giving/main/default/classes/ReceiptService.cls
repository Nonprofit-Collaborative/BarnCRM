/**
 * Issuing, voiding and reissuing receipts (feature G-13, ADR-0010, ADR-0016).
 *
 * Three rules run through everything here and none of them is negotiable:
 *
 * - **A number is consumed once and never reused.** `ReceiptNumberSequence` owns that; this class
 *   never invents, reuses or rolls back a number.
 * - **Voiding never touches the stored file.** A void writes a reason and a date on the receipt
 *   record and leaves the document exactly as the donor received it.
 * - **Regeneration is never an update.** It is a void plus a new receipt, with the two records
 *   pointing at each other.
 */
public with sharing class ReceiptService {
    public static final String STATUS_ISSUED = 'Issued';
    public static final String STATUS_VOID = 'Void';

    /**
     * The permission to issue, void and reissue. Bare, and correctly so: a custom permission
     * defined in the same package resolves without a namespace prefix.
     */
    public static final String ISSUE_RECEIPTS_PERMISSION = 'Issue_Receipts';

    public class ReceiptServiceException extends Exception {
    }

    /**
     * Issues one receipt for one gift and returns it.
     *
     * The order matters. The number is consumed first, because a number that was handed out and
     * then not used is recoverable (R-RC3 accounts for it) while two receipts carrying the same
     * number are not. The document is rendered next, then stored, then the receipt record is
     * written, and only then does the gift learn its receipt number, which is the point at which
     * the gift becomes locked (R-G4).
     *
     * **A caller must let a failure here propagate all the way out, so the transaction rolls
     * back.** That is not style, it is the only thing accounting for the per gift number series:
     * nothing reconciles it. `ReceiptNumberSequence.reconcile` runs for the statement series from
     * `ReceiptStatementBatch.finish` and for nothing else, and the Health Check finding added in
     * C-11 counts only what that pass wrote. `ReceiptController.issue` rethrows, so today the
     * number and the receipt stand or fall together. A future caller that catches this exception
     * and carries on, a bulk action or an async retry wrapper, consumes a number that no pass will
     * ever explain and that the Health Check will report as zero. Build the per gift
     * reconciliation pass before writing that caller (ADR-0016, "Numbering").
     */
    public static Receipt__c issueForGift(Id giftId) {
        requireIssuePermission();
        Gift__c gift = ReceiptSelector.giftForReceipting(giftId);
        if (gift == null) {
            throw new ReceiptServiceException(Label.Giving_Receipt_GiftNotFound);
        }
        if (String.isNotBlank(gift.Receipt_Number__c)) {
            throw new ReceiptServiceException(Label.Giving_Receipt_GiftAlreadyReceipted);
        }
        // No money has arrived for a Pending or Cancelled gift, and a receipt says it has. The
        // statement run leaves the same two statuses out (R-RC8, R-G16).
        if ('Pending'.equals(gift.Status__c) || 'Cancelled'.equals(gift.Status__c)) {
            throw new ReceiptServiceException(Label.Giving_Receipt_GiftNotReceived);
        }

        Integer statementYear = gift.Gift_Date__c == null
            ? Date.today().year()
            : gift.Gift_Date__c.year();
        String allocated = ReceiptNumberSequence.allocateOne(
            ReceiptNumberSequence.TYPE_PER_GIFT,
            statementYear
        );

        String donorName = donorNameFor(gift.Donor_Contact__c, gift.Donor_Account__c);
        String html = ReceiptContentBuilder.forGift(
            gift,
            donorName,
            allocated,
            Date.today(),
            ReceiptTemplateService.activeBodyFor(ReceiptNumberSequence.TYPE_PER_GIFT)
        );

        Receipt__c receipt = new Receipt__c(
            Receipt_Number__c = allocated,
            Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
            Status__c = STATUS_ISSUED,
            Statement_Year__c = statementYear,
            Gift__c = gift.Id,
            Donor_Contact__c = gift.Donor_Contact__c,
            Donor_Account__c = gift.Donor_Account__c,
            Household__c = gift.Household__c,
            // What the document states, which for a gift of goods or services is nothing at all
            // (R-RC12). The value the organization recorded stays on the gift.
            Total_Amount__c = ReceiptContentBuilder.statedAmountOf(gift),
            Issue_Date__c = Date.today(),
            Series_Key__c = ReceiptNumberSequence.seriesKeyFor(
                ReceiptNumberSequence.TYPE_PER_GIFT,
                statementYear
            )
        );
        ReceiptWriter.insertReceipts(new List<Receipt__c>{ receipt });

        // The receipt and the gift, and deliberately not the donor Contact or Account: a file's
        // audience is the audience of the records it is linked to, and every Core role can read a
        // Contact and an Account (ADR-0034). The donor still finds the document, through the
        // Receipts related list on their record, which needs a Giving permission set.
        storeDocumentFor(receipt, html, new List<Id>{ receipt.Id, gift.Id });

        GiftService.recordReceiptNumbers(new Map<Id, String>{ gift.Id => allocated });
        return receipt;
    }

    /**
     * Voids a receipt. It writes a reason and a date and nothing else: the stored file is left
     * alone on purpose, because the donor still holds their copy and so should the organization
     * (R-RC4).
     */
    public static Receipt__c voidReceipt(Id receiptId, String reason) {
        requireIssuePermission();
        if (String.isBlank(reason)) {
            throw new ReceiptServiceException(Label.Giving_Receipt_VoidNeedsReason);
        }
        Receipt__c receipt = ReceiptSelector.byId(receiptId);
        if (receipt == null) {
            throw new ReceiptServiceException(Label.Giving_Receipt_NotFound);
        }
        if (STATUS_VOID.equals(receipt.Status__c)) {
            throw new ReceiptServiceException(Label.Giving_Receipt_AlreadyVoid);
        }
        receipt.Status__c = STATUS_VOID;
        receipt.Void_Reason__c = reason.trim();
        receipt.Voided_On__c = System.now();
        // The idempotency key is cleared so that the donor can be receipted again for the same
        // year: the key exists to stop a retried batch chunk issuing twice, not to stop a
        // correction (R-RC9).
        receipt.Donor_Year_Key__c = null;
        ReceiptWriter.updateReceipts(new List<Receipt__c>{ receipt });
        return receipt;
    }

    /**
     * Voids a receipt and issues its replacement (R-RC5).
     *
     * The replacement takes the next number in the same series, never the voided one, and the two
     * records point at each other so that a person holding either can find the other.
     */
    public static Receipt__c voidAndReissue(Id receiptId, String reason) {
        requireIssuePermission();
        Receipt__c original = ReceiptSelector.byId(receiptId);
        if (original == null) {
            throw new ReceiptServiceException(Label.Giving_Receipt_NotFound);
        }
        if (original.Gift__c == null) {
            throw new ReceiptServiceException(Label.Giving_Receipt_ReissueNeedsGift);
        }

        voidReceipt(receiptId, reason);
        // The gift is unlocked for exactly one write, the new number, and locked again by the
        // finally block inside GiftService.
        clearGiftReceiptNumber(original.Gift__c);

        Receipt__c replacement = issueForGift(original.Gift__c);
        // Two field writes on two records, each as a fresh sObject: updating the instance read
        // before the void would write its stale copy of the void reason back over the real one.
        ReceiptWriter.updateReceipts(
            new List<Receipt__c>{
                new Receipt__c(Id = replacement.Id, Replaces__c = original.Id),
                new Receipt__c(Id = original.Id, Replaced_By__c = replacement.Id)
            }
        );
        replacement.Replaces__c = original.Id;
        return replacement;
    }

    /**
     * Issues one consolidated statement, for the batch. The number is passed in because the batch
     * allocates its whole block in one locked update rather than one number at a time (R-RS1).
     */
    public static Receipt__c issueStatement(
        Account donor,
        List<Gift__c> gifts,
        Integer statementYear,
        String allocated,
        Id runId,
        String templateBody,
        ReceiptRenderer renderer
    ) {
        String seriesKey = ReceiptNumberSequence.seriesKeyFor(
            ReceiptNumberSequence.TYPE_STATEMENT,
            statementYear
        );
        String html = ReceiptContentBuilder.forStatement(
            donor.Name,
            gifts,
            allocated,
            statementYear,
            Date.today(),
            templateBody
        );

        Receipt__c receipt = new Receipt__c(
            Receipt_Number__c = allocated,
            Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
            Status__c = STATUS_ISSUED,
            Statement_Year__c = statementYear,
            Donor_Account__c = donor.Id,
            Total_Amount__c = ReceiptContentBuilder.cashTotalOf(gifts),
            Issue_Date__c = Date.today(),
            Series_Key__c = seriesKey,
            Donor_Year_Key__c = donorYearKey(
                donor.Id,
                statementYear,
                ReceiptNumberSequence.TYPE_STATEMENT
            ),
            Receipt_Run__c = runId
        );
        ReceiptWriter.insertReceipts(new List<Receipt__c>{ receipt });
        // The receipt only. A year end statement is the whole of a donor's giving, their address
        // and the organization's tax identifiers in one document, and linking it to the donor
        // Account put it in the Files list of a record every Core role can read (ADR-0034).
        storeDocumentFor(receipt, html, new List<Id>{ receipt.Id }, renderer);
        return receipt;
    }

    /**
     * Donor, year and type as one value. Unique on the record, so a batch chunk that is retried
     * after a failure resumes the run rather than sending a second document to the same donor
     * (R-RC9, R-RR2).
     */
    public static String donorYearKey(Id donorId, Integer statementYear, String receiptType) {
        return String.valueOf(donorId) + '|' + String.valueOf(statementYear) + '|' + receiptType;
    }

    // ----------------------------------------------------------------------- internals

    private static void storeDocumentFor(Receipt__c receipt, String html, List<Id> linkTo) {
        storeDocumentFor(receipt, html, linkTo, ReceiptRendererFactory.get());
    }

    /**
     * Renders, stores, and records where the bytes went. The blob is a local: nothing holds a PDF
     * beyond this method, which is what keeps a batch chunk inside the async heap limit.
     */
    private static void storeDocumentFor(
        Receipt__c receipt,
        String html,
        List<Id> linkTo,
        ReceiptRenderer renderer
    ) {
        Blob rendered = renderer.render(html);
        Id documentId = ReceiptWriter.storeDocument(receipt.Receipt_Number__c, rendered, linkTo);
        receipt.Content_Document_Id__c = documentId;
        ReceiptWriter.updateReceipts(new List<Receipt__c>{ receipt });
    }

    private static void clearGiftReceiptNumber(Id giftId) {
        GiftService.recordReceiptNumbers(new Map<Id, String>{ giftId => null });
    }

    private static String donorNameFor(Id donorContactId, Id donorAccountId) {
        if (donorContactId != null) {
            List<Contact> people = [
                SELECT Id, Name
                FROM Contact
                WHERE Id = :donorContactId
                WITH USER_MODE
                LIMIT 1
            ];
            return people.isEmpty() ? '' : people[0].Name;
        }
        if (donorAccountId != null) {
            List<Account> accounts = [
                SELECT Id, Name
                FROM Account
                WHERE Id = :donorAccountId
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? '' : accounts[0].Name;
        }
        return '';
    }

    /**
     * True when the running user may issue, void and reissue. Read once per transaction: the
     * answer cannot change inside one, and a batch chunk would otherwise ask the same question
     * twenty five times.
     *
     * Visible to tests because a custom permission cannot be granted to the user a test runs as
     * without assigning a permission set, which would make every receipting test a test of
     * permission set assignment.
     */
    @TestVisible
    private static Boolean issuePermission = null;

    public static Boolean canIssueReceipts() {
        if (issuePermission == null) {
            issuePermission = FeatureManagement.checkPermission(ISSUE_RECEIPTS_PERMISSION);
        }
        return issuePermission;
    }

    /**
     * The gate every issuing path passes. Public because `ReceiptTemplateService` needs the same
     * answer before it materializes a shipped letter on the issuing path, and one gate stated once
     * is what ADR-0021 asks for (ADR-0034).
     */
    public static void requireIssuePermission() {
        if (!canIssueReceipts()) {
            throw new ReceiptServiceException(Label.Giving_Receipt_NoPermission);
        }
    }
}
