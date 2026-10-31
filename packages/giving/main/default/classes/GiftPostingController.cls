/**
 * The Posting card on a gift's page (G-20, R-G13, ADR-0053).
 *
 * It answers what a person looking at a gift wants to know before they try to change it: is it
 * posted to accounting, by whom and when, and is it dated in a closed period. It carries the one
 * place a gift is unposted, for someone holding Post Gifts, with the reason box the service needs.
 */
public with sharing class GiftPostingController {
    private static final String CONTEXT = 'Gift posting card';

    /** The card, in one round trip. */
    public class PostingState {
        @AuraEnabled
        public Boolean inBooks;
        @AuraEnabled
        public Boolean posted;
        @AuraEnabled
        public Datetime postedAt;
        @AuraEnabled
        public String postedBy;
        @AuraEnabled
        public Boolean inClosedPeriod;
        @AuraEnabled
        public Date closedThrough;
        @AuraEnabled
        public Boolean canUnpost;
    }

    @AuraEnabled
    public static PostingState getState(Id giftId) {
        try {
            return stateOf(giftId);
        } catch (Exception caught) {
            throw asUserError(caught, CONTEXT);
        }
    }

    @AuraEnabled
    public static PostingState unpost(Id giftId, String reason) {
        try {
            GiftPostingService.unpost(giftId, reason);
            return stateOf(giftId);
        } catch (Exception caught) {
            throw asUserError(caught, 'Unpost a gift');
        }
    }

    private static PostingState stateOf(Id giftId) {
        PostingState state = new PostingState();
        List<Gift__c> found = giftId == null
            ? new List<Gift__c>()
            : GiftPostingSelector.selectForPosting(new Set<Id>{ giftId });
        if (found.isEmpty()) {
            throw new GiftPostingService.GiftPostingException(Label.Giving_Posting_NotPosted);
        }
        Gift__c gift = found[0];
        state.inBooks = GiftPostingLock.isInBooks(gift);
        state.posted = GiftPostingLock.isPosted(gift);
        state.postedAt = gift.Accounting_Posted_At__c;
        state.postedBy = gift.Accounting_Posted_By__r?.Name;
        state.closedThrough = GiftPostingLock.closedThrough();
        state.inClosedPeriod =
            state.inBooks &&
            GiftPostingLock.isInClosedPeriod(gift.Gift_Date__c, state.closedThrough);
        state.canUnpost = state.posted && GiftPostingService.canPost();
        return state;
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof GiftPostingService.GiftPostingException,
            context,
            Label.Giving_Periods_UnexpectedError
        );
    }
}
