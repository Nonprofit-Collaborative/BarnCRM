/**
 * ADR-0032's first test: which rule wins, and which gifts are outside the feature entirely
 * (R-AK1, R-AK2, R-AK8).
 *
 * Matching is a pure function, so most of this needs no records at all: the gifts are built in
 * memory and the rules are a list. That is the point of keeping the matcher free of DML.
 */
@IsTest(testFor='ApexClass:AcknowledgmentRuleService')
private class AcknowledgmentRuleMatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static List<Acknowledgment_Rule__c> ladder() {
        Acknowledgment_Rule__c major = AcknowledgmentTestData.buildRule(
            'Major gifts',
            10,
            AcknowledgmentRuleService.CHANNEL_LETTER,
            null
        );
        major.Minimum_Amount__c = 1000;

        Acknowledgment_Rule__c everything = AcknowledgmentTestData.buildRule(
            'Everything else',
            100,
            AcknowledgmentRuleService.CHANNEL_EMAIL,
            'BarnCRM_Thank_You'
        );
        return new List<Acknowledgment_Rule__c>{ major, everything };
    }

    /**
     * A contact identifier that no record has. Matching never reads the donor, only compares the
     * identifier, so a test of the rule does not need two saved contacts to make its point.
     */
    private static Id fakeContactId(Integer sequence) {
        String suffix = String.valueOf(sequence).leftPad(12, '0');
        return Id.valueOf(
            Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getKeyPrefix() + suffix
        );
    }

    private static Gift__c giftOf(Decimal amount) {
        return new Gift__c(
            Amount__c = amount,
            Status__c = 'Received',
            Type__c = 'Check',
            Donor_Contact__c = null
        );
    }

    @IsTest
    static void lowestOrderedMatchingRuleWins() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c large = giftOf(2500);
            Gift__c small = giftOf(50);

            AcknowledgmentRuleService.RuleMatch forLarge = AcknowledgmentRuleService.matchFor(
                large,
                ladder(),
                new Set<String>()
            );
            AcknowledgmentRuleService.RuleMatch forSmall = AcknowledgmentRuleService.matchFor(
                small,
                ladder(),
                new Set<String>()
            );

            Assert.areEqual(
                AcknowledgmentRuleService.CHANNEL_LETTER,
                forLarge.channel,
                'A gift of 2500 is at or above the major gift rule minimum of 1000, and that rule is ' +
                'ordered 10 against the catch all rule ordered 100, so the letter wins.'
            );
            Assert.areEqual(
                AcknowledgmentRuleService.CHANNEL_EMAIL,
                forSmall.channel,
                'A gift of 50 is below the major gift minimum, so the only rule left is the catch all.'
            );
        }
    }

    @IsTest
    static void bothEndsOfAnAmountRangeAreIncluded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Acknowledgment_Rule__c banded = AcknowledgmentTestData.buildRule(
                'Mid range',
                10,
                AcknowledgmentRuleService.CHANNEL_EMAIL,
                'BarnCRM_Thank_You'
            );
            banded.Minimum_Amount__c = 100;
            banded.Maximum_Amount__c = 1000;
            List<Acknowledgment_Rule__c> rules = new List<Acknowledgment_Rule__c>{ banded };

            Assert.isNotNull(
                AcknowledgmentRuleService.matchFor(giftOf(100), rules, new Set<String>()),
                'A gift of exactly the minimum is inside the band (R-AK2).'
            );
            Assert.isNotNull(
                AcknowledgmentRuleService.matchFor(giftOf(1000), rules, new Set<String>()),
                'A gift of exactly the maximum is inside the band (R-AK2).'
            );
            Assert.isNull(
                AcknowledgmentRuleService.matchFor(giftOf(1000.01), rules, new Set<String>()),
                'A gift a cent above the maximum is outside the band, so no rule matches it.'
            );
        }
    }

    @IsTest
    static void anEmptyCriterionMatchesEverythingRatherThanNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Acknowledgment_Rule__c typed = AcknowledgmentTestData.buildRule(
                'Stock gifts',
                10,
                AcknowledgmentRuleService.CHANNEL_LETTER,
                null
            );
            typed.Gift_Type__c = 'Stock';
            Acknowledgment_Rule__c anyType = AcknowledgmentTestData.buildRule(
                'Anything',
                20,
                AcknowledgmentRuleService.CHANNEL_EMAIL,
                'BarnCRM_Thank_You'
            );
            List<Acknowledgment_Rule__c> rules = new List<Acknowledgment_Rule__c>{ typed, anyType };

            Gift__c check = giftOf(500);
            Gift__c stock = giftOf(500);
            stock.Type__c = 'Stock';

            Assert.areEqual(
                'Anything',
                AcknowledgmentRuleService.matchFor(check, rules, new Set<String>()).ruleName,
                'A check does not match a rule that names Stock, and falls through to the rule with ' +
                'no type on it.'
            );
            Assert.areEqual(
                'Stock gifts',
                AcknowledgmentRuleService.matchFor(stock, rules, new Set<String>()).ruleName,
                'A stock gift matches the typed rule, which is ordered first.'
            );
        }
    }

    @IsTest
    static void anInactiveRuleMatchesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Acknowledgment_Rule__c> rules = ladder();
            rules[0].Active__c = false;

            Assert.areEqual(
                AcknowledgmentRuleService.CHANNEL_EMAIL,
                AcknowledgmentRuleService.matchFor(giftOf(5000), rules, new Set<String>()).channel,
                'With the major gift rule deactivated, a 5000 gift falls through to the catch all ' +
                'rather than being matched by a rule nobody meant to keep using (R-AK1).'
            );
        }
    }

    @IsTest
    static void aFirstGiftRuleMatchesOnlyTheFirstGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Acknowledgment_Rule__c welcome = AcknowledgmentTestData.buildRule(
                'Welcome',
                10,
                AcknowledgmentRuleService.CHANNEL_LETTER,
                null
            );
            welcome.First_Gift_Only__c = true;
            List<Acknowledgment_Rule__c> rules = new List<Acknowledgment_Rule__c>{ welcome };

            Id newDonor = fakeContactId(1);
            Id knownDonor = fakeContactId(2);
            Gift__c fromNew = giftOf(100);
            fromNew.Donor_Contact__c = newDonor;
            Gift__c fromKnown = giftOf(100);
            fromKnown.Donor_Contact__c = knownDonor;
            Set<String> alreadyGiving = new Set<String>{ String.valueOf(knownDonor) };

            Assert.isNotNull(
                AcknowledgmentRuleService.matchFor(fromNew, rules, alreadyGiving),
                'A donor with no earlier gift gets the welcome letter.'
            );
            Assert.isNull(
                AcknowledgmentRuleService.matchFor(fromKnown, rules, alreadyGiving),
                'A donor who has given before does not get a welcome letter for their fourth gift, ' +
                'which is the mistake R-AK2 exists to prevent.'
            );
        }
    }

    @IsTest
    static void refundsWriteOffsAndPendingGiftsAreOutsideTheFeature() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Gift__c refunded = giftOf(100);
            refunded.Status__c = 'Refunded';
            Gift__c pending = giftOf(100);
            pending.Status__c = 'Pending';
            Gift__c reversal = giftOf(-100);

            Assert.isFalse(
                AcknowledgmentRuleService.isAcknowledgeable(refunded),
                'A refunded gift is never thanked for (R-AK8).'
            );
            Assert.isFalse(
                AcknowledgmentRuleService.isAcknowledgeable(pending),
                'A pending gift is money that has not arrived, so there is nothing to thank for yet.'
            );
            Assert.isFalse(
                AcknowledgmentRuleService.isAcknowledgeable(reversal),
                'The negative gift that records a refund is not a gift to thank anybody for.'
            );
            Assert.isNull(
                AcknowledgmentRuleService.matchFor(reversal, ladder(), new Set<String>()),
                'And no rule matches it either, so no caller has to remember the exclusion twice.'
            );
        }
    }

    @IsTest
    static void anEarlierGiftIsFoundForEitherKindOfDonor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = AcknowledgmentTestData.insertDonor(
                'Ada',
                'Fitzgerald',
                'ada@example.org'
            );
            Account organization = GivingTestDataFactory.insertOrganization('Riverside Trust');
            GivingTestDataFactory.insertDefaultFund();

            Gift__c earlier = GivingTestDataFactory.buildGift(person.Id, 100);
            insert earlier;

            Gift__c second = GivingTestDataFactory.buildGift(person.Id, 200);
            Gift__c firstFromOrganization = GivingTestDataFactory.buildAccountGift(
                organization.Id,
                500
            );

            Test.startTest();
            Set<String> answered = AcknowledgmentRuleService.donorsWithEarlierGifts(
                new List<Gift__c>{ second, firstFromOrganization },
                new Set<Id>()
            );
            Test.stopTest();

            Assert.isTrue(
                answered.contains(String.valueOf(person.Id)),
                'Ada already gave 100, so her next gift is not a first gift.'
            );
            Assert.isFalse(
                answered.contains(String.valueOf(organization.Id)),
                'The Riverside Trust has never given, so its gift is a first gift, and the account ' +
                'donor path is answered by the same query as the contact one.'
            );
        }
    }
}
