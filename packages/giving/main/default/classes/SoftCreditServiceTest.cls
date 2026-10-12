/**
 * Automatic household soft credits, in both membership modes, at bulk, and through every path a
 * gift can take (feature G-08).
 */
@IsTest
private class SoftCreditServiceTest {
    @IsTest
    static void creditsTheOtherHouseholdMemberInContactMode() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Luis is the only other member of the household');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The spouse is the credited person');
        System.assertEquals(
            SoftCreditService.ROLE_HOUSEHOLD_MEMBER,
            credits[0].Role__c,
            'The role says why the credit is there'
        );
        System.assertEquals(500, credits[0].Amount__c, 'A household credit is for the whole gift');
        System.assertEquals(true, credits[0].Is_Automatic__c, 'The package created this credit');
    }

    @IsTest
    static void creditsTheOtherHouseholdMemberInJunctionMode() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        RecognitionTestData.useJunctionMembership();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', null);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', null);
        RecognitionTestData.membership(garcias.Id, ana.Id, 'Head');
        RecognitionTestData.membership(garcias.Id, luis.Id, 'Spouse or Partner');

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 250);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Junction membership credits the same one person');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The spouse is the credited person');
        System.assertEquals(250, credits[0].Amount__c, 'The credit is for the whole gift');
    }

    @IsTest
    static void creditsNobodyWhenTheSettingIsOff() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'The organization asked for no automatic credits'
        );
    }

    @IsTest
    static void removesAutomaticCreditsWhenTheSettingIsTurnedOff() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        System.assertEquals(
            1,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'Luis starts credited'
        );

        Test.startTest();
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        SettingsService.clearCaches();
        gift.Amount__c = 600;
        update gift;
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'The setting off means no household member is wanted, so the credit goes (R-SC3)'
        );
        System.assertNotEquals(null, luis.Id, 'Luis is still a person');
    }

    @IsTest
    static void creditsTheNewMemberWhenSomebodyJoinsTheHousehold() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        System.assertEquals(0, RecognitionTestData.creditsFor(gift.Id).size(), 'Ana lives alone');

        Test.startTest();
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(
            1,
            credits.size(),
            'Luis moves in and is recognized on the gift already recorded (R-SC3)'
        );
        System.assertEquals(500, credits[0].Amount__c, 'For the whole of it');
    }

    @IsTest
    static void removesTheCreditWhenSomebodyLeavesTheHousehold() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Account alvarez = RecognitionTestData.household('The Alvarez Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        System.assertEquals(
            1,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'Luis starts credited'
        );

        Test.startTest();
        luis.AccountId = alvarez.Id;
        update luis;
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'Luis moves out and stops being recognized on the gift he no longer shares (R-SC3)'
        );
    }

    @IsTest
    static void recomputesWhenTheAmountChanges() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Amount__c = 750;
        update gift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'The credit is recomputed, not duplicated');
        System.assertEquals(750, credits[0].Amount__c, 'The credit follows the gift');
    }

    @IsTest
    static void movesTheCreditWhenTheDonorChanges() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Donor_Contact__c = luis.Id;
        update gift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Still one credit, for the other member');
        System.assertEquals(ana.Id, credits[0].Contact__c, 'Ana is now the one recognized');
    }

    /**
     * ADR-0023: the status a refund writes on the original gift does not take the recognition
     * away. The negative gift's own negative credit is the reversal, and deleting this one as
     * well would leave the household member recognized for minus the gift.
     */
    @IsTest
    static void keepsCreditsWhenTheGiftIsMarkedRefunded() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Status__c = 'Refunded';
        update gift;
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'The gift keeps the credit it earned');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'Still the same person recognized');
        System.assertEquals(
            500,
            credits[0].Amount__c,
            'At the amount it earned, for the negative gift to cancel'
        );
    }

    /**
     * A write-off is the same shape as a refund with a different status, so it reads the same
     * way (ADR-0023).
     */
    @IsTest
    static void keepsCreditsWhenTheGiftIsWrittenOff() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        gift.Status__c = SoftCreditService.STATUS_WRITTEN_OFF;
        update gift;
        Test.stopTest();

        System.assertEquals(
            1,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'A written off gift keeps its credit, and its negative gift carries the reversal'
        );
    }

    @IsTest
    static void aRefundProducesNegativeCredits() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        // A negative gift is only ever the reversal of an original one (R-G3), so the refund is
        // made the way staff make it rather than typed in by hand.
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);

        Test.startTest();
        Id refundId = GiftService.refund(gift.Id, 500, 'Donor asked for the gift back');
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(refundId);
        System.assertEquals(1, credits.size(), 'The refund recognizes the household too');
        System.assertEquals(luis.Id, credits[0].Contact__c, 'The same person is recognized');
        System.assertEquals(
            -500,
            credits[0].Amount__c,
            'A negative gift produces a negative credit so totals stay right'
        );
    }

    @IsTest
    static void leavesCreditsEnteredByStaffAlone() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Soft_Credit__c manual = RecognitionTestData.manualCredit(
            gift.Id,
            solicitor.Id,
            'Solicitor',
            500
        );

        Test.startTest();
        gift.Amount__c = 900;
        update gift;
        Test.stopTest();

        Map<Id, Soft_Credit__c> byId = new Map<Id, Soft_Credit__c>(
            RecognitionTestData.creditsFor(gift.Id)
        );
        System.assertEquals(2, byId.size(), 'Both credits are still there');
        System.assertEquals(
            500,
            byId.get(manual.Id).Amount__c,
            'The credit a person entered is not recomputed'
        );
    }

    @IsTest
    static void recomputationIsIdempotent() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Id firstCreditId = RecognitionTestData.creditsFor(gift.Id)[0].Id;

        Test.startTest();
        SoftCreditService.createHouseholdMemberCredits(
            GiftLookupSelector.selectForRecognition(new Set<Id>{ gift.Id })
        );
        SoftCreditService.createHouseholdMemberCredits(
            GiftLookupSelector.selectForRecognition(new Set<Id>{ gift.Id })
        );
        Test.stopTest();

        List<Soft_Credit__c> credits = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, credits.size(), 'Running twice changes nothing');
        System.assertEquals(firstCreditId, credits[0].Id, 'The same record is kept');
    }

    /**
     * The gift is deliberately left in place. Soft Credit's Gift lookup is a master detail
     * relationship, so deleting the gift would take its credits with it whatever this package
     * does, and a test that deleted the gift would pass with the whole removal path deleted.
     * What the method promises, and what nothing else does for it, is that it removes the
     * credits BarnCRM created while leaving the ones a person entered (R-SC6).
     */
    @IsTest
    static void removesTheAutomaticCreditsAndLeavesTheOnesStaffEnteredAlone() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        // Putting Ana and Luis in the household queues a recompute of its credits (R-SC3). The
        // setup runs inside its own start and stop so that recompute has finished before the
        // removal: left queued, it ran after the removal and put Luis's credit straight back,
        // which is the household rule working, not the removal failing.
        Test.startTest();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        Contact luis = RecognitionTestData.person('Luis', 'Garcia', garcias.Id);
        Contact solicitor = RecognitionTestData.person('Tom', 'Alvarez', null);
        Gift__c gift = RecognitionTestData.gift(ana.Id, null, 500);
        Soft_Credit__c manual = RecognitionTestData.manualCredit(
            gift.Id,
            solicitor.Id,
            'Solicitor',
            500
        );
        Test.stopTest();
        Map<Id, Soft_Credit__c> before = new Map<Id, Soft_Credit__c>(
            RecognitionTestData.creditsFor(gift.Id)
        );
        System.assertEquals(2, before.size(), 'Luis is credited automatically, Tom by hand');
        System.assertEquals(
            luis.Id,
            automaticIn(before.values())[0].Contact__c,
            'And the automatic one is the household member credit'
        );

        SoftCreditService.removeAutomaticCredits(new Set<Id>{ gift.Id });

        System.assertEquals(
            1,
            [SELECT COUNT() FROM Gift__c WHERE Id = :gift.Id],
            'The gift itself is untouched, so no cascade explains what happened to the credits'
        );
        List<Soft_Credit__c> remaining = RecognitionTestData.creditsFor(gift.Id);
        System.assertEquals(1, remaining.size(), 'Only one credit is left');
        System.assertEquals(manual.Id, remaining[0].Id, 'And it is the one Tom was given by hand');
        System.assertEquals(false, remaining[0].Is_Automatic__c, 'A manual credit stays manual');
        System.assertEquals(500, remaining[0].Amount__c, 'With the amount staff entered');
        System.assertEquals(
            0,
            automaticIn(remaining).size(),
            'Every credit BarnCRM created for the gift is gone'
        );
    }

    private static List<Soft_Credit__c> automaticIn(List<Soft_Credit__c> credits) {
        List<Soft_Credit__c> automatic = new List<Soft_Credit__c>();
        for (Soft_Credit__c credit : credits) {
            if (credit.Is_Automatic__c == true) {
                automatic.add(credit);
            }
        }
        return automatic;
    }

    @IsTest
    static void creditsTwoHundredGiftsInOneInsert() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        GivingTestDataFactory.ensureDefaultFund();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Contact ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        RecognitionTestData.person('Luis', 'Garcia', garcias.Id);

        List<Gift__c> gifts = new List<Gift__c>();
        for (Integer i = 0; i < 200; i++) {
            gifts.add(RecognitionTestData.newGift(ana.Id, null, 10 + i));
        }

        Test.startTest();
        insert gifts;
        Test.stopTest();

        System.assertEquals(
            200,
            [SELECT COUNT() FROM Soft_Credit__c WHERE Is_Automatic__c = TRUE],
            'Two hundred gifts credit two hundred times, in one transaction'
        );
    }

    @IsTest
    static void creditsNobodyForAnOrganizationGift() {
        RecognitionTestData.setAutomaticHouseholdCredits(true);
        Account riverbend = RecognitionTestData.organization('Riverbend Manufacturing');

        Test.startTest();
        Gift__c gift = RecognitionTestData.gift(null, riverbend.Id, 1000);
        Test.stopTest();

        System.assertEquals(
            0,
            RecognitionTestData.creditsFor(gift.Id).size(),
            'An organization has no household members'
        );
    }

    @IsTest
    static void percentAndAmountConvertBothWays() {
        System.assertEquals(
            50,
            SoftCreditService.percentOf(250, 500),
            'Half a gift is fifty percent of it'
        );
        System.assertEquals(
            250,
            SoftCreditService.amountOf(50, 500),
            'Fifty percent of a gift is half of it'
        );
        System.assertEquals(
            null,
            SoftCreditService.percentOf(250, 0),
            'A gift of nothing has no share'
        );
    }
}
