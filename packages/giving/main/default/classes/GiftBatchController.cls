/**
 * Gift batch entry (G-17). Serves the `giftBatchEntry` grid on the gift batch record page: the
 * batch and its lines, saving what has been typed, and posting.
 *
 * The batch's own fields (control total and defaults) are edited on the record page itself, so
 * this class never writes the batch. Every rule lives in `GiftBatchService`; this class checks
 * what arrived from the browser and keeps unexpected failures out of the person's face, logging
 * them to the Error Log (plan Section 2.3).
 */
public with sharing class GiftBatchController {
    private static final String CONTEXT = 'GiftBatchController';

    /** A batch and everything the grid needs to draw it. */
    public class BatchView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Boolean posted;
        @AuraEnabled
        public Decimal controlTotal;
        @AuraEnabled
        public Decimal enteredTotal;
        @AuraEnabled
        public Boolean hasPersonAccounts;
        /** False for someone who may only read this batch: the grid then offers no buttons. */
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<Option> paymentMethods = new List<Option>();
        @AuraEnabled
        public List<Line> lines = new List<Line>();
    }

    /** One choice in the payment method list. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;

        public Option(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    /** One line, as the grid shows it and sends it back. */
    public class Line {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String donorContactId;
        @AuraEnabled
        public String donorAccountId;
        @AuraEnabled
        public Decimal amount;
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public String paymentMethod;
        @AuraEnabled
        public String paymentReference;
        @AuraEnabled
        public String fundId;
        @AuraEnabled
        public String appealId;
        /** The scheduled payment this line's gift pays, or empty (R-GR5). */
        @AuraEnabled
        public String installmentId;
        /** The grid's own name for a line, saved or not, so payment choices find their line. */
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String giftId;
        @AuraEnabled
        public String giftName;

        /** Used when the grid sends a line back. */
        public Line() {
            return;
        }

        public Line(Gift_Batch_Row__c row) {
            this.installmentId = row.Installment__c;
            this.id = row.Id;
            this.donorContactId = row.Donor_Contact__c;
            this.donorAccountId = row.Donor_Account__c;
            this.amount = row.Amount__c;
            this.giftDate = row.Gift_Date__c;
            this.paymentMethod = row.Payment_Method__c;
            this.paymentReference = row.Payment_Reference__c;
            this.fundId = row.Fund__c;
            this.appealId = row.Appeal__c;
            this.giftId = row.Gift__c;
            this.giftName = row.Gift__c == null ? null : row.Gift__r.Name;
        }
    }

    /** One message the grid shows beside one line. */
    public class LineError {
        @AuraEnabled
        public String lineId;
        @AuraEnabled
        public Integer lineNumber;
        @AuraEnabled
        public String message;
    }

    /** What came of a post. */
    public class PostResult {
        @AuraEnabled
        public Boolean success = false;
        @AuraEnabled
        public Integer giftCount = 0;
        @AuraEnabled
        public String formError;
        @AuraEnabled
        public List<LineError> lineErrors = new List<LineError>();
    }

    /** The batch and its lines, for opening it. */
    @AuraEnabled
    public static BatchView getBatch(Id batchId) {
        try {
            return view(batchId);
        } catch (GiftBatchException e) {
            throw asAuraException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getBatch', batchId);
            throw asAuraException(Label.Giving_GiftBatch_ErrorLoadBatch);
        }
    }

    /**
     * Saves the whole grid in one transaction: changed lines, new lines and removed lines arrive
     * together, so the batch is never half saved. Returns the batch as the server now holds it.
     */
    @AuraEnabled
    public static BatchView saveLines(Id batchId, List<Line> lines, List<String> removedLineIds) {
        try {
            Gift_Batch__c batch = GiftBatchSelector.selectForUpdate(batchId);
            if (batch == null) {
                throw new GiftBatchException(Label.Giving_GiftBatch_ErrorBatchMissing);
            }
            if (GiftBatchService.STATUS_POSTED.equals(batch.Status__c)) {
                throw new GiftBatchException(Label.Giving_GiftBatch_ErrorEditAfterPost);
            }
            if (!GiftBatchSelector.canEdit(batchId)) {
                throw new GiftBatchException(Label.Giving_GiftBatch_ErrorNoAccess);
            }
            Set<Id> existing = new Map<Id, Gift_Batch_Row__c>(GiftBatchSelector.selectRows(batchId))
                .keySet();
            upsertLines(batchId, lines, existing);
            deleteLines(removedLineIds, existing);
            return view(batchId);
        } catch (GiftBatchException e) {
            throw asAuraException(e.getMessage());
        } catch (DmlException e) {
            ErrorLogger.log(e, CONTEXT + '.saveLines', batchId);
            throw asAuraException(e.getDmlMessage(0));
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.saveLines', batchId);
            throw asAuraException(Label.Giving_GiftBatch_ErrorSaveRows);
        }
    }

    /**
     * The scheduled payments each line's donor still owes, for the Pays column (R-GR5, R-DM8),
     * one answer per line key in one lookup. A line with no date of its own is matched on the
     * batch's date (R-GB1).
     */
    @AuraEnabled
    public static List<GiftEntryPayments.Choices> getPaymentChoices(Id batchId, List<Line> lines) {
        try {
            Gift_Batch__c batch = batchId == null ? null : GiftBatchSelector.selectById(batchId);
            if (batch == null) {
                throw new GiftBatchException(Label.Giving_GiftBatch_ErrorBatchMissing);
            }
            List<GiftEntryPayments.Request> requests = new List<GiftEntryPayments.Request>();
            for (Line line : lines == null ? new List<Line>() : lines) {
                requests.add(
                    new GiftEntryPayments.Request(
                        line.key,
                        asId(line.donorContactId, Contact.SObjectType),
                        asId(line.donorAccountId, Account.SObjectType),
                        line.giftDate != null ? line.giftDate : batch.Default_Gift_Date__c,
                        line.amount
                    )
                );
            }
            return GiftEntryPayments.forRequests(requests).values();
        } catch (GiftBatchException e) {
            throw asAuraException(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, CONTEXT + '.getPaymentChoices', batchId);
            throw asAuraException(Label.Giving_GiftEntryPays_ErrorLoad);
        }
    }

    /** Posts the batch. Everything that decides whether it may is in `GiftBatchService.post`. */
    @AuraEnabled
    public static PostResult postBatch(Id batchId) {
        GiftBatchService.PostOutcome outcome = GiftBatchService.post(batchId);
        PostResult result = new PostResult();
        result.success = outcome.success;
        result.giftCount = outcome.giftCount;
        result.formError = outcome.formError;
        for (GiftBatchService.LineProblem problem : outcome.lineProblems) {
            LineError error = new LineError();
            error.lineId = problem.rowId;
            error.lineNumber = problem.lineNumber;
            error.message = problem.message;
            result.lineErrors.add(error);
        }
        return result;
    }

    private static void upsertLines(Id batchId, List<Line> lines, Set<Id> existing) {
        List<Gift_Batch_Row__c> inserts = new List<Gift_Batch_Row__c>();
        List<Gift_Batch_Row__c> updates = new List<Gift_Batch_Row__c>();
        Set<String> methods = paymentMethodValues();
        for (Line line : lines == null ? new List<Line>() : lines) {
            Gift_Batch_Row__c row = new Gift_Batch_Row__c(
                Donor_Contact__c = asId(line.donorContactId, Contact.SObjectType),
                Donor_Account__c = asId(line.donorAccountId, Account.SObjectType),
                Amount__c = line.amount,
                Gift_Date__c = line.giftDate,
                Payment_Method__c = methods.contains(line.paymentMethod)
                    ? line.paymentMethod
                    : null,
                Payment_Reference__c = line.paymentReference,
                Fund__c = asId(line.fundId, Fund__c.SObjectType),
                Appeal__c = asId(line.appealId, Appeal__c.SObjectType),
                Installment__c = asId(line.installmentId, Installment__c.SObjectType)
            );
            Id rowId = asId(line.id, Gift_Batch_Row__c.SObjectType);
            if (rowId == null) {
                row.Gift_Batch__c = batchId;
                inserts.add(row);
            } else if (existing.contains(rowId)) {
                row.Id = rowId;
                updates.add(row);
            } else {
                throw new GiftBatchException(Label.Giving_GiftBatch_ErrorLineMissing);
            }
        }
        if (!updates.isEmpty()) {
            Database.update(updates, true, AccessLevel.USER_MODE);
        }
        if (!inserts.isEmpty()) {
            Database.insert(inserts, true, AccessLevel.USER_MODE);
        }
    }

    /** Only lines of this batch are deleted, so a browser cannot ask for anything else to go. */
    private static void deleteLines(List<String> removedLineIds, Set<Id> existing) {
        List<Gift_Batch_Row__c> doomed = new List<Gift_Batch_Row__c>();
        for (String value : removedLineIds == null ? new List<String>() : removedLineIds) {
            Id rowId = asId(value, Gift_Batch_Row__c.SObjectType);
            if (rowId != null && existing.contains(rowId)) {
                doomed.add(new Gift_Batch_Row__c(Id = rowId));
            }
        }
        if (!doomed.isEmpty()) {
            Database.delete(doomed, true, AccessLevel.USER_MODE);
        }
    }

    private static BatchView view(Id batchId) {
        Gift_Batch__c batch = batchId == null ? null : GiftBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new GiftBatchException(Label.Giving_GiftBatch_ErrorBatchMissing);
        }
        List<Gift_Batch_Row__c> rows = GiftBatchSelector.selectRows(batchId);
        BatchView result = new BatchView();
        result.id = batch.Id;
        result.posted = GiftBatchService.STATUS_POSTED.equals(batch.Status__c);
        result.controlTotal = batch.Control_Total__c;
        result.enteredTotal = GiftBatchService.enteredTotal(rows);
        result.hasPersonAccounts = OrgShapeDetector.hasPersonAccounts();
        result.canEdit = GiftBatchSelector.canEdit(batch.Id);
        result.paymentMethods = paymentMethodOptions();
        for (Gift_Batch_Row__c row : rows) {
            result.lines.add(new Line(row));
        }
        return result;
    }

    private static List<Option> paymentMethodOptions() {
        List<Option> options = new List<Option>();
        for (
            Schema.PicklistEntry entry : Gift_Batch_Row__c.Payment_Method__c.getDescribe()
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                options.add(new Option(entry.getLabel(), entry.getValue()));
            }
        }
        return options;
    }

    private static Set<String> paymentMethodValues() {
        Set<String> values = new Set<String>();
        for (Option option : paymentMethodOptions()) {
            values.add(option.value);
        }
        return values;
    }

    /**
     * Anything that is not an identifier of the expected kind is treated as no value, so a record
     * deleted since the grid was drawn never blocks a save.
     */
    private static Id asId(String value, Schema.SObjectType expected) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            Id parsed = Id.valueOf(value.trim());
            return parsed.getSobjectType() == expected ? parsed : null;
        } catch (System.StringException e) {
            return null;
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }

    /** A refusal the person can act on, shown as it is rather than logged. */
    public class GiftBatchException extends Exception {
    }
}
