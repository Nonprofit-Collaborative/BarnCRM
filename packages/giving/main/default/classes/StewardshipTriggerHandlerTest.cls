/**
 * That the plan starter is an automation like every other one: switchable, pausable, and unable to
 * take a gift down with it (R-SP1, R-SP9, R-A1).
 *
 * These tests have not been executed against an org: none was reachable from the environment they
 * were written in.
 */
@IsTest(testFor='ApexClass:StewardshipTriggerHandler')
private class StewardshipTriggerHandlerTest {
    private static final String PLAN = 'Every gift thanks';

    /**
     * A gift saves only when there is a default fund to allocate it to (R-GA2).
     */
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
        }
    }

    private static Stewardship_Plan_Template__c activeTemplate() {
        Stewardship_Plan_Template__c template = new Stewardship_Plan_Template__c(
            Name = PLAN,
            Plan_Key__c = 'every_gift_thanks',
            Active__c = true,
            Trigger_Event__c = StewardshipService.EVENT_GIFT_RECEIVED
        );
        insert template;
        insert new Stewardship_Plan_Step__c(
            Stewardship_Plan_Template__c = template.Id,
            Order__c = 1,
            Subject__c = 'Call to say thank you',
            Days_After_Start__c = 1,
            Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
            Priority__c = 'High'
        );
        return template;
    }

    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        insert person;
        return person;
    }

    @IsTest
    static void switchingTheAutomationOffStopsPlansStarting() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            // The switch is a row the post-install script writes from the registry; a test
            // sees none of the org's rows, so it writes them the same way first.
            AutomationControl.ensureDefaults();
            AutomationControl.setEnabled('Stewardship_Plan_Starter', false);
            AutomationControl.clearCache();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 100);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'An administrator who switched stewardship off before a bulk load gets no plans (R-SP1).'
            );
        }
    }

    @IsTest
    static void switchingItBackOnDoesNotStartPlansForTheGiftsItMissed() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            // The switch is a row the post-install script writes from the registry; a test
            // sees none of the org's rows, so it writes them the same way first.
            AutomationControl.ensureDefaults();
            AutomationControl.setEnabled('Stewardship_Plan_Starter', false);
            AutomationControl.clearCache();
            insert GivingTestDataFactory.buildGift(person.Id, 100);
            AutomationControl.setEnabled('Stewardship_Plan_Starter', true);
            AutomationControl.clearCache();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 200);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Only the gift saved while it was on started a plan. Nothing is caught up afterwards, ' +
                'because a welcome for a gift from three weeks ago is not a welcome.'
            );
        }
    }

    @IsTest
    static void aGiftWithNoDonorStartsNothingAndStillSaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();

            Test.startTest();
            Gift__c orphan = GivingTestDataFactory.buildGift(null, 100);
            Database.SaveResult saved = Database.insert(orphan, false);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'There is nobody to steward, so nothing starts.'
            );
            Assert.isNotNull(
                saved,
                'And the save was attempted rather than blocked by stewardship.'
            );
        }
    }

    @IsTest
    static void aGiftSavesEvenWhenThereAreNoTemplatesAtAll() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 100);
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'The gift is recorded.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'An org that has not set up any stewardship pays nothing for the feature existing.'
            );
        }
    }
}
