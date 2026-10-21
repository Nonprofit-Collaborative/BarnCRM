/**
 * The Lightning-facing surface for a gift: what a gift summary panel needs to show, and the
 * two actions that record money going back. Every method validates its input and either
 * returns a typed result or throws a message a screen can show a person (plan Section 7.2).
 */
public with sharing class GiftController {
    /**
     * Records a refund of part or all of a gift and returns the identifier of the negative gift
     * that documents it.
     */
    @AuraEnabled
    public static Id refund(Id giftId, Decimal amount, String reason) {
        try {
            return GiftService.refund(giftId, amount, reason);
        } catch (Exception refundError) {
            ErrorLogger.log(refundError, 'GiftController.refund', giftId);
            throw asUserError(refundError);
        }
    }

    /**
     * Writes off what is left of a gift and returns the identifier of the negative gift that
     * documents it.
     */
    @AuraEnabled
    public static Id writeOff(Id giftId, String reason) {
        try {
            return GiftService.writeOff(giftId, reason);
        } catch (Exception writeOffError) {
            ErrorLogger.log(writeOffError, 'GiftController.writeOff', giftId);
            throw asUserError(writeOffError);
        }
    }

    /**
     * Everything a gift panel shows in one call: the gift, its allocations, what is allocated,
     * what has gone back, and what is left.
     */
    @AuraEnabled(cacheable=true)
    public static GiftSummary getGiftSummary(Id giftId) {
        try {
            if (giftId == null) {
                throw new GiftService.GiftServiceException(Label.Giving_Gift_OriginalNotFound);
            }
            List<Gift__c> gifts = GiftSelector.selectWithAllocations(new Set<Id>{ giftId });
            if (gifts.isEmpty()) {
                throw new GiftService.GiftServiceException(Label.Giving_Gift_OriginalNotFound);
            }
            return new GiftSummary(gifts[0]);
        } catch (Exception summaryError) {
            // No logging here on purpose: this method is cacheable, and the Error Log is a
            // record insert, which the platform refuses inside a cacheable call. The screen
            // still gets a sentence it can show, and the actions below do log.
            throw asUserError(summaryError);
        }
    }

    private static AuraHandledException asUserError(Exception cause) {
        return GivingErrors.userError(cause, Label.Giving_Gift_UnexpectedError);
    }

    /**
     * A gift and the numbers a screen would otherwise have to work out for itself.
     */
    public class GiftSummary {
        @AuraEnabled
        public Gift__c gift;
        @AuraEnabled
        public List<Gift_Allocation__c> allocations;
        @AuraEnabled
        public Decimal allocatedAmount;
        @AuraEnabled
        public Decimal reversedAmount;
        @AuraEnabled
        public Decimal remainingAmount;
        @AuraEnabled
        public Boolean fullyReversed;

        public GiftSummary(Gift__c source) {
            this.gift = source;
            this.allocations = source.Gift_Allocations__r == null
                ? new List<Gift_Allocation__c>()
                : source.Gift_Allocations__r;
            this.allocatedAmount = 0;
            for (Gift_Allocation__c allocation : this.allocations) {
                this.allocatedAmount += allocation.Amount__c == null ? 0 : allocation.Amount__c;
            }
            this.remainingAmount = source.Amount__c == null
                ? 0
                : GiftService.remainingAmount(source);
            this.reversedAmount =
                (source.Amount__c == null ? 0 : source.Amount__c) - this.remainingAmount;
            this.fullyReversed =
                source.Amount__c != null &&
                source.Amount__c > 0 &&
                this.remainingAmount <= 0;
        }
    }
}
