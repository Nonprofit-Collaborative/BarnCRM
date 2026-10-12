/**
 * The Acknowledgments page's Apex: the counts it shows and the refusals it reports.
 *
 * The page counts the queue by matching the rules rather than by reading a field, because that is
 * what a send does (R-AK3). These tests are the proof that the two agree.
 */
@IsTest
private class AcknowledgmentControllerTest {
    @TestSetup
    static void setUp() {
        GivingTestDataFactory.insertDefaultFund();
    }

    private static void twoRules() {
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
        insert new List<Acknowledgment_Rule__c>{ major, everything };
    }

    @IsTest
    static void theQueueIsCountedByWhatEachGiftWouldActuallyGet() {
        AcknowledgmentTestData.enable();
        twoRules();
        Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
        Account organization = GivingTestDataFactory.insertOrganization('Riverside Trust');
        insert new List<Gift__c>{
            GivingTestDataFactory.buildGift(donor.Id, 50),
            GivingTestDataFactory.buildGift(donor.Id, 75),
            GivingTestDataFactory.buildGift(donor.Id, 2500),
            GivingTestDataFactory.buildAccountGift(organization.Id, 200)
        };

        Test.startTest();
        AcknowledgmentController.PageView view = AcknowledgmentController.getPage();
        Test.stopTest();

        Assert.areEqual(
            2,
            view.emailQueue,
            'The two small gifts from a person with an address are the emails waiting.'
        );
        Assert.areEqual(1, view.letterQueue, 'The 2500 gift is a letter, by the major gift rule.');
        Assert.areEqual(
            1,
            view.withoutRecipient,
            'The organization gift matches the email rule but has no primary contact, so it is ' +
            'counted separately rather than quietly included in a send that would skip it.'
        );
        Assert.areEqual(
            0,
            view.unmatchedQueue,
            'Every waiting gift is matched, because the second rule has no criteria on it.'
        );
    }

    @IsTest
    static void aGiftNoRuleCoversIsCountedAsUnmatchedRatherThanHidden() {
        AcknowledgmentTestData.enable();
        Acknowledgment_Rule__c narrow = AcknowledgmentTestData.buildRule(
            'Major gifts only',
            10,
            AcknowledgmentRuleService.CHANNEL_LETTER,
            null
        );
        narrow.Minimum_Amount__c = 1000;
        insert narrow;
        Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
        insert GivingTestDataFactory.buildGift(donor.Id, 20);

        AcknowledgmentController.PageView view = AcknowledgmentController.getPage();

        Assert.areEqual(
            1,
            view.unmatchedQueue,
            'A gift waiting that no rule covers is shown, because otherwise an incomplete set of ' +
            'rules looks exactly like an empty queue.'
        );
        Assert.areEqual(0, view.emailQueue, 'And it is not counted as something about to be sent.');
    }

    @IsTest
    static void aRuleNamingATemplateThisOrgDoesNotHaveIsFlagged() {
        AcknowledgmentTestData.enable();
        Acknowledgment_Rule__c wrong = AcknowledgmentTestData.buildRule(
            'Typo',
            10,
            AcknowledgmentRuleService.CHANNEL_EMAIL,
            'BarnCRM: thank you for your gift'
        );
        insert wrong;

        AcknowledgmentController.PageView view = AcknowledgmentController.getPage();

        Assert.areEqual(1, view.rules.size(), 'The rule is listed.');
        Assert.isFalse(
            view.rules[0].templateFound,
            'A rule that names a template label rather than a developer name is flagged on the ' +
            'page, rather than failing silently on the night of the send.'
        );
    }

    @IsTest
    static void aUserWithoutThePermissionIsToldRatherThanRefusedSilently() {
        AcknowledgmentTestData.enable();
        twoRules();
        AcknowledgmentService.sendPermission = false;

        String message;
        try {
            AcknowledgmentController.sendEmailsNow();
        } catch (Exception refused) {
            message = refused.getMessage();
        }

        Assert.isNotNull(
            message,
            'A user without Send Acknowledgments gets a message naming the permission, not a ' +
            'button that appears to work.'
        );
        Assert.isFalse(
            AcknowledgmentController.getPage().canSend,
            'And the page knows to disable the button in the first place.'
        );
    }

    @IsTest
    static void thePageSaysWhenTheLastSendFinishedAndWhatItDid() {
        AcknowledgmentTestData.enable();

        Test.startTest();
        AcknowledgmentService.recordLastRun('Emailed thank yous: 12 sent, 0 did not go.');
        AcknowledgmentController.PageView view = AcknowledgmentController.getPage();
        Test.stopTest();

        Assert.areEqual(
            'Emailed thank yous: 12 sent, 0 did not go.',
            view.lastRunSummary,
            'A bare timestamp says the job woke up, not that it sent anything (R-AK12).'
        );
        Assert.isNotNull(view.lastRun, 'And the time it finished is kept beside it.');
    }
}
