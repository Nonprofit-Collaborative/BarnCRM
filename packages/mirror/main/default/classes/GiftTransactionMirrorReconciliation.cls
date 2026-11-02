/**
 * The Gift Transaction mirror reconciliation (feature X-07, R-GT10): for a date range, the gifts
 * the mirror copies (R-GT3) against the Gift Transactions of the paid status, each side's count
 * and total, and every difference.
 *
 * The shape of the Opportunity mirror's (R-OM11): a page rather than a report, because a packaged
 * report type over a Nonprofit Cloud object would stop Mirror installing without it. It reads in
 * user mode and writes nothing, so each person sees the differences among the records they can
 * see. A range too large to compare in one transaction is refused rather than shown in part: each
 * side's read stops one past the most it compares, and the reads' rows at that most must fit what
 * the transaction has left.
 */
public with sharing class GiftTransactionMirrorReconciliation {
    /** The most gifts, and separately the most Gift Transactions, one comparison reads. */
    @TestVisible
    private static Integer maxRecords = 10000;
    /** The most differences listed; the count still covers them all. */
    @TestVisible
    private static Integer maxRows = 500;

    public class ReconciliationException extends Exception {
    }

    /** One gift, one Gift Transaction, or a linked pair, and why they are listed. */
    public class Difference {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Id giftId;
        @AuraEnabled
        public String giftName;
        @AuraEnabled
        public Decimal giftAmount;
        @AuraEnabled
        public Date giftDate;
        @AuraEnabled
        public String giftTransactionId;
        @AuraEnabled
        public String giftTransactionName;
        @AuraEnabled
        public Decimal giftTransactionAmount;
        @AuraEnabled
        public Date transactionDate;
        @AuraEnabled
        public String reason;
    }

    /** What the page shows for a range. */
    public class Comparison {
        @AuraEnabled
        public Integer giftCount = 0;
        @AuraEnabled
        public Decimal giftTotal = 0;
        @AuraEnabled
        public Integer giftTransactionCount = 0;
        @AuraEnabled
        public Decimal giftTransactionTotal = 0;
        @AuraEnabled
        public Integer differenceCount = 0;
        @AuraEnabled
        public List<Difference> differences = new List<Difference>();

        private void add(Difference difference) {
            differenceCount++;
            if (differences.size() < maxRows) {
                difference.key = difference.giftId != null
                    ? String.valueOf(difference.giftId)
                    : difference.giftTransactionId;
                differences.add(difference);
            }
        }
    }

    /**
     * Compares the gifts of R-GT3 dated in the range with the Gift Transactions of the paid status
     * dated in it, as the running user can see them.
     *
     * @throws ReconciliationException, in words the page shows as they are
     */
    public static Comparison compare(Date fromDate, Date toDate) {
        checkReady(fromDate, toDate);
        String status = GiftTransactionMirrorService.paidStatus();
        String objectName = GiftTransactionMirrorSchema.objectName();
        Integer cap = maxRecords + 1;
        // Each gift can cost a second row for its Gift Transaction, each one a check for a gift.
        if (4 * cap > Limits.getLimitQueryRows() - Limits.getQueryRows()) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_ErrorTooMany);
        }
        List<SObject> paid = GiftTransactionMirrorSelector.giftTransactionsInRange(
            objectName,
            status,
            fromDate,
            toDate,
            cap
        );
        List<Gift__c> gifts = (List<Gift__c>) Database.queryWithBinds(
            GiftTransactionMirrorSelector.GIFTS_IN_RANGE_QUERY,
            new Map<String, Object>{
                'statuses' => GiftTransactionMirrorService.MIRRORED_STATUSES,
                'inKind' => GiftTransactionMirrorService.TYPE_IN_KIND,
                'fromDate' => fromDate,
                'toDate' => toDate,
                'cap' => cap
            },
            AccessLevel.USER_MODE
        );
        if (paid.size() > maxRecords || gifts.size() > maxRecords) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_ErrorTooMany);
        }

        Comparison result = new Comparison();
        Map<String, SObject> paidById = new Map<String, SObject>();
        for (SObject giftTransaction : paid) {
            paidById.put(String.valueOf(giftTransaction.Id), giftTransaction);
            result.giftTransactionCount++;
            result.giftTransactionTotal += amountOf(giftTransaction);
        }

        Schema.SObjectType giftTransactionType = GiftTransactionMirrorSchema.objectType();
        Set<String> named = new Set<String>();
        // A gift in the range may name a Gift Transaction dated outside it, or of another status.
        List<Gift__c> elsewhere = new List<Gift__c>();
        Set<Id> elsewhereIds = new Set<Id>();
        for (Gift__c gift : gifts) {
            result.giftCount++;
            result.giftTotal += gift.Amount__c == null ? 0 : gift.Amount__c;
            if (gift.Gift_Transaction_Id__c == null) {
                result.add(
                    pair(gift, null, Label.Mirror_GiftTransactionMirror_DiffNoGiftTransaction)
                );
            } else if (paidById.containsKey(gift.Gift_Transaction_Id__c)) {
                named.add(gift.Gift_Transaction_Id__c);
                compareLinked(result, gift, paidById.get(gift.Gift_Transaction_Id__c), status);
            } else {
                elsewhere.add(gift);
                Id linked = MirrorSync.idOf(gift.Gift_Transaction_Id__c, giftTransactionType);
                if (linked != null) {
                    elsewhereIds.add(linked);
                }
            }
        }
        Map<Id, SObject> otherById = GiftTransactionMirrorSelector.giftTransactionsById(
            objectName,
            GiftTransactionMirrorSchema.read(),
            elsewhereIds
        );
        for (Gift__c gift : elsewhere) {
            Id linked = MirrorSync.idOf(gift.Gift_Transaction_Id__c, giftTransactionType);
            compareLinked(result, gift, linked == null ? null : otherById.get(linked), status);
        }

        // A paid Gift Transaction is without a gift only when no gift the mirror copies names it.
        Set<String> unnamed = new Set<String>(paidById.keySet());
        unnamed.removeAll(named);
        unnamed.removeAll(
            GiftTransactionMirrorSelector.linkedByMirroredGifts(
                unnamed,
                GiftTransactionMirrorService.MIRRORED_STATUSES,
                GiftTransactionMirrorService.TYPE_IN_KIND
            )
        );
        for (SObject giftTransaction : paid) {
            if (unnamed.contains(String.valueOf(giftTransaction.Id))) {
                result.add(
                    pair(null, giftTransaction, Label.Mirror_GiftTransactionMirror_DiffNoGift)
                );
            }
        }
        return result;
    }

    /** Refuses a comparison that cannot be made, in words the page shows. */
    private static void checkReady(Date fromDate, Date toDate) {
        if (fromDate == null || toDate == null) {
            throw new ReconciliationException(
                Label.Mirror_GiftTransactionMirror_ErrorDatesRequired
            );
        }
        if (fromDate > toDate) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_ErrorDateOrder);
        }
        if (!GiftTransactionMirrorService.isAvailable()) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_Unavailable);
        }
        String status = GiftTransactionMirrorService.paidStatus();
        if (!GiftTransactionMirrorSchema.isActiveStatus(status)) {
            throw new ReconciliationException(
                String.format(
                    Label.Mirror_GiftTransactionMirror_UnknownStatus,
                    new List<Object>{ status }
                )
            );
        }
        // User mode reads of a field the viewer cannot see fail with the platform's own words.
        if (!Gift__c.Gift_Transaction_Id__c.getDescribe().isAccessible()) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_NoLinkAccess);
        }
        if (!GiftTransactionMirrorSchema.canRead(GiftTransactionMirrorSchema.read())) {
            throw new ReconciliationException(Label.Mirror_GiftTransactionMirror_NoRead);
        }
    }

    /** Lists a linked gift whose Gift Transaction is gone or differs from it. */
    private static void compareLinked(
        Comparison result,
        Gift__c gift,
        SObject giftTransaction,
        String status
    ) {
        if (giftTransaction == null) {
            Difference missing = pair(gift, null, Label.Mirror_GiftTransactionMirror_DiffMissing);
            missing.giftTransactionId = gift.Gift_Transaction_Id__c;
            result.add(missing);
            return;
        }
        GiftTransactionMirrorSchema.Names names = GiftTransactionMirrorSchema.names;
        List<String> reasons = new List<String>();
        Decimal giftAmount = gift.Amount__c == null ? 0 : gift.Amount__c;
        if (giftAmount != amountOf(giftTransaction)) {
            reasons.add(Label.Mirror_GiftTransactionMirror_DiffAmount);
        }
        if (gift.Gift_Date__c != (Date) giftTransaction.get(names.dateField)) {
            reasons.add(Label.Mirror_GiftTransactionMirror_DiffDate);
        }
        if (!MirrorSync.same(status, giftTransaction.get(names.statusField))) {
            reasons.add(Label.Mirror_GiftTransactionMirror_DiffStatus);
        }
        if (!reasons.isEmpty()) {
            result.add(pair(gift, giftTransaction, String.join(reasons, ', ')));
        }
    }

    private static Difference pair(Gift__c gift, SObject giftTransaction, String reason) {
        Difference difference = new Difference();
        difference.reason = reason;
        if (gift != null) {
            difference.giftId = gift.Id;
            difference.giftName = gift.Name;
            difference.giftAmount = gift.Amount__c;
            difference.giftDate = gift.Gift_Date__c;
        }
        if (giftTransaction != null) {
            GiftTransactionMirrorSchema.Names names = GiftTransactionMirrorSchema.names;
            Object name = giftTransaction.get(names.nameField);
            difference.giftTransactionId = String.valueOf(giftTransaction.Id);
            difference.giftTransactionName = name == null ? null : String.valueOf(name);
            difference.giftTransactionAmount = amountOf(giftTransaction);
            difference.transactionDate = (Date) giftTransaction.get(names.dateField);
        }
        return difference;
    }

    private static Decimal amountOf(SObject giftTransaction) {
        Decimal amount = GiftTransactionMirrorSchema.decimalOf(
            giftTransaction.get(GiftTransactionMirrorSchema.names.amountField)
        );
        return amount == null ? 0 : amount;
    }
}
