/**
 * Marks gifts posted to accounting and unposts them (G-20, canonical model R-G13, ADR-0053).
 *
 * The only code that writes `Accounting_Posted_At__c` and `Accounting_Posted_By__c`. Both fields
 * are read only in every packaged permission set, and the posting lock refuses any change to
 * them that does not come through `GiftPostingLock.whilePosting`, so "posted" always means this
 * class recorded who and when.
 *
 * `@NamespaceAccessible` because Mirror's Accounting Export page marks the gifts it exported
 * (Mirror depends on Giving, never the reverse).
 */
@NamespaceAccessible
public with sharing class GiftPostingService {
    @NamespaceAccessible
    public static final String POST_PERMISSION = 'Post_Gifts';

    /** How many gifts one click marks posted: a synchronous save, well inside the row limits. */
    @NamespaceAccessible
    public static final Integer MAX_GIFTS_PER_MARK = 5000;

    private static final String OBJECT_NAME = 'Gift__c';
    private static final String UNPOST_LOG_CONTEXT = 'Gift unposted';

    @TestVisible
    private static Boolean postPermission = null;

    @NamespaceAccessible
    public class GiftPostingException extends Exception {
    }

    @NamespaceAccessible
    public static Boolean canPost() {
        if (postPermission == null) {
            postPermission = FeatureManagement.checkPermission(POST_PERMISSION);
        }
        return postPermission;
    }

    /**
     * Marks these gifts posted, now, by the running user, and returns how many it marked. Only
     * gifts in the books and not yet posted are marked: marking twice changes nothing, and a
     * Pending or in-kind gift is in no export file. The gifts are read in user mode, so a gift
     * the user cannot see is not marked.
     */
    @NamespaceAccessible
    public static Integer markPosted(Set<Id> giftIds) {
        requirePermission();
        if (giftIds == null || giftIds.isEmpty()) {
            return 0;
        }
        if (giftIds.size() > MAX_GIFTS_PER_MARK) {
            throw new GiftPostingException(
                String.format(
                    Label.Giving_Posting_TooMany,
                    new List<String>{ String.valueOf(MAX_GIFTS_PER_MARK) }
                )
            );
        }
        Datetime now = Datetime.now();
        Id userId = UserInfo.getUserId();
        List<Gift__c> marks = new List<Gift__c>();
        for (Gift__c gift : GiftPostingSelector.selectForPosting(giftIds)) {
            if (GiftPostingLock.isInBooks(gift) && !GiftPostingLock.isPosted(gift)) {
                marks.add(
                    new Gift__c(
                        Id = gift.Id,
                        Accounting_Posted_At__c = now,
                        Accounting_Posted_By__c = userId
                    )
                );
            }
        }
        save(marks);
        return marks.size();
    }

    /**
     * Clears the posting mark on one gift, for a stated reason, and writes the reason to the
     * Error Log at Warning so the bookkeeper's change is on record. A gift dated in a closed
     * period stays locked after it is unposted.
     */
    @NamespaceAccessible
    public static void unpost(Id giftId, String reason) {
        requirePermission();
        if (String.isBlank(reason)) {
            throw new GiftPostingException(Label.Giving_Posting_ReasonRequired);
        }
        List<Gift__c> found = giftId == null
            ? new List<Gift__c>()
            : GiftPostingSelector.selectForPosting(new Set<Id>{ giftId });
        if (found.isEmpty() || !GiftPostingLock.isPosted(found[0])) {
            throw new GiftPostingException(Label.Giving_Posting_NotPosted);
        }
        save(
            new List<Gift__c>{
                new Gift__c(
                    Id = giftId,
                    Accounting_Posted_At__c = null,
                    Accounting_Posted_By__c = null
                )
            }
        );
        ErrorLogger.logMessages(
            new List<String>{
                String.format(
                    Label.Giving_Posting_UnpostLogged,
                    new List<String>{
                        found[0].Name,
                        reason.trim(),
                        found[0].Accounting_Posted_By__r?.Name,
                        found[0].Accounting_Posted_At__c.format()
                    }
                )
            },
            UNPOST_LOG_CONTEXT,
            ErrorLogger.SEVERITY_WARNING
        );
    }

    private static void requirePermission() {
        if (!canPost()) {
            throw new GiftPostingException(Label.Giving_Posting_NoPermission);
        }
    }

    /**
     * Saves the posting fields through the posting door. The switchable Gift automations are
     * bypassed for this save: none of them reads the posting fields, and running them for up to
     * 5,000 unchanged gifts is only cost. The Always Runs rules (the posting and receipt locks)
     * still run, as they do on every save.
     */
    private static void save(List<Gift__c> gifts) {
        if (gifts.isEmpty()) {
            return;
        }
        Set<Id> ids = new Map<Id, Gift__c>(gifts).keySet();
        List<String> bypassed = new List<String>();
        for (String name : GiftPostingSelector.selectSwitchableAutomationNames(OBJECT_NAME)) {
            // One the caller already bypassed stays bypassed after this save.
            if (!AutomationControl.isBypassed(name)) {
                AutomationControl.bypass(name);
                bypassed.add(name);
            }
        }
        try {
            GiftPostingLock.whilePosting(ids, new Write(gifts));
        } finally {
            for (String name : bypassed) {
                AutomationControl.clearBypass(name);
            }
        }
    }

    private class Write implements GiftPostingLock.Runnable {
        private List<Gift__c> gifts;

        Write(List<Gift__c> gifts) {
            this.gifts = gifts;
        }

        public void run() {
            GiftPostingWriter.save(gifts);
        }
    }
}
