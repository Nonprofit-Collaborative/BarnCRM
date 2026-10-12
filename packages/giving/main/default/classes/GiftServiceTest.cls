/**
 * Money that goes back is recorded, never erased (R-G3, ADR-0010). These tests follow the
 * refunds walkthrough David is given in the admin guide.
 */
@IsTest
private class GiftServiceTest {
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.insertDefaultFund();
        GivingTestDataFactory.insertHouseholdContact('The Nolan Family', 'Ana', 'Nolan');
    }

    private static Gift__c insertGift(Decimal amount) {
        Contact person = [SELECT Id FROM Contact LIMIT 1];
        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, amount);
        insert gift;
        return gift;
    }

    @IsTest
    static void aPartialRefundLeavesTheOriginalReceived() {
        Gift__c original = insertGift(250);

        Test.startTest();
        Id refundId = GiftService.refund(
            original.Id,
            100,
            'Donor asked for the misdirected portion back'
        );
        Test.stopTest();

        Gift__c refund = [
            SELECT
                Id,
                Amount__c,
                Status__c,
                Original_Gift__c,
                Refund_Reason__c,
                Gift_Date__c,
                Donor_Contact__c
            FROM Gift__c
            WHERE Id = :refundId
        ];
        System.assertEquals(-100, refund.Amount__c, 'A refund is a negative gift.');
        System.assertEquals(
            'Received',
            refund.Status__c,
            'The refund itself is a transaction that happened.'
        );
        System.assertEquals(original.Id, refund.Original_Gift__c, 'It is linked to the original.');
        System.assertEquals(Date.today(), refund.Gift_Date__c, 'It is dated the day it was made.');
        System.assert(
            refund.Refund_Reason__c.contains('misdirected'),
            'The reason is carried on the refund.'
        );

        Gift__c reloaded = [SELECT Id, Status__c, Amount__c FROM Gift__c WHERE Id = :original.Id];
        System.assertEquals(
            'Received',
            reloaded.Status__c,
            'Part of the gift is still a gift, so the original stays Received.'
        );
        System.assertEquals(250, reloaded.Amount__c, 'The original is never edited.');

        Gift_Allocation__c mirrored = [
            SELECT Id, Amount__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :refundId
        ];
        System.assertEquals(
            -100,
            mirrored.Amount__c,
            'The refund mirrors the designation negatively, so the fund total corrects itself.'
        );
    }

    @IsTest
    static void refundingTheRestClosesTheOriginal() {
        Gift__c original = insertGift(250);
        GiftService.refund(original.Id, 100, 'First part back');

        Test.startTest();
        GiftService.refund(original.Id, 150, 'The rest back');
        Test.stopTest();

        Gift__c reloaded = [SELECT Id, Status__c FROM Gift__c WHERE Id = :original.Id];
        System.assertEquals(
            'Refunded',
            reloaded.Status__c,
            'Once the whole gift has gone back, the original says so.'
        );
    }

    @IsTest
    static void refundingMoreThanIsLeftIsRefused() {
        Gift__c original = insertGift(250);
        GiftService.refund(original.Id, 200, 'Most of it back');

        String message = '';
        Test.startTest();
        try {
            GiftService.refund(original.Id, 100, 'Too much');
        } catch (GiftService.GiftServiceException tooMuch) {
            message = tooMuch.getMessage();
        }
        Test.stopTest();

        System.assert(
            message.contains('larger than the amount left'),
            'A second refund cannot take more than is left: ' + message
        );
    }

    @IsTest
    static void refundNeedsAnAmountAndAGift() {
        Gift__c original = insertGift(50);
        String zeroMessage = '';
        String missingMessage = '';

        Test.startTest();
        try {
            GiftService.refund(original.Id, 0, 'Nothing');
        } catch (GiftService.GiftServiceException zeroError) {
            zeroMessage = zeroError.getMessage();
        }
        try {
            GiftService.refund(null, 10, 'No gift');
        } catch (GiftService.GiftServiceException missingError) {
            missingMessage = missingError.getMessage();
        }
        Test.stopTest();

        System.assert(zeroMessage.contains('more than zero'), zeroMessage);
        System.assert(missingMessage.contains('could not be found'), missingMessage);
    }

    @IsTest
    static void aWriteOffClosesTheGiftAndReversesTheRest() {
        Gift__c original = insertGift(500);

        Test.startTest();
        Id writeOffId = GiftService.writeOff(original.Id, 'Pledged at the gala, never paid');
        Test.stopTest();

        Gift__c writeOff = [
            SELECT Id, Amount__c, Original_Gift__c, Refund_Reason__c
            FROM Gift__c
            WHERE Id = :writeOffId
        ];
        System.assertEquals(-500, writeOff.Amount__c, 'The whole gift is reversed.');
        System.assertEquals(original.Id, writeOff.Original_Gift__c, 'Linked to the original.');

        Gift__c reloaded = [SELECT Id, Status__c FROM Gift__c WHERE Id = :original.Id];
        System.assertEquals('Written off', reloaded.Status__c, 'The original says what happened.');
    }

    @IsTest
    static void aGiftThatIsAlreadyBackCannotBeWrittenOffAgain() {
        Gift__c original = insertGift(120);
        GiftService.writeOff(original.Id, 'Never paid');

        String message = '';
        Test.startTest();
        try {
            GiftService.writeOff(original.Id, 'Again');
        } catch (GiftService.GiftServiceException alreadyDone) {
            message = alreadyDone.getMessage();
        }
        Test.stopTest();

        System.assert(message.contains('nothing left'), message);
    }

    @IsTest
    static void aNegativeGiftCannotItselfBeRefunded() {
        Gift__c original = insertGift(80);
        Id refundId = GiftService.refund(original.Id, 80, 'All back');

        String message = '';
        Test.startTest();
        try {
            GiftService.refund(refundId, 10, 'Refund of a refund');
        } catch (GiftService.GiftServiceException notAllowed) {
            message = notAllowed.getMessage();
        }
        Test.stopTest();

        System.assert(message.contains('already records money going back'), message);
    }

    @IsTest
    static void theSettingsFundWinsOverTheFlaggedFund() {
        Fund__c chosen = GivingTestDataFactory.buildFund('Building', false);
        insert chosen;
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Default_Fund__c = chosen.Id;
        upsert settings;
        SettingsService.clearCaches();

        Test.startTest();
        Gift__c gift = insertGift(60);
        Test.stopTest();

        Gift_Allocation__c allocation = [
            SELECT Id, Fund__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :gift.Id
        ];
        System.assertEquals(
            chosen.Id,
            allocation.Fund__c,
            'The fund Maria picked in settings is the one gifts land in.'
        );
    }

    @IsTest
    static void anUnusableSettingsFundFallsBackToTheFlaggedFund() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Default_Fund__c = 'not an identifier';
        upsert settings;
        SettingsService.clearCaches();
        Fund__c flagged = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];

        Test.startTest();
        Gift__c gift = insertGift(30);
        Test.stopTest();

        Gift_Allocation__c allocation = [
            SELECT Id, Fund__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :gift.Id
        ];
        System.assertEquals(
            flagged.Id,
            allocation.Fund__c,
            'A stale setting does not stop David entering a gift.'
        );
    }

    @IsTest
    static void mirroredAllocationsStillTotalTheRefundWhenTheySplitUnevenly() {
        Contact person = [SELECT Id FROM Contact LIMIT 1];
        Fund__c general = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        Fund__c scholarship = GivingTestDataFactory.buildFund('Scholarship', false);
        insert scholarship;

        Gift__c gift = GivingTestDataFactory.buildGift(person.Id, 10);
        try {
            GiftService.suppressDefaultAllocations = true;
            insert gift;
        } finally {
            GiftService.suppressDefaultAllocations = false;
        }
        insert new List<Gift_Allocation__c>{
            GivingTestDataFactory.buildAllocation(gift.Id, general.Id, 3.33),
            GivingTestDataFactory.buildAllocation(gift.Id, scholarship.Id, 6.67)
        };

        Test.startTest();
        Id refundId = GiftService.refund(gift.Id, 5, 'Half back');
        Test.stopTest();

        Decimal total = 0;
        for (Gift_Allocation__c allocation : [
            SELECT Amount__c
            FROM Gift_Allocation__c
            WHERE Gift__c = :refundId
        ]) {
            total += allocation.Amount__c;
        }
        System.assertEquals(
            -5,
            total,
            'A refund of an unevenly split gift still totals the refund exactly, with the ' +
            'rounding difference on the largest mirrored allocation (R-GA3).'
        );
    }

    @IsTest
    static void aCallerThatWasSuppressingAllocationsStillIsAfterARefund() {
        Gift__c original = insertGift(90);

        Test.startTest();
        GiftService.suppressDefaultAllocations = true;
        try {
            GiftService.refund(original.Id, 30, 'Part back');
            System.assertEquals(
                true,
                GiftService.suppressDefaultAllocations,
                'Recording a refund gives the caller back the suppression it had, rather than ' +
                'quietly turning it off part way through their own save.'
            );
        } finally {
            GiftService.suppressDefaultAllocations = false;
        }
        Test.stopTest();
    }

    @IsTest
    static void chosenFundsGiftByGiftFailOnlyTheGiftTheyBelongTo() {
        Fund__c building = GivingTestDataFactory.buildFund('Building Fund', false);
        insert building;
        Gift__c kept = insertGift(80);
        Fund__c defaultFund = [SELECT Id FROM Fund__c WHERE Is_Default__c = TRUE LIMIT 1];
        Gift__c split;
        GiftService.suppressDefaultAllocations = true;
        try {
            split = insertGift(100);
            insert new List<Gift_Allocation__c>{
                GivingTestDataFactory.buildAllocation(split.Id, defaultFund.Id, 60),
                GivingTestDataFactory.buildAllocation(split.Id, defaultFund.Id, 40)
            };
        } finally {
            GiftService.suppressDefaultAllocations = false;
        }
        // A gift the platform cannot attach an allocation to: its record is not there.
        Gift__c missing = new Gift__c(
            Id = Gift__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() +
                '000000000001',
            Amount__c = 10
        );

        Test.startTest();
        Map<Id, String> notApplied = GiftService.applyChosenFundsEach(
            new List<Gift__c>{ kept, split, missing },
            new Map<Id, Id>{
                kept.Id => building.Id,
                split.Id => building.Id,
                missing.Id => building.Id
            }
        );
        Test.stopTest();

        Assert.areEqual(2, notApplied.size(), String.valueOf(notApplied));
        Assert.isTrue(notApplied.containsKey(split.Id));
        Assert.isNull(notApplied.get(split.Id), 'Already split: nothing for the platform to say.');
        Assert.isNotNull(notApplied.get(missing.Id), 'The platform says why it refused.');
        Assert.areEqual(
            building.Id,
            [SELECT Fund__c FROM Gift_Allocation__c WHERE Gift__c = :kept.Id].Fund__c,
            'The gift that could be designated was, although another in the call failed.'
        );
    }
}
