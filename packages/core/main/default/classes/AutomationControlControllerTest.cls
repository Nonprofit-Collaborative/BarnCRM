/**
 * The Automation page as two people see it: Maria, who has the Manage BarnCRM Settings
 * permission through the BarnCRM Admin role, and David, who has the BarnCRM Staff permission set and
 * does not.
 *
 * Both are built on a minimal profile with only a packaged permission set, so these tests prove
 * what the package grants rather than what a system administrator profile already allows.
 */
@IsTest
private class AutomationControlControllerTest {
    private static final String NAMING = 'Household_Naming';

    private static User barnCrmAdmin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static User staffOnly() {
        return TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
    }

    @IsTest
    static void thePageListsEveryAutomationAndThePauseState() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        TestDataFactory.pausedSettings(2);
        User maria = barnCrmAdmin();

        Test.startTest();
        AutomationControlController.AutomationPageView page;
        System.runAs(maria) {
            page = AutomationControlController.getPage();
        }
        Test.stopTest();

        Assert.isTrue(page.paused, 'The page knows automation is paused.');
        Assert.isNotNull(page.pausedUntil, 'And when it ends.');
        Assert.isTrue(page.canManage, 'Maria may change it.');
        Assert.areEqual(
            new List<Integer>{ 1, 2, 4, 8, 24 },
            page.pauseHourOptions,
            'The page offers the five lengths, in order.'
        );
        Assert.areEqual(1, page.automations.size(), 'One automation is listed.');
        Assert.areEqual(NAMING, page.automations[0].automationName, 'Named as it is registered.');
        Assert.isTrue(page.automations[0].enabled, 'And switched on.');
        Assert.isNotNull(page.automations[0].label, 'With a label Maria reads.');
    }

    @IsTest
    static void anAlwaysRunsAutomationIsListedOffDisabledAndRefused() {
        insert new Automation_Setting__c(
            Name = 'Gift: receipt lock',
            Automation_Name__c = 'Gift_Receipt_Lock',
            Description__c = 'Protects the receipt a donor is holding.',
            Enabled__c = true,
            Always_Runs__c = true,
            Is_Package_Default__c = true
        );
        AutomationControl.clearCache();
        User maria = barnCrmAdmin();

        Test.startTest();
        AutomationControlController.AutomationPageView page;
        System.runAs(maria) {
            page = AutomationControlController.getPage();
            try {
                AutomationControlController.setEnabled('Gift_Receipt_Lock', false);
                Assert.fail('The page must not be able to switch a rule off.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Automation_AlwaysRuns,
                    expected.getMessage(),
                    'The page shows Maria why the switch will not move.'
                );
            }
        }
        Test.stopTest();

        Assert.areEqual(1, page.automations.size(), 'The lock is still listed, not hidden.');
        Assert.isTrue(page.automations[0].alwaysRuns, 'Marked as one that always runs.');
        Assert.isFalse(
            page.automations[0].enabled,
            'Shown off, so nobody reads the page as saying it could be turned on.'
        );
    }

    @IsTest
    static void mariaPausesResumesAndSwitchesOneAutomationOff() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();

        Test.startTest();
        System.runAs(maria) {
            AutomationControlController.AutomationPageView paused = AutomationControlController.pauseAll(
                2
            );
            Assert.isTrue(paused.canManage, 'Maria may change this page.');
            Assert.isTrue(paused.paused, 'And has paused everything.');

            AutomationControlController.AutomationPageView running = AutomationControlController.resumeAll();
            Assert.isFalse(running.paused, 'And started it again.');

            AutomationControlController.AutomationPageView switched = AutomationControlController.setEnabled(
                NAMING,
                false
            );
            Assert.isFalse(switched.automations[0].enabled, 'And switched one automation off.');
        }
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Setting_Change__c],
            'Three changes, three audit rows.'
        );
    }

    @IsTest
    static void davidSeesThePageButCannotChangeIt() {
        TestDataFactory.insertAutomationSettings(new Map<String, Boolean>{ NAMING => true });
        User david = staffOnly();

        Test.startTest();
        System.runAs(david) {
            AutomationControlController.AutomationPageView page = AutomationControlController.getPage();
            Assert.isFalse(page.canManage, 'David may read the page but not change it.');
            Assert.areEqual(
                1,
                page.automations.size(),
                'And the read only page really loads: the Staff set grants read on the list.'
            );
            Assert.isTrue(page.automations[0].enabled, 'With the switch positions on it.');

            for (String action : new List<String>{ 'pause', 'resume', 'switch' }) {
                try {
                    if (action == 'pause') {
                        AutomationControlController.pauseAll(2);
                    } else if (action == 'resume') {
                        AutomationControlController.resumeAll();
                    } else {
                        AutomationControlController.setEnabled(NAMING, false);
                    }
                    Assert.fail('David should not be able to ' + action + '.');
                } catch (AuraHandledException expected) {
                    Assert.areEqual(
                        Label.Core_Automation_NoPermission,
                        expected.getMessage(),
                        'The message names the permission David needs.'
                    );
                }
            }
        }
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing was changed.');
    }

    @IsTest
    static void aPauseLengthThatIsNotOfferedIsRefused() {
        TestDataFactory.defaultSettings();
        User maria = barnCrmAdmin();

        Test.startTest();
        System.runAs(maria) {
            try {
                AutomationControlController.pauseAll(3);
                Assert.fail('Three hours is not one of the offered lengths.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Automation_PauseHoursInvalid,
                    expected.getMessage(),
                    'Maria is told which lengths she can choose.'
                );
            }
            try {
                AutomationControlController.setEnabled('   ', false);
                Assert.fail('An automation with no name should be refused.');
            } catch (AuraHandledException expected) {
                Assert.areEqual(
                    Label.Core_Automation_NameRequired,
                    expected.getMessage(),
                    'Maria is told to pick an automation.'
                );
            }
        }
        Test.stopTest();
    }
}
