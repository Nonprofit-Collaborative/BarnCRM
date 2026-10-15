/**
 * The Opportunity mirror reconciliation (feature X-01, R-OM11): for a date range, the gifts in the
 * totals against the won Opportunities, each side's count and total, and every difference.
 *
 * A page rather than a report, because a packaged report type over Opportunity would stop Mirror
 * installing where Opportunity does not exist (ADR-0013). It reads in user mode and writes
 * nothing, so each person sees the differences among the records they can see. A range too large
 * to compare in one transaction is refused rather than shown in part (ADR-0051): each side's read
 * stops one past the most it compares, the four reads' rows at that most (both sides, the
 * Opportunities gifts name outside the range, the gifts naming the won ones) must fit what the
 * transaction has left, and the gifts are read 200 at a time, keeping only those whose
 * Opportunity is looked up after.
 */
public with sharing class OpportunityMirrorReconciliation {
    /** The most gifts, and separately the most won Opportunities, one comparison reads. */
    @TestVisible
    private static Integer maxRecords = 10000;
    /** The most differences listed; the count still covers them all. */
    @TestVisible
    private static Integer maxRows = 500;

    public class ReconciliationException extends Exception {
    }

    /** One gift, one Opportunity, or a linked pair, and why they are listed. */
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
        public String opportunityId;
        @AuraEnabled
        public String opportunityName;
        @AuraEnabled
        public Decimal opportunityAmount;
        @AuraEnabled
        public Date closeDate;
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
        public Integer opportunityCount = 0;
        @AuraEnabled
        public Decimal opportunityTotal = 0;
        @AuraEnabled
        public Integer differenceCount = 0;
        @AuraEnabled
        public List<Difference> differences = new List<Difference>();

        private void add(Difference difference) {
            differenceCount++;
            if (differences.size() < maxRows) {
                difference.key = difference.giftId != null
                    ? String.valueOf(difference.giftId)
                    : difference.opportunityId;
                differences.add(difference);
            }
        }
    }

    /**
     * Compares the gifts in the totals dated in the range with the won Opportunities closed in
     * it, as the running user can see them.
     *
     * @throws ReconciliationException, in words the page shows as they are
     */
    public static Comparison compare(Date fromDate, Date toDate) {
        if (fromDate == null || toDate == null) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_ErrorDatesRequired);
        }
        if (fromDate > toDate) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_ErrorDateOrder);
        }
        if (!OpportunityMirrorService.isAvailable()) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_Unavailable);
        }
        // User mode reads of a field the viewer cannot see fail with the platform's own words.
        if (!Gift__c.Opportunity_Id__c.getDescribe().isAccessible()) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_NoLinkAccess);
        }
        if (!canReadOpportunities()) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_NoOpportunityRead);
        }
        String opportunityObject = OpportunityMirrorService.opportunityType()
            .getDescribe()
            .getName();
        // Bound by name in the selector's gift query, as are the dates and statuses.
        Integer cap = maxRecords + 1;
        // Each gift can cost a second row for its Opportunity, each won one a check for a gift.
        if (4 * cap > Limits.getLimitQueryRows() - Limits.getQueryRows()) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_ErrorTooMany);
        }
        List<SObject> won = OpportunityMirrorSelector.wonInRange(
            opportunityObject,
            fromDate,
            toDate,
            cap
        );
        if (won.size() > maxRecords) {
            throw new ReconciliationException(Label.Mirror_OpportunityMirror_ErrorTooMany);
        }

        Comparison result = new Comparison();
        Map<String, SObject> wonById = new Map<String, SObject>();
        for (SObject opportunity : won) {
            wonById.put(String.valueOf(opportunity.Id), opportunity);
            result.opportunityCount++;
            result.opportunityTotal += amountOf(opportunity.get('Amount'));
        }

        Set<String> statuses = OpportunityMirrorService.IN_TOTALS;
        Set<String> named = new Set<String>();
        // A gift in the range may name an Opportunity closed outside it, or one not won.
        List<Gift__c> elsewhere = new List<Gift__c>();
        Set<Id> elsewhereIds = new Set<Id>();
        // Access mode: user mode, stated as WITH USER_MODE in the selector's query text.
        for (List<Gift__c> chunk : Database.query(OpportunityMirrorSelector.GIFTS_IN_RANGE_QUERY)) {
            if (result.giftCount + chunk.size() > maxRecords) {
                throw new ReconciliationException(Label.Mirror_OpportunityMirror_ErrorTooMany);
            }
            for (Gift__c gift : chunk) {
                result.giftCount++;
                result.giftTotal += amountOf(gift.Amount__c);
                if (gift.Opportunity_Id__c == null) {
                    result.add(pair(gift, null, Label.Mirror_OpportunityMirror_DiffNoOpportunity));
                } else if (wonById.containsKey(gift.Opportunity_Id__c)) {
                    named.add(gift.Opportunity_Id__c);
                    compareLinked(result, gift, wonById.get(gift.Opportunity_Id__c));
                } else {
                    elsewhere.add(gift);
                    elsewhereIds.add(Id.valueOf(gift.Opportunity_Id__c));
                }
            }
        }
        Map<Id, SObject> otherById = OpportunityMirrorSelector.opportunitiesById(
            opportunityObject,
            new List<String>{ 'Id', 'Name', 'Amount', 'CloseDate', 'IsWon' },
            elsewhereIds
        );
        for (Gift__c gift : elsewhere) {
            compareLinked(result, gift, otherById.get(Id.valueOf(gift.Opportunity_Id__c)));
        }

        // A won Opportunity is without a gift only when no gift anywhere names it.
        Set<String> unnamed = new Set<String>(wonById.keySet());
        unnamed.removeAll(named);
        unnamed.removeAll(OpportunityMirrorSelector.linkedOpportunityIds(unnamed));
        for (SObject opportunity : wonById.values()) {
            if (unnamed.contains(String.valueOf(opportunity.Id))) {
                result.add(pair(null, opportunity, Label.Mirror_OpportunityMirror_DiffNoGift));
            }
        }
        return result;
    }

    /** Lists a linked gift whose Opportunity is gone or differs from it. */
    private static void compareLinked(Comparison result, Gift__c gift, SObject opportunity) {
        if (opportunity == null) {
            Difference missing = pair(gift, null, Label.Mirror_OpportunityMirror_DiffMissing);
            missing.opportunityId = gift.Opportunity_Id__c;
            result.add(missing);
            return;
        }
        List<String> reasons = new List<String>();
        if (amountOf(gift.Amount__c) != amountOf(opportunity.get('Amount'))) {
            reasons.add(Label.Mirror_OpportunityMirror_DiffAmount);
        }
        if (gift.Gift_Date__c != (Date) opportunity.get('CloseDate')) {
            reasons.add(Label.Mirror_OpportunityMirror_DiffDate);
        }
        if (opportunity.get('IsWon') != true) {
            reasons.add(Label.Mirror_OpportunityMirror_DiffNotWon);
        }
        if (!reasons.isEmpty()) {
            result.add(pair(gift, opportunity, String.join(reasons, ', ')));
        }
    }

    /** Whether the viewer can read Opportunities and each field the comparison shows. */
    private static Boolean canReadOpportunities() {
        Schema.DescribeSObjectResult opportunity = OpportunityMirrorService.opportunityType()
            .getDescribe();
        if (!opportunity.isAccessible()) {
            return false;
        }
        Map<String, Schema.SObjectField> fields = opportunity.fields.getMap();
        for (String name : new List<String>{ 'name', 'amount', 'closedate' }) {
            if (!fields.get(name).getDescribe().isAccessible()) {
                return false;
            }
        }
        return true;
    }

    private static Difference pair(Gift__c gift, SObject opportunity, String reason) {
        Difference difference = new Difference();
        difference.reason = reason;
        if (gift != null) {
            difference.giftId = gift.Id;
            difference.giftName = gift.Name;
            difference.giftAmount = gift.Amount__c;
            difference.giftDate = gift.Gift_Date__c;
        }
        if (opportunity != null) {
            difference.opportunityId = String.valueOf(opportunity.Id);
            difference.opportunityName = (String) opportunity.get('Name');
            difference.opportunityAmount = (Decimal) opportunity.get('Amount');
            difference.closeDate = (Date) opportunity.get('CloseDate');
        }
        return difference;
    }

    private static Decimal amountOf(Object amount) {
        return amount == null ? 0 : (Decimal) amount;
    }
}
