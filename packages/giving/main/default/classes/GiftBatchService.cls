/**
 * The rules of a gift batch (G-17): what a line takes from its batch, whether a batch balances,
 * and posting. Canonical model Sections 25L and 25M, rules R-GB1 to R-GB6 and R-GR1 to R-GR4.
 *
 * Posting takes the long way round on purpose. It inserts ordinary `Gift__c` records in user
 * mode, so the Gift triggers derive the household, create the default allocation and apply the
 * receipt lock exactly as they do for one gift typed on the quick entry screen (R-GB6). Nothing
 * here reimplements a gift rule to make twenty gifts faster.
 */
public with sharing class GiftBatchService {
    public static final String STATUS_POSTED = GiftBatchWriter.STATUS_POSTED;

    private static final String GIFT_STATUS_RECEIVED = 'Received';
    private static final String CONTEXT = 'GiftBatchService.post';

    /** One thing wrong with one line, in words the person typing can act on. */
    public class LineProblem {
        public Id rowId;
        public Integer lineNumber;
        public String message;

        public LineProblem(Id rowId, Integer lineNumber, String message) {
            this.rowId = rowId;
            this.lineNumber = lineNumber;
            this.message = message;
        }
    }

    /** What came of a post. */
    public class PostOutcome {
        public Boolean success = false;
        public Integer giftCount = 0;
        public String formError;
        public List<LineProblem> lineProblems = new List<LineProblem>();
    }

    /** The values a line's gift will carry: the line's own, else the batch's (R-GB1). */
    public class Resolved {
        public Date giftDate;
        public String paymentMethod;
        public Id fundId;
        public Id appealId;

        public Resolved(Gift_Batch__c batch, Gift_Batch_Row__c row) {
            this.giftDate = row.Gift_Date__c != null
                ? row.Gift_Date__c
                : batch.Default_Gift_Date__c;
            this.paymentMethod = String.isNotBlank(row.Payment_Method__c)
                ? row.Payment_Method__c
                : batch.Default_Payment_Method__c;
            this.fundId = row.Fund__c != null ? row.Fund__c : batch.Default_Fund__c;
            this.appealId = row.Appeal__c != null ? row.Appeal__c : batch.Default_Appeal__c;
        }
    }

    /** The sum of the line amounts, an empty amount counting as zero (R-GB2). */
    public static Decimal enteredTotal(List<Gift_Batch_Row__c> rows) {
        Decimal total = 0;
        for (Gift_Batch_Row__c row : rows) {
            total += row.Amount__c == null ? 0 : row.Amount__c;
        }
        return total;
    }

    /**
     * Everything wrong with the lines, all of it rather than the first thing found, because a
     * person fixing a batch wants the list (R-GR1 to R-GR3). Line numbers are positions in the
     * order the lines were entered, which is the order the grid shows.
     */
    public static List<LineProblem> validateRows(
        Gift_Batch__c batch,
        List<Gift_Batch_Row__c> rows
    ) {
        List<LineProblem> problems = new List<LineProblem>();
        for (Integer index = 0; index < rows.size(); index++) {
            Gift_Batch_Row__c row = rows[index];
            Integer line = index + 1;
            Boolean hasContact = row.Donor_Contact__c != null;
            Boolean hasAccount = row.Donor_Account__c != null;
            if (hasContact && hasAccount) {
                problems.add(
                    new LineProblem(row.Id, line, Label.Giving_GiftBatch_ErrorRowDonorBoth)
                );
            } else if (!hasContact && !hasAccount) {
                problems.add(
                    new LineProblem(row.Id, line, Label.Giving_GiftBatch_ErrorRowDonorMissing)
                );
            }
            if (row.Amount__c == null || row.Amount__c <= 0) {
                problems.add(new LineProblem(row.Id, line, Label.Giving_GiftBatch_ErrorRowAmount));
            }
            Resolved values = new Resolved(batch, row);
            if (values.giftDate == null) {
                problems.add(new LineProblem(row.Id, line, Label.Giving_GiftBatch_ErrorRowDate));
            }
            if (String.isBlank(values.paymentMethod)) {
                problems.add(
                    new LineProblem(row.Id, line, Label.Giving_GiftBatch_ErrorRowPaymentMethod)
                );
            }
        }
        Map<Id, Installment__c> payments = confirmedPayments(batch, rows);
        for (Integer index = 0; index < rows.size(); index++) {
            Gift_Batch_Row__c row = rows[index];
            if (row.Installment__c != null && !payments.containsKey(row.Id)) {
                problems.add(
                    new LineProblem(
                        row.Id,
                        index + 1,
                        Label.Giving_GiftBatch_ErrorRowPaymentNotOpen
                    )
                );
            }
        }
        return problems;
    }

    /**
     * R-GR5: for each line that names a scheduled payment its donor may still pay, that payment
     * with its commitment, by line. A line missing from the result named one it may not pay.
     */
    public static Map<Id, Installment__c> confirmedPayments(
        Gift_Batch__c batch,
        List<Gift_Batch_Row__c> rows
    ) {
        List<GiftEntryPayments.Request> requests = new List<GiftEntryPayments.Request>();
        Map<String, Id> chosen = new Map<String, Id>();
        for (Gift_Batch_Row__c row : rows) {
            if (row.Installment__c == null) {
                continue;
            }
            Resolved values = new Resolved(batch, row);
            requests.add(
                new GiftEntryPayments.Request(
                    row.Id,
                    row.Donor_Contact__c,
                    row.Donor_Account__c,
                    values.giftDate,
                    row.Amount__c
                )
            );
            chosen.put(row.Id, row.Installment__c);
        }
        Map<Id, Installment__c> byRow = new Map<Id, Installment__c>();
        if (requests.isEmpty()) {
            return byRow;
        }
        Map<String, Installment__c> confirmed = GiftEntryPayments.confirm(requests, chosen);
        for (String rowId : confirmed.keySet()) {
            byRow.put(Id.valueOf(rowId), confirmed.get(rowId));
        }
        return byRow;
    }

    /**
     * Posts a batch: every line becomes a gift, once, or nothing happens.
     *
     * The batch is read with a row lock first, so a second post waits and then finds it Posted
     * (R-GB4). The totals are compared inside the transaction that creates the gifts, so a stale
     * browser cannot post an unbalanced batch (R-GB3). Any failure rolls the whole posting back
     * (R-GB5).
     */
    public static PostOutcome post(Id batchId) {
        PostOutcome outcome = new PostOutcome();
        Savepoint before = Database.setSavepoint();
        try {
            Gift_Batch__c batch = batchId == null
                ? null
                : GiftBatchSelector.selectForUpdate(batchId);
            List<Gift_Batch_Row__c> rows = batch == null
                ? new List<Gift_Batch_Row__c>()
                : GiftBatchSelector.selectRows(batchId);
            outcome.formError = refusal(batch, rows);
            if (outcome.formError == null) {
                outcome.lineProblems = validateRows(batch, rows);
                if (!outcome.lineProblems.isEmpty()) {
                    outcome.formError = Label.Giving_GiftBatch_ErrorRowsIncomplete;
                }
            }
            if (outcome.formError == null) {
                outcome.lineProblems = createGifts(batch, rows);
                if (!outcome.lineProblems.isEmpty()) {
                    Database.rollback(before);
                    outcome.formError = Label.Giving_GiftBatch_ErrorPostFailed;
                    return outcome;
                }
                GiftBatchWriter.markPosted(batch.Id);
                outcome.success = true;
                outcome.giftCount = rows.size();
            }
            return outcome;
        } catch (Exception e) {
            Database.rollback(before);
            ErrorLogger.log(e, CONTEXT, batchId);
            PostOutcome failed = new PostOutcome();
            failed.formError = Label.Giving_GiftBatch_ErrorPostFailed;
            return failed;
        }
    }

    /** Why a batch cannot be posted at all, before its lines are looked at, or null. */
    private static String refusal(Gift_Batch__c batch, List<Gift_Batch_Row__c> rows) {
        if (batch == null) {
            return Label.Giving_GiftBatch_ErrorBatchMissing;
        }
        if (STATUS_POSTED.equals(batch.Status__c)) {
            return Label.Giving_GiftBatch_ErrorAlreadyPosted;
        }
        // Posting writes the batch and its lines. GiftBatchWriter does that in system mode but
        // with sharing, so someone who can only read this batch would reach it and fail there,
        // after the gifts: refuse them here, in words, before anything is created.
        if (!GiftBatchSelector.canEdit(batch.Id)) {
            return Label.Giving_GiftBatch_ErrorNoAccess;
        }
        if (rows.isEmpty()) {
            return Label.Giving_GiftBatch_ErrorNoRows;
        }
        if (batch.Control_Total__c == null) {
            return Label.Giving_GiftBatch_ErrorNoControlTotal;
        }
        Decimal gap = batch.Control_Total__c - enteredTotal(rows);
        if (gap == 0) {
            return null;
        }
        String template = gap > 0
            ? Label.Giving_GiftBatch_ErrorShortOfControlTotal
            : Label.Giving_GiftBatch_ErrorOverControlTotal;
        // Two decimals, no grouping, whatever the locale: the same text the grid shows for the
        // same gap (toFixed(2)), so the message a person searches for is the one on the screen.
        return template.replace('{0}', String.valueOf(gap.abs().setScale(2)));
    }

    /**
     * R-GB6: one ordinary gift per line, inserted in user mode. Every line the platform refuses is
     * reported with its own message rather than only the first, and the caller rolls back.
     */
    private static List<LineProblem> createGifts(
        Gift_Batch__c batch,
        List<Gift_Batch_Row__c> rows
    ) {
        List<Gift__c> gifts = new List<Gift__c>();
        List<Resolved> resolved = new List<Resolved>();
        // validateRows refused any line naming a payment it may not pay; read again here so each
        // gift carries its payment's commitment as it stands (R-GR5).
        Map<Id, Installment__c> payments = confirmedPayments(batch, rows);
        for (Gift_Batch_Row__c row : rows) {
            Resolved values = new Resolved(batch, row);
            resolved.add(values);
            Installment__c payment = payments.get(row.Id);
            gifts.add(
                new Gift__c(
                    Donor_Contact__c = row.Donor_Contact__c,
                    Donor_Account__c = row.Donor_Account__c,
                    Amount__c = row.Amount__c,
                    Gift_Date__c = values.giftDate,
                    Type__c = values.paymentMethod,
                    Status__c = GIFT_STATUS_RECEIVED,
                    Appeal__c = values.appealId,
                    Payment_Reference__c = row.Payment_Reference__c,
                    Installment__c = payment == null ? null : payment.Id,
                    Commitment__c = payment == null ? null : payment.Commitment__c
                )
            );
        }

        List<LineProblem> problems = new List<LineProblem>();
        List<Database.SaveResult> results = Database.insert(gifts, false, AccessLevel.USER_MODE);
        for (Integer index = 0; index < results.size(); index++) {
            if (!results[index].isSuccess()) {
                problems.add(
                    new LineProblem(
                        rows[index].Id,
                        index + 1,
                        results[index].getErrors()[0].getMessage()
                    )
                );
            }
        }
        if (!problems.isEmpty()) {
            return problems;
        }

        Map<Id, Id> giftIdByRowId = new Map<Id, Id>();
        Map<Id, Id> fundIdByGiftId = new Map<Id, Id>();
        for (Integer index = 0; index < rows.size(); index++) {
            giftIdByRowId.put(rows[index].Id, gifts[index].Id);
            if (resolved[index].fundId != null) {
                fundIdByGiftId.put(gifts[index].Id, resolved[index].fundId);
            }
        }
        // The same designation step quick gift entry uses. A gift the fund could not be applied
        // to (already split by some other automation) fails the post rather than losing the
        // line's designation.
        Set<Id> notApplied = GiftService.applyChosenFunds(gifts, fundIdByGiftId);
        for (Integer index = 0; index < rows.size(); index++) {
            if (notApplied.contains(gifts[index].Id)) {
                problems.add(
                    new LineProblem(
                        rows[index].Id,
                        index + 1,
                        Label.Giving_GiftBatch_ErrorPostFailed
                    )
                );
            }
        }
        if (problems.isEmpty()) {
            GiftBatchWriter.linkGifts(giftIdByRowId);
        }
        return problems;
    }
}
