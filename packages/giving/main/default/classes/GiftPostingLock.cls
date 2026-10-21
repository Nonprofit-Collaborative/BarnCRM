/**
 * The posting and closed period lock (G-20, canonical model R-G13, R-G14, R-GA5, ADR-0053).
 *
 * A gift is in the books when the accounting export would write it: Status Received, Refunded
 * or Written off, and Type not In-kind (ADR-0051, ADR-0022). It is locked when it is in the books
 * and either posted to accounting or dated on or before Books Closed Through. A locked gift keeps
 * every value the export writes for it, stays in the books, keeps its allocations and is not
 * deleted; and nothing enters the books in a closed period.
 *
 * The rules run from `GiftPostingLockHandler` and `GiftAllocationPostingLockHandler`, whose
 * registry rows carry Always Runs, so no switch and no pause reaches them (ADR-0024). The one way
 * past is `Override_Posting_Lock`, granted to nobody by the package, and every save it lets
 * through is written to the Error Log at Warning.
 */
public with sharing class GiftPostingLock {
    public static final String OVERRIDE_PERMISSION = 'Override_Posting_Lock';

    /** The statuses the accounting export and the money rollups read (ADR-0022, ADR-0051). */
    public static final Set<String> BOOK_STATUSES = new Set<String>{
        'Received',
        'Refunded',
        'Written off'
    };
    public static final String TYPE_IN_KIND = 'In-kind';

    private static final String LOG_CONTEXT = 'Posting lock override';

    /** Every value the accounting export writes for a gift (R-G14). */
    private static final List<Schema.SObjectField> LOCKED_FIELDS = new List<Schema.SObjectField>{
        Gift__c.Gift_Date__c,
        Gift__c.Amount__c,
        Gift__c.Donor_Contact__c,
        Gift__c.Donor_Account__c,
        Gift__c.Type__c,
        Gift__c.Payment_Reference__c,
        Gift__c.Original_Gift__c
    };

    private static final List<Schema.SObjectField> POSTING_FIELDS = new List<Schema.SObjectField>{
        Gift__c.Accounting_Posted_At__c,
        Gift__c.Accounting_Posted_By__c
    };

    private static final List<Schema.SObjectField> ALLOCATION_FIELDS = new List<Schema.SObjectField>{
        Gift_Allocation__c.Fund__c,
        Gift_Allocation__c.Amount__c,
        Gift_Allocation__c.Percent__c
    };

    /**
     * The gifts whose posting fields `GiftPostingService` is writing right now. A set of Ids
     * rather than a flag, for the reason `GiftService.giftsBeingRenumbered` gives: a flag would
     * open the fields for every gift saved in the transaction.
     */
    @TestVisible
    private static Set<Id> giftsBeingPosted = new Set<Id>();

    /** Read once per transaction: the answer cannot change inside one. */
    @TestVisible
    private static Boolean overrideHeld = null;

    // -------------------------------------------------------------------------------------
    // What is locked
    // -------------------------------------------------------------------------------------

    /** The last day of the latest closed period, or null when no period is closed. */
    public static Date closedThrough() {
        return Giving_Settings__c.getOrgDefaults().Books_Closed_Through__c;
    }

    /** Whether the export would write this gift. An empty status is the field's default. */
    public static Boolean isInBooks(Gift__c gift) {
        String status = String.isBlank(gift.Status__c) ? 'Received' : gift.Status__c;
        return BOOK_STATUSES.contains(status) && gift.Type__c != TYPE_IN_KIND;
    }

    public static Boolean isPosted(Gift__c gift) {
        return gift.Accounting_Posted_At__c != null;
    }

    /** An empty date is today once the gift rules fill it in, and today is never closed. */
    public static Boolean isInClosedPeriod(Date giftDate, Date closed) {
        return closed != null && giftDate != null && giftDate <= closed;
    }

    public static Boolean isLocked(Gift__c gift, Date closed) {
        return isInBooks(gift) && (isPosted(gift) || isInClosedPeriod(gift.Gift_Date__c, closed));
    }

    // -------------------------------------------------------------------------------------
    // Gifts
    // -------------------------------------------------------------------------------------

    /** Before insert: nothing is created in the books in a closed period, or already posted. */
    public static void enforceOnInsert(List<Gift__c> gifts) {
        if (canOverride()) {
            return;
        }
        Date closed = closedThrough();
        for (Gift__c gift : gifts) {
            String refusal = insertRefusal(gift, closed);
            if (refusal != null) {
                gift.addError(refusal);
            }
        }
    }

    /**
     * After insert and after undelete: records what the override let in, now that the gifts have
     * Ids to name. An undelete is refused here too, because it is the only moment it can be: a
     * restored gift is a gift entering the books again.
     */
    public static void enforceOnRestore(List<Gift__c> gifts, Boolean isUndelete) {
        Date closed = closedThrough();
        Boolean overridden = canOverride();
        List<String> overrides = new List<String>();
        for (Gift__c gift : gifts) {
            String refusal = insertRefusal(gift, closed);
            if (refusal == null) {
                continue;
            }
            if (overridden) {
                overrides.add(
                    describe(
                        gift.Id,
                        isUndelete
                            ? Label.Giving_Posting_OverrideRestored
                            : Label.Giving_Posting_OverrideCreated
                    )
                );
            } else if (isUndelete) {
                gift.addError(refusal);
            }
        }
        ErrorLogger.logMessages(overrides, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    private static String insertRefusal(Gift__c gift, Date closed) {
        if (postingFieldsSet(gift)) {
            return Label.Giving_Posting_FieldsWrittenByPosting;
        }
        if (isInBooks(gift) && isInClosedPeriod(gift.Gift_Date__c, closed)) {
            return String.format(
                Label.Giving_Posting_ClosedPeriodNewGift,
                new List<String>{ closed.format() }
            );
        }
        return null;
    }

    /** Before update: a locked gift keeps its values, and no gift enters a closed period. */
    public static void enforceOnUpdate(List<Gift__c> gifts, Map<Id, Gift__c> oldGifts) {
        Date closed = closedThrough();
        Boolean overridden = canOverride();
        List<String> overrides = new List<String>();
        for (Gift__c gift : gifts) {
            Gift__c previous = oldGifts.get(gift.Id);
            if (previous == null) {
                continue;
            }
            List<String> changes = new List<String>();
            String refusal = null;
            if (!giftsBeingPosted.contains(gift.Id)) {
                List<String> posting = changesTo(POSTING_FIELDS, previous, gift);
                if (!posting.isEmpty()) {
                    changes.addAll(posting);
                    refusal = Label.Giving_Posting_FieldsWrittenByPosting;
                }
            }
            if (isLocked(previous, closed)) {
                List<String> moved = changesTo(LOCKED_FIELDS, previous, gift);
                if (!isInBooks(gift)) {
                    moved.add(
                        GiftService.change(Gift__c.Status__c, previous.Status__c, gift.Status__c)
                    );
                }
                if (!moved.isEmpty()) {
                    changes.addAll(moved);
                    refusal = lockedMessage(previous, closed);
                }
            } else if (isInBooks(gift) && isInClosedPeriod(gift.Gift_Date__c, closed)) {
                changes.add(
                    String.format(
                        Label.Giving_Posting_OverrideEnteredBooks,
                        new List<String>{ String.valueOf(gift.Gift_Date__c) }
                    )
                );
                refusal = String.format(
                    Label.Giving_Posting_ClosedPeriodNewGift,
                    new List<String>{ closed.format() }
                );
            }
            if (refusal == null) {
                continue;
            }
            if (overridden) {
                overrides.add(describe(gift.Id, String.join(changes, ', ')));
            } else {
                gift.addError(refusal);
            }
        }
        ErrorLogger.logMessages(overrides, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    /**
     * Before delete: a locked gift stays, and so does a gift a locked gift names as its original
     * (R-G15), because the platform would clear Original Gift on the locked gift without running
     * this lock.
     */
    public static void enforceOnDelete(List<Gift__c> gifts) {
        Date closed = closedThrough();
        Boolean overridden = canOverride();
        Set<Id> originals = namedByLockedGifts(new Map<Id, Gift__c>(gifts).keySet(), closed);
        List<String> overrides = new List<String>();
        for (Gift__c gift : gifts) {
            String refusal = isLocked(gift, closed)
                ? lockedMessage(gift, closed)
                : originals.contains(gift.Id) ? Label.Giving_Posting_OriginalLocked : null;
            if (refusal == null) {
                continue;
            }
            if (overridden) {
                overrides.add(describe(gift.Id, Label.Giving_Posting_OverrideDeleted));
            } else {
                gift.addError(refusal);
            }
        }
        ErrorLogger.logMessages(overrides, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    // -------------------------------------------------------------------------------------
    // Donors a locked gift names (R-G15)
    // -------------------------------------------------------------------------------------

    /** The people and organizations being deleted that a locked gift names, from before delete. */
    private static Set<Id> donorsNamed = new Set<Id>();

    /**
     * Before delete of a Contact or Account: notes which of them a locked gift names. Nothing is
     * refused yet, because a merge deletes the losing record too and only after delete says so.
     * Each delete reads the books afresh: a record refused earlier in the transaction is not
     * refused again once nothing locked names it.
     */
    public static void noteDonorsNamed(List<SObject> records) {
        Set<Id> recordIds = new Map<Id, SObject>(records).keySet();
        donorsNamed.removeAll(recordIds);
        donorsNamed.addAll(namedByLockedGifts(recordIds, closedThrough()));
    }

    /**
     * After delete: refuses deleting a noted record that was not merged. A merged record's gifts
     * moved to the surviving record (MasterRecordId is set), so the books still name a donor.
     */
    public static void enforceOnDonorDelete(List<SObject> records) {
        Boolean overridden = canOverride();
        List<String> overrides = new List<String>();
        for (SObject record : records) {
            if (!donorsNamed.contains(record.Id) || record.get('MasterRecordId') != null) {
                continue;
            }
            if (overridden) {
                overrides.add(describe(record.Id, Label.Giving_Posting_OverrideDonorDeleted));
            } else {
                record.addError(Label.Giving_Posting_DonorLocked);
            }
        }
        ErrorLogger.logMessages(overrides, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    /**
     * Which of these records a locked gift names as donor or as its original. A person's
     * household Account counts too: deleting it deletes the person with no Contact trigger, and
     * would blank the gift's Donor Contact.
     */
    private static Set<Id> namedByLockedGifts(Set<Id> recordIds, Date closed) {
        Set<Id> named = new Set<Id>();
        for (Gift__c gift : GiftPostingSelector.selectPossiblyLockedNaming(recordIds, closed)) {
            if (!isLocked(gift, closed)) {
                continue;
            }
            for (
                Id reference : new List<Id>{
                    gift.Donor_Contact__c,
                    gift.Donor_Contact__r?.AccountId,
                    gift.Donor_Account__c,
                    gift.Original_Gift__c
                }
            ) {
                if (reference != null && recordIds.contains(reference)) {
                    named.add(reference);
                }
            }
        }
        return named;
    }

    // -------------------------------------------------------------------------------------
    // Allocations (R-GA5)
    // -------------------------------------------------------------------------------------

    /**
     * An allocation of a locked gift is not inserted, changed in fund or amount, or deleted.
     * `oldAllocations` is null on insert and on delete; `records` is the new rows on insert and
     * update and the old rows on delete. `action` is the translated Error Log phrase for what
     * happened to the allocation, used when an override lets it through.
     */
    public static void enforceOnAllocations(
        List<Gift_Allocation__c> records,
        Map<Id, Gift_Allocation__c> oldAllocations,
        String action
    ) {
        Set<Id> giftIds = new Set<Id>();
        for (Gift_Allocation__c allocation : records) {
            if (allocation.Gift__c != null) {
                giftIds.add(allocation.Gift__c);
            }
        }
        if (giftIds.isEmpty()) {
            return;
        }
        Date closed = closedThrough();
        Map<Id, Gift__c> locked = new Map<Id, Gift__c>();
        for (Gift__c gift : GiftPostingSelector.selectLockStateByIds(giftIds)) {
            if (isLocked(gift, closed)) {
                locked.put(gift.Id, gift);
            }
        }
        if (locked.isEmpty()) {
            return;
        }
        Boolean overridden = canOverride();
        List<String> overrides = new List<String>();
        for (Gift_Allocation__c allocation : records) {
            if (!locked.containsKey(allocation.Gift__c)) {
                continue;
            }
            Gift_Allocation__c previous = oldAllocations == null
                ? null
                : oldAllocations.get(allocation.Id);
            if (previous != null && changesTo(ALLOCATION_FIELDS, previous, allocation).isEmpty()) {
                continue;
            }
            if (overridden) {
                overrides.add(describe(allocation.Gift__c, action));
            } else {
                allocation.addError(Label.Giving_Posting_AllocationLocked);
            }
        }
        ErrorLogger.logMessages(overrides, LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
    }

    // -------------------------------------------------------------------------------------
    // The posting door and the override
    // -------------------------------------------------------------------------------------

    /**
     * Runs `work` with the posting fields of these gifts open, and closes them again whatever
     * happens. The previous set is restored rather than emptied, so a nested call leaves the
     * outer one intact. Only `GiftPostingService` calls it.
     */
    public static void whilePosting(Set<Id> giftIds, Runnable work) {
        Set<Id> wasOpen = giftsBeingPosted;
        try {
            Set<Id> open = new Set<Id>(wasOpen);
            open.addAll(giftIds);
            giftsBeingPosted = open;
            work.run();
        } finally {
            giftsBeingPosted = wasOpen;
        }
    }

    /** The work `whilePosting` runs. */
    public interface Runnable {
        void run();
    }

    public static Boolean canOverride() {
        if (overrideHeld == null) {
            overrideHeld = FeatureManagement.checkPermission(OVERRIDE_PERMISSION);
        }
        return overrideHeld;
    }

    // -------------------------------------------------------------------------------------
    // Wording
    // -------------------------------------------------------------------------------------

    private static String lockedMessage(Gift__c gift, Date closed) {
        if (isPosted(gift)) {
            return Label.Giving_Posting_PostedGiftLocked;
        }
        return String.format(
            Label.Giving_Posting_ClosedGiftLocked,
            new List<String>{ closed.format() }
        );
    }

    private static Boolean postingFieldsSet(Gift__c gift) {
        return gift.Accounting_Posted_At__c != null || gift.Accounting_Posted_By__c != null;
    }

    /**
     * Each field that differs, with what it was and what it became. Text is compared exactly:
     * Apex compares strings without regard to case, and a reference whose case changed is a
     * different reference in the books.
     */
    private static List<String> changesTo(
        List<Schema.SObjectField> fields,
        SObject previous,
        SObject current
    ) {
        List<String> changes = new List<String>();
        for (Schema.SObjectField field : fields) {
            Object before = previous.get(field);
            Object after = current.get(field);
            if (differs(before, after)) {
                changes.add(GiftService.change(field, before, after));
            }
        }
        return changes;
    }

    private static Boolean differs(Object before, Object after) {
        if (before == null || after == null) {
            return before != after;
        }
        if (before instanceof String) {
            return !((String) before).equals(String.valueOf(after));
        }
        // Numbers compare by value, so 250 and 250.00 are the same amount.
        return before != after;
    }

    private static String describe(Id giftId, String what) {
        return String.format(
            Label.Giving_Posting_OverrideLogged,
            new List<String>{ String.valueOf(giftId), what }
        );
    }
}
