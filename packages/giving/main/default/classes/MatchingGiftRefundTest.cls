/**
 * What a refund of the employer's gift does to the employee's matched donor credit (R-G11,
 * R-SC5, ADR-0031).
 *
 * ADR-0023 settled the household credit and left this one open: the Matched Donor credit sits on
 * the employer's gift, and the negative gift recording a refund is not half of a matching pair,
 * so nothing reversed it and a match the company took back went on recognizing the employee for
 * the whole of it. The refund now propagates along the link as a negative credit, prorated to
 * what came back.
 *
 * Like `SoftCreditRefundTest`, the case that turns on a number a fundraiser reads runs the real
 * refund path and the real shipped rollup rows rather than definitions the test builds.
 */
@IsTest(testFor='ApexClass:MatchingGiftService, ApexClass:GiftService')
private class MatchingGiftRefundTest {
    private static final String KEY_TOTAL = 'Contact_Total_Soft_Credits';
    private static final String KEY_COUNT = 'Contact_Soft_Credit_Count';

    /**
     * Riverbend matches Ana's gift with 500 and then takes all of it back. Ana keeps the record
     * of having been recognized and is recognized for nothing: the pair cancels, the way the
     * household credit pair does.
     */
    @IsTest
    static void aFullyRefundedMatchLeavesTheEmployeeRecognizedForNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);

            Test.startTest();
            Id refundId = GiftService.refund(data.employerGift.Id, 500, 'The company reversed it');
            Test.stopTest();

            Assert.areEqual(
                'Refunded',
                [SELECT Status__c FROM Gift__c WHERE Id = :data.employerGift.Id].Status__c,
                'The whole match has gone back, so R-G3 moves the employer gift off Received.'
            );
            List<Soft_Credit__c> onEmployerGift = RecognitionTestData.creditsFor(
                data.employerGift.Id
            );
            Assert.areEqual(
                1,
                onEmployerGift.size(),
                'The employer gift keeps the credit the link created: the reversal is the negative ' +
                'gift, not the deletion of this one (ADR-0031).'
            );
            Assert.areEqual(
                500,
                onEmployerGift[0].Amount__c,
                'And keeps it at the amount that was matched, so a recognition list produced before ' +
                'the refund is still explicable afterwards.'
            );

            List<Soft_Credit__c> onRefund = RecognitionTestData.creditsFor(refundId);
            Assert.areEqual(1, onRefund.size(), 'The negative gift carries exactly one credit.');
            Assert.areEqual(
                data.ana.Id,
                onRefund[0].Contact__c,
                'It reverses the person the match recognized, not the company that gave it.'
            );
            Assert.areEqual(
                SoftCreditService.ROLE_MATCHED_DONOR,
                onRefund[0].Role__c,
                'It is the same recognition being taken back, so it carries the same role.'
            );
            Assert.areEqual(
                -500,
                onRefund[0].Amount__c,
                'The whole match came back, so the whole of the credit is reversed.'
            );
            Assert.areEqual(
                true,
                onRefund[0].Is_Automatic__c,
                'The package created it, so the package may maintain it (R-SC6).'
            );
        }
    }

    /**
     * The case the decision turns on. Riverbend matches with 500 and asks for 200 back, so the
     * employer gift stays at Received and only part of the recognition is reversed. A mechanism
     * that fired on the status change instead would do nothing here.
     */
    @IsTest
    static void aPartlyRefundedMatchLeavesRecognitionForWhatTheEmployerStillHolds() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
            Id refundId = GiftService.refund(data.employerGift.Id, 200, 'Overpaid the match');

            Assert.areEqual(
                'Received',
                [SELECT Status__c FROM Gift__c WHERE Id = :data.employerGift.Id].Status__c,
                'Part of the match is still held, so the employer gift keeps its status.'
            );
            Assert.areEqual(
                -200,
                RecognitionTestData.creditsFor(refundId)[0].Amount__c,
                'The credit reverses what came back, not what was given.'
            );

            Test.startTest();
            RollupService.ensureDefaults();
            RollupService.runFullRecalculation(
                definitionsFor(new Set<String>{ KEY_TOTAL, KEY_COUNT })
            );
            Test.stopTest();

            Contact recalculated = [
                SELECT Total_Soft_Credits__c, Soft_Credit_Count__c
                FROM Contact
                WHERE Id = :data.ana.Id
            ];

            GivingTestDataFactory.assertRollupWrote(recalculated.Total_Soft_Credits__c);
            Assert.areEqual(
                300,
                recalculated.Total_Soft_Credits__c,
                'Both rows sit on gifts inside the widened status filter (ADR-0022), so the rollup ' +
                'sums 500 and minus 200: what the employer still holds because of Ana.'
            );
            Assert.areEqual(
                1,
                recalculated.Soft_Credit_Count__c,
                'Ana was recognized on one gift. The count row requires a positive amount, so the ' +
                'reversal is not a second gift recognized.'
            );
        }
    }

    /**
     * A write-off is a refund with a different status on the original, so it reverses the credit
     * the same way. Nothing in the mechanism reads which of the two it was.
     */
    @IsTest
    static void aWrittenOffMatchReversesTheCreditTheSameWay() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);

            Test.startTest();
            Id writeOffId = GiftService.writeOff(data.employerGift.Id, 'The check never cleared');
            Test.stopTest();

            Assert.areEqual(
                'Written off',
                [SELECT Status__c FROM Gift__c WHERE Id = :data.employerGift.Id].Status__c,
                'A write-off moves the original to its own status.'
            );
            Assert.areEqual(
                -500,
                RecognitionTestData.creditsFor(writeOffId)[0].Amount__c,
                'Money the organization never collected recognizes nobody, so the whole credit is ' +
                'reversed.'
            );
        }
    }

    /**
     * An organization gift that matched nothing has no matched donor credit to reverse, so its
     * refund produces none. The mechanism reads the credits the reversed gift carries rather than
     * the shape of the gift, which is what keeps this case free of a branch of its own.
     */
    @IsTest
    static void refundingAnUnmatchedEmployerGiftCreatesNoCredit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();

            Test.startTest();
            Id refundId = GiftService.refund(
                data.employerGift.Id,
                500,
                'Sent to the wrong charity'
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                RecognitionTestData.creditsFor(data.employerGift.Id).size(),
                'An unlinked company gift recognizes nobody in the first place.'
            );
            Assert.areEqual(
                0,
                RecognitionTestData.creditsFor(refundId).size(),
                'So its refund has nothing to reverse, and invents no recognition to take away.'
            );
        }
    }

    /**
     * The other half of the decision: the credit is recognition for the employer's money, so a
     * refund of the employee's own gift leaves it standing. The company's match is still money
     * the organization holds, and Ana did cause it.
     */
    @IsTest
    static void refundingTheEmployeeGiftLeavesTheMatchedCreditStanding() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);

            Test.startTest();
            Id refundId = GiftService.refund(data.employeeGift.Id, 500, 'Ana asked for hers back');
            Test.stopTest();

            Assert.areEqual(
                500,
                RecognitionTestData.creditsFor(data.employerGift.Id)[0].Amount__c,
                'The employer gift still recognizes Ana for the match the company still holds.'
            );
            Assert.areEqual(
                0,
                RecognitionTestData.creditsFor(refundId).size(),
                'And the negative gift reversing her own gift carries no matched donor credit, ' +
                'because the gift it reverses carried none.'
            );
        }
    }

    /**
     * Unlinking after a refund takes both halves away. Removing only the positive one would leave
     * the employee recognized for minus the amount returned, which is a worse number than no rows
     * at all.
     */
    @IsTest
    static void unlinkingAfterARefundRemovesBothHalvesOfThePair() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
            Id refundId = GiftService.refund(data.employerGift.Id, 200, 'Overpaid the match');
            Assert.areEqual(
                1,
                RecognitionTestData.creditsFor(refundId).size(),
                'The reversal is there to be removed.'
            );

            Test.startTest();
            MatchingGiftService.unlink(data.employerGift.Id);
            Test.stopTest();

            Assert.areEqual(
                0,
                RecognitionTestData.creditsFor(data.employerGift.Id).size(),
                'The credit the link created goes with the link.'
            );
            Assert.areEqual(
                0,
                RecognitionTestData.creditsFor(refundId).size(),
                'And the negative credit that only existed to reverse it goes too.'
            );
        }
    }

    /**
     * The order the two events happen in must not change the answer. Linking a gift that was
     * already partly refunded credits the employee for the match and reverses what came back in
     * the same act, so recognition never reads the full amount for a gift already partly
     * returned.
     */
    @IsTest
    static void linkingAGiftAlreadyPartlyRefundedReversesTheReturnedPart() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Setup data = setUp();
            Id refundId = GiftService.refund(data.employerGift.Id, 200, 'Overpaid the match');

            Test.startTest();
            MatchingGiftService.link(data.employeeGift.Id, data.employerGift.Id);
            Test.stopTest();

            Assert.areEqual(
                500,
                RecognitionTestData.creditsFor(data.employerGift.Id)[0].Amount__c,
                'The credit the link creates is still the employer gift, whole.'
            );
            Assert.areEqual(
                -200,
                RecognitionTestData.creditsFor(refundId)[0].Amount__c,
                'And the part already returned is already reversed, so the total reads 300 ' +
                'whichever of the refund and the link happened first.'
            );
        }
    }

    private class Setup {
        Contact ana;
        Gift__c employeeGift;
        Gift__c employerGift;
    }

    private static Setup setUp() {
        RecognitionTestData.setAutomaticHouseholdCredits(false);
        GivingTestDataFactory.insertDefaultFund();
        Setup data = new Setup();
        Account garcias = RecognitionTestData.household('The Garcia Family');
        Account riverbend = RecognitionTestData.organization('Riverbend Manufacturing');
        data.ana = RecognitionTestData.person('Ana', 'Garcia', garcias.Id);
        data.ana.Employer__c = riverbend.Id;
        update data.ana;
        data.employeeGift = RecognitionTestData.gift(data.ana.Id, null, 500);
        data.employerGift = RecognitionTestData.gift(null, riverbend.Id, 500);
        return data;
    }

    private static List<Rollup_Definition__c> definitionsFor(Set<String> keys) {
        List<Rollup_Definition__c> definitions = [
            SELECT
                Id,
                Name,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Active__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :keys
        ];
        Assert.areEqual(
            keys.size(),
            definitions.size(),
            'The shipped defaults under test have to be materialized before they can run.'
        );
        return definitions;
    }
}
