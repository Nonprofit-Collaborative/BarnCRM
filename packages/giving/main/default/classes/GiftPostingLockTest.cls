/**
 * The posting and closed period lock (G-20, R-G14, R-GA5, ADR-0053), from both sides.
 *
 * Jen has put last month into the books. David cannot change what she holds, add to it, or take
 * from it, however he tries, and a pause of all automation does not help him. He can still
 * refund, thank and receipt. The one afternoon Maria holds Override Posting Lock, she can make an
 * auditor's correction, and BarnCRM writes down what she did.
 */
@IsTest
private class GiftPostingLockTest {
    private static final String OVERRIDE_PERMISSION = 'Override_Posting_Lock';

    private static Date lastClosedDay() {
        return Date.today().toStartOfMonth().addDays(-1);
    }

    private static Date inClosedPeriod() {
        return lastClosedDay().addDays(-3);
    }

    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        Contact ana = GivingTestDataFactory.insertHouseholdContact(
            'The Nolan Family',
            'Ana',
            'Nolan'
        );
        GivingTestDataFactory.insertHouseholdContact('The Okafor Family', 'Ben', 'Okafor');
        Gift__c closedMonth = GivingTestDataFactory.buildGift(ana.Id, 250);
        closedMonth.Gift_Date__c = inClosedPeriod();
        closedMonth.Payment_Reference__c = 'CHK-1001';
        Gift__c pending = GivingTestDataFactory.buildGift(ana.Id, 75);
        pending.Gift_Date__c = inClosedPeriod();
        pending.Status__c = 'Pending';
        Gift__c thisMonth = GivingTestDataFactory.buildGift(ana.Id, 40);
        thisMonth.Gift_Date__c = Date.today();
        insert new List<Gift__c>{ closedMonth, pending, thisMonth };
    }

    private static Gift__c giftOf(Decimal amount) {
        return [
            SELECT
                Id,
                Amount__c,
                Gift_Date__c,
                Status__c,
                Donor_Contact__c,
                Accounting_Posted_At__c,
                (SELECT Id, Fund__c, Amount__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE Amount__c = :amount
            LIMIT 1
        ];
    }

    private static Contact ben() {
        return [SELECT Id FROM Contact WHERE LastName = 'Okafor' LIMIT 1];
    }

    private static String refusalOf(SObject record) {
        try {
            update record;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    private static String deleteRefusal(SObject record) {
        try {
            delete record;
            return null;
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
    }

    /** Marks a gift posted the way `GiftPostingService` does: through the posting door. */
    private class MarkPosted implements GiftPostingLock.Runnable {
        private Id giftId;
        MarkPosted(Id giftId) {
            this.giftId = giftId;
        }
        public void run() {
            update new Gift__c(
                Id = giftId,
                Accounting_Posted_At__c = System.now(),
                Accounting_Posted_By__c = UserInfo.getUserId()
            );
        }
    }

    private static void markPosted(Id giftId) {
        GiftPostingLock.whilePosting(new Set<Id>{ giftId }, new MarkPosted(giftId));
    }

    private static String closedGiftMessage() {
        return String.format(
            Label.Giving_Posting_ClosedGiftLocked,
            new List<String>{ lastClosedDay().format() }
        );
    }

    // -------------------------------------------------------------------------------------
    // Closed periods
    // -------------------------------------------------------------------------------------

    @IsTest
    static void nothingIsAddedToAClosedPeriodButTodayAndThingsOutsideTheBooksAre() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Contact ana = [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
        Gift__c late = GivingTestDataFactory.buildGift(ana.Id, 60);
        late.Gift_Date__c = inClosedPeriod();
        Gift__c today = GivingTestDataFactory.buildGift(ana.Id, 61);
        today.Gift_Date__c = Date.today();
        Gift__c pledged = GivingTestDataFactory.buildGift(ana.Id, 62);
        pledged.Gift_Date__c = inClosedPeriod();
        pledged.Status__c = 'Pending';

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(
            new List<Gift__c>{ late, today, pledged },
            false
        );
        Test.stopTest();

        Assert.isFalse(results[0].isSuccess(), 'A gift dated in a closed month is refused.');
        Assert.areEqual(
            String.format(
                Label.Giving_Posting_ClosedPeriodNewGift,
                new List<String>{ lastClosedDay().format() }
            ),
            results[0].getErrors()[0].getMessage(),
            'In words that say what to do.'
        );
        Assert.isTrue(results[1].isSuccess(), 'Today is always open.');
        Assert.isTrue(
            results[2].isSuccess(),
            'A Pending gift is in no export file, so it may be dated in a closed month.'
        );
    }

    @IsTest
    static void everyValueTheBooksHoldIsLockedAndTheRestIsNot() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c gift = giftOf(250);
        List<Gift__c> attempts = new List<Gift__c>{
            new Gift__c(Id = gift.Id, Amount__c = 300),
            new Gift__c(Id = gift.Id, Gift_Date__c = Date.today()),
            new Gift__c(Id = gift.Id, Donor_Contact__c = ben().Id),
            new Gift__c(Id = gift.Id, Type__c = 'Cash'),
            new Gift__c(Id = gift.Id, Payment_Reference__c = 'chk-1001'),
            new Gift__c(Id = gift.Id, Status__c = 'Pending')
        };

        Test.startTest();
        List<String> refusals = new List<String>();
        for (Gift__c attempt : attempts) {
            refusals.add(refusalOf(attempt));
        }
        String acknowledged = refusalOf(
            new Gift__c(Id = gift.Id, Acknowledgment_Status__c = 'Acknowledged')
        );
        Test.stopTest();

        for (Integer index = 0; index < refusals.size(); index++) {
            Assert.areEqual(
                closedGiftMessage(),
                refusals[index],
                'Attempt ' + index + ' changes something the books hold, so it is refused.'
            );
        }
        Assert.isNull(acknowledged, 'Thanking the donor goes on after the books close.');
        Assert.areEqual(250, giftOf(250).Amount__c, 'The amount is what the books hold.');
    }

    @IsTest
    static void aLockedGiftCannotBeDeletedButAPendingOneInTheSameMonthCan() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String locked = deleteRefusal(new Gift__c(Id = giftOf(250).Id));
        String pending = deleteRefusal(new Gift__c(Id = giftOf(75).Id));
        Test.stopTest();

        Assert.areEqual(closedGiftMessage(), locked, 'The gift in the books stays.');
        Assert.isNull(
            pending,
            'The unpaid pledge payment is not in the books, so deleting it changes nothing Jen holds.'
        );
    }

    @IsTest
    static void aGiftCannotBeMovedIntoAClosedPeriodOrBroughtIntoTheBooksThere() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String movedBack = refusalOf(
            new Gift__c(Id = giftOf(40).Id, Gift_Date__c = inClosedPeriod())
        );
        String received = refusalOf(new Gift__c(Id = giftOf(75).Id, Status__c = 'Received'));
        Test.stopTest();

        String expected = String.format(
            Label.Giving_Posting_ClosedPeriodNewGift,
            new List<String>{ lastClosedDay().format() }
        );
        Assert.areEqual(
            expected,
            movedBack,
            'Dating a gift back into a closed month is adding it.'
        );
        Assert.areEqual(expected, received, 'So is a Pending gift there becoming Received.');
    }

    @IsTest
    static void aGiftDeletedBeforeTheCloseIsNotRestoredIntoIt() {
        Gift__c gift = giftOf(250);
        delete gift;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        Database.UndeleteResult result = Database.undelete(gift.Id, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'A restored gift would enter the closed books.');
    }

    @IsTest
    static void theFundsOfALockedGiftAreLocked() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c gift = giftOf(250);
        Gift_Allocation__c existing = gift.Gift_Allocations__r[0];
        Fund__c building = GivingTestDataFactory.buildFund('Building Fund', false);
        insert building;

        Test.startTest();
        String moved = refusalOf(new Gift_Allocation__c(Id = existing.Id, Fund__c = building.Id));
        String removed = deleteRefusal(new Gift_Allocation__c(Id = existing.Id));
        Database.SaveResult added = Database.insert(
            GivingTestDataFactory.buildAllocation(gift.Id, building.Id, 10),
            false
        );
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_AllocationLocked, moved, 'No fund changes.');
        Assert.areEqual(Label.Giving_Posting_AllocationLocked, removed, 'None is taken away.');
        Assert.isFalse(added.isSuccess(), 'None is added.');
        Assert.isTrue(
            messagesOf(added.getErrors()).contains(Label.Giving_Posting_AllocationLocked),
            'Refused by the lock: ' + messagesOf(added.getErrors())
        );
    }

    private static List<String> messagesOf(List<Database.Error> errors) {
        List<String> messages = new List<String>();
        for (Database.Error error : errors) {
            messages.add(error.getMessage());
        }
        return messages;
    }

    @IsTest
    static void anAllocationIsNotRestoredOntoALockedGift() {
        TestDataFactory.pausedSettings(2);
        AutomationControl.clearCache();
        Gift_Allocation__c existing = giftOf(250).Gift_Allocations__r[0];
        delete existing;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        Database.UndeleteResult result = Database.undelete(existing.Id, false);
        Test.stopTest();

        Assert.isFalse(result.isSuccess(), 'Restoring is adding a fund to the books.');
        Assert.isTrue(
            messagesOf(result.getErrors()).contains(Label.Giving_Posting_AllocationLocked),
            'Refused by the lock, pause or no pause: ' + messagesOf(result.getErrors())
        );
    }

    // -------------------------------------------------------------------------------------
    // What a locked gift names (R-G15)
    // -------------------------------------------------------------------------------------

    private static Contact ana() {
        return [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
    }

    @IsTest
    static void theDonorOfALockedGiftIsNotDeleted() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String refusal = deleteRefusal(ana());
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_DonorLocked, refusal);
        Assert.isNotNull(giftOf(250).Donor_Contact__c, 'The books still name Ana.');
    }

    @IsTest
    static void aDonorWhoseGiftsAreAllOpenIsDeleted() {
        Contact ben = ben();
        update new Gift__c(Id = giftOf(40).Id, Donor_Contact__c = ben.Id);
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String refusal = deleteRefusal(ben);
        Test.stopTest();

        Assert.isNull(refusal, 'Ben\'s only gift is dated today and not posted.');
    }

    @IsTest
    static void theDonorOfALockedGiftCanStillBeMerged() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Contact ben = ben();

        Test.startTest();
        Database.MergeResult result = Database.merge(ben, ana().Id, false);
        Test.stopTest();

        Assert.isTrue(result.isSuccess(), 'A merge is not a delete: ' + result.getErrors());
        Assert.areEqual(ben.Id, giftOf(250).Donor_Contact__c, 'The gift moved to Ben.');
    }

    @IsTest
    static void theOrganizationDonorOfALockedGiftIsNotDeleted() {
        Account riverside = new Account(Name = 'Riverside Foundation');
        insert riverside;
        Gift__c grant = GivingTestDataFactory.buildGift(null, 500);
        grant.Donor_Account__c = riverside.Id;
        grant.Gift_Date__c = inClosedPeriod();
        insert grant;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String refusal = deleteRefusal(riverside);
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_DonorLocked, refusal);
    }

    @IsTest
    static void theHouseholdOfALockedGiftsDonorIsNotDeleted() {
        // Ana's gift names only her, not her household; deleting the household would delete her
        // with no Contact trigger and blank the gift's donor.
        Id household = [SELECT AccountId FROM Contact WHERE LastName = 'Nolan' LIMIT 1].AccountId;
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        String refusal = deleteRefusal(new Account(Id = household));
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_DonorLocked, refusal);
        Assert.areEqual(ana().Id, giftOf(250).Donor_Contact__c, 'The books still name Ana.');
    }

    @IsTest
    static void theOriginalOfAPostedRefundIsNotDeleted() {
        Gift__c original = giftOf(40);
        Id refundId = GiftService.refund(original.Id, 10, 'Returned');
        markPosted(refundId);
        // Paused, so the switchable rule that already guards an original with a refund is out of
        // the way and only the lock is left to refuse.
        TestDataFactory.pausedSettings(2);
        AutomationControl.clearCache();

        Test.startTest();
        String refusal = deleteRefusal(new Gift__c(Id = original.Id));
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_OriginalLocked, refusal);
    }

    @IsTest
    static void theLockStillHoldsWhileAllAutomationIsPaused() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        TestDataFactory.pausedSettings(2);
        AutomationControl.clearCache();

        Test.startTest();
        String refusal = refusalOf(new Gift__c(Id = giftOf(250).Id, Amount__c = 1));
        Test.stopTest();

        Assert.areEqual(
            closedGiftMessage(),
            refusal,
            'The pause stops BarnCRM filling things in, never stops it refusing something.'
        );
    }

    // -------------------------------------------------------------------------------------
    // Posted gifts
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aPostedGiftInAnOpenMonthIsLockedTheSameWay() {
        Gift__c gift = giftOf(40);
        markPosted(gift.Id);

        Test.startTest();
        String amount = refusalOf(new Gift__c(Id = gift.Id, Amount__c = 45));
        String deleted = deleteRefusal(new Gift__c(Id = gift.Id));
        String appeal = refusalOf(
            new Gift__c(Id = gift.Id, Acknowledgment_Status__c = 'Do not acknowledge')
        );
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_PostedGiftLocked, amount, 'The amount is posted.');
        Assert.areEqual(Label.Giving_Posting_PostedGiftLocked, deleted, 'So is the gift.');
        Assert.isNull(appeal, 'What the books do not hold stays editable.');
    }

    @IsTest
    static void thePostingFieldsAreWrittenOnlyThroughThePostingDoor() {
        Gift__c gift = giftOf(40);
        Contact ana = [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
        Gift__c alreadyPosted = GivingTestDataFactory.buildGift(ana.Id, 12);
        alreadyPosted.Accounting_Posted_At__c = System.now();

        Test.startTest();
        String typed = refusalOf(new Gift__c(Id = gift.Id, Accounting_Posted_At__c = System.now()));
        Database.SaveResult created = Database.insert(alreadyPosted, false);
        markPosted(gift.Id);
        String cleared = refusalOf(new Gift__c(Id = gift.Id, Accounting_Posted_At__c = null));
        Test.stopTest();

        Assert.areEqual(Label.Giving_Posting_FieldsWrittenByPosting, typed, 'Not by hand.');
        Assert.isFalse(created.isSuccess(), 'Nor on a new gift.');
        Assert.areEqual(Label.Giving_Posting_FieldsWrittenByPosting, cleared, 'Nor cleared.');
        Assert.isNotNull(giftOf(40).Accounting_Posted_At__c, 'The door itself works.');
    }

    // -------------------------------------------------------------------------------------
    // Money going back
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aPostedGiftInAClosedMonthCanStillBeRefundedAsANewGiftToday() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c gift = giftOf(250);
        markPosted(gift.Id);

        Test.startTest();
        Id refundId = GiftService.refund(gift.Id, 250, 'Card charged twice');
        Test.stopTest();

        Gift__c refund = [
            SELECT Gift_Date__c, Amount__c, Accounting_Posted_At__c
            FROM Gift__c
            WHERE Id = :refundId
        ];
        Assert.areEqual(Date.today(), refund.Gift_Date__c, 'The refund lands in an open month.');
        Assert.isNull(refund.Accounting_Posted_At__c, 'And waits for the next export.');
        Gift__c original = giftOf(250);
        Assert.areEqual('Refunded', original.Status__c, 'The original moved within the books.');
        Assert.isNotNull(original.Accounting_Posted_At__c, 'And stays posted.');
    }

    @IsTest
    static void aPendingGiftInAClosedMonthIsCancelledNotWrittenOff() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c pending = giftOf(75);
        Integer before = [SELECT COUNT() FROM Gift__c];

        Test.startTest();
        String refusal;
        try {
            GiftService.writeOff(pending.Id, 'Never paid');
        } catch (GiftService.GiftServiceException refused) {
            refusal = refused.getMessage();
        }
        update new Gift__c(Id = pending.Id, Status__c = 'Cancelled');
        Test.stopTest();

        Assert.areEqual(
            String.format(Label.Giving_Gift_ReverseNeedsReceived, new List<String>{ 'Pending' }),
            refusal,
            'Nothing was received, so nothing is written off (R-G3).'
        );
        Assert.areEqual(before, [SELECT COUNT() FROM Gift__c], 'No negative gift.');
        Assert.areEqual(
            'Cancelled',
            giftOf(75).Status__c,
            'Neither Pending nor Cancelled is in the books, so the lock lets it through (R-G16).'
        );
    }

    @IsTest
    static void aLockedReceivedGiftIsNotCancelledEvenWithAutomationPaused() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        // Paused, so the switchable status rule that refuses Received to Cancelled is out of
        // the way: the refusal left is the lock's.
        TestDataFactory.pausedSettings(2);
        AutomationControl.clearCache();

        Test.startTest();
        String refusal = refusalOf(new Gift__c(Id = giftOf(250).Id, Status__c = 'Cancelled'));
        Test.stopTest();

        Assert.areEqual(closedGiftMessage(), refusal, 'Cancelling would take it out of the books.');
        Assert.areEqual('Received', giftOf(250).Status__c);
    }

    @IsTest
    static void aReceivedGiftInAClosedMonthCanBeWrittenOff() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());

        Test.startTest();
        Id writeOffId = GiftService.writeOff(giftOf(250).Id, 'Check bounced');
        Test.stopTest();

        Assert.isNotNull(writeOffId, 'Moving within the books is what a write-off does.');
        Assert.areEqual('Written off', giftOf(250).Status__c, 'The original is written off.');
    }

    // -------------------------------------------------------------------------------------
    // The override
    // -------------------------------------------------------------------------------------

    private static User maria() {
        User maria = TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet granted = new PermissionSet(
                Name = 'Posting_Lock_Override_Test',
                Label = 'Posting lock override (test)'
            );
            insert granted;
            Id permissionId = [
                SELECT Id
                FROM CustomPermission
                WHERE DeveloperName = :OVERRIDE_PERMISSION
                LIMIT 1
            ]
            .Id;
            insert new SetupEntityAccess(ParentId = granted.Id, SetupEntityId = permissionId);
            insert new PermissionSetAssignment(AssigneeId = maria.Id, PermissionSetId = granted.Id);
        }
        return maria;
    }

    /** Gifts ship private; the test is about the lock, not about sharing. */
    private static void handTo(User person, List<Id> recordIds) {
        List<SObject> handed = new List<SObject>();
        for (Id recordId : recordIds) {
            SObject owned = recordId.getSObjectType().newSObject(recordId);
            owned.put('OwnerId', person.Id);
            handed.add(owned);
        }
        update handed;
        GiftPostingLock.overrideHeld = null;
    }

    @IsTest
    static void theOverrideLetsAnAuditorsCorrectionThroughAndRecordsIt() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c gift = giftOf(250);
        User maria = maria();
        handTo(maria, new List<Id>{ gift.Id });

        Test.startTest();
        System.runAs(maria) {
            update new Gift__c(Id = gift.Id, Payment_Reference__c = 'CHK-1010');
        }
        Test.stopTest();

        List<Error_Log__c> logged = [
            SELECT Message__c, Context__c, User__c
            FROM Error_Log__c
            WHERE Severity__c = :ErrorLogger.SEVERITY_WARNING
        ];
        Assert.areEqual(1, logged.size(), 'One overridden save, one entry.');
        Assert.areEqual('Posting lock override', logged[0].Context__c, 'Filed as an override.');
        Assert.areEqual(maria.Id, logged[0].User__c, 'Naming who did it.');
        Assert.isTrue(
            logged[0].Message__c.contains(String.valueOf(gift.Id)) &&
                logged[0].Message__c.contains('CHK-1001') &&
                logged[0].Message__c.contains('CHK-1010'),
            'Naming the gift and what moved: ' + logged[0].Message__c
        );
    }

    @IsTest
    static void theOverrideLetsALockedGiftBeDeletedAndRecordsThat() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Gift__c gift = giftOf(250);
        User maria = maria();
        handTo(maria, new List<Id>{ gift.Id });

        Test.startTest();
        System.runAs(maria) {
            delete new Gift__c(Id = gift.Id);
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c WHERE Id = :gift.Id], 'Deleted.');
        // Message__c is long text, which SOQL cannot filter on.
        List<Error_Log__c> logs = [
            SELECT Message__c
            FROM Error_Log__c
            WHERE Context__c = 'Posting lock override'
        ];
        Assert.areEqual(1, logs.size(), 'And written down.');
        Assert.isTrue(logs[0].Message__c.contains('deleted'), logs[0].Message__c);
    }

    // -------------------------------------------------------------------------------------
    // Volume
    // -------------------------------------------------------------------------------------

    @IsTest
    static void twoHundredGiftsAreRefusedAndCheckedInOneSave() {
        GivingTestDataFactory.closeBooksThrough(lastClosedDay());
        Contact ana = [SELECT Id FROM Contact WHERE LastName = 'Nolan' LIMIT 1];
        List<Gift__c> late = GivingTestDataFactory.buildGifts(ana.Id, 200, 5);
        for (Gift__c gift : late) {
            gift.Gift_Date__c = inClosedPeriod();
        }

        Test.startTest();
        List<Database.SaveResult> results = Database.insert(late, false);
        Test.stopTest();

        for (Database.SaveResult result : results) {
            Assert.isFalse(result.isSuccess(), 'Every one of them is refused.');
        }
    }
}
