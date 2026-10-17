/**
 * Maria finishes first-run setup: the edition and the features she ticked, in one step. David,
 * without Manage BarnCRM Settings, sees the window but cannot finish it (ADR-0124).
 */
@IsTest(testFor='ApexClass:FirstRunController')
private class FirstRunControllerTest {
    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            TestUsers.standardUserWith('Adeyemi', new List<String>{ 'BarnCRM_Read_Only' });
        }
    }

    private static User david() {
        return [
            SELECT Id
            FROM User
            WHERE LastName = 'Adeyemi'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
    }

    @IsTest
    static void aNewInstallNeedsSetupAndOffersEveryFeature() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            Test.stopTest();

            Assert.isTrue(state.needsSetup, 'No edition is saved yet');
            Assert.isTrue(state.canFinish, 'Maria may finish it');
            // Suggested only when Giving, NPSP or Nonprofit Cloud is there; otherwise null by
            // design, so the administrator picks (ADR-0072). The test holds in either org.
            if (ModuleDetectionService.isGivingPresent()) {
                Assert.areEqual(
                    ModuleDetectionService.SUITE_IMPACT,
                    state.recommendedSuite,
                    'The Nonprofit Edition is suggested when Giving is installed'
                );
            } else {
                Assert.isTrue(
                    state.recommendedSuite == null ||
                    state.recommendedSuite == ModuleDetectionService.SUITE_IMPACT,
                    'Without Giving an edition is suggested only for NPSP or Nonprofit Cloud: ' +
                    state.recommendedSuite
                );
            }
            Assert.areEqual(8, state.features.size(), 'Every feature is offered');
        }
    }

    @IsTest
    static void mariaFinishesWithTheFeaturesSheTicked() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.finish(
                ModuleDetectionService.SUITE_COMMUNITY,
                new List<String>{
                    FeatureSwitchService.DATA_MANAGER,
                    FeatureSwitchService.RELATIONSHIPS
                }
            );
            Test.stopTest();

            Assert.isFalse(state.needsSetup, 'The window does not show again');
            Assert.areEqual(
                ModuleDetectionService.SUITE_COMMUNITY,
                ModuleDetectionService.chosenSuite(),
                'The edition is saved'
            );
            Assert.isTrue(
                FeatureSwitchService.isOn(FeatureSwitchService.DATA_MANAGER),
                'A ticked feature is on'
            );
            Assert.isTrue(
                FeatureSwitchService.isOn(FeatureSwitchService.RELATIONSHIPS),
                'So is the other'
            );
            Assert.isFalse(
                FeatureSwitchService.isOn(FeatureSwitchService.AFFILIATIONS),
                'An unticked feature stays off'
            );
        }
    }

    @IsTest
    static void anEditionSavedInSetupStillAsksForFeaturesAndIsPreselected() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();
            SettingsService.saveSystemValue('Suite__c', ModuleDetectionService.SUITE_IMPACT);

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            Test.stopTest();

            Assert.isTrue(state.needsSetup, 'The features are still to be chosen');
            Assert.areEqual(
                ModuleDetectionService.SUITE_IMPACT,
                state.recommendedSuite,
                'The saved edition is pre-selected'
            );
        }
    }

    @IsTest
    static void finishingWithEveryFeatureUntickedDoesNotLoop() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.finish(
                ModuleDetectionService.SUITE_COMMUNITY,
                new List<String>()
            );
            Test.stopTest();

            Assert.isFalse(state.needsSetup, 'The window does not come back');
            Assert.areEqual(
                FeatureSwitchService.NONE_CHOSEN,
                SettingsService.getSettings().Features_Turned_On__c,
                'Setup is marked done with nothing on'
            );
            Assert.isTrue(FeatureSwitchService.featuresOn().isEmpty(), 'No feature is on');
            FeatureSwitchService.turnOn(FeatureSwitchService.RELATIONSHIPS);
            Assert.areEqual(
                FeatureSwitchService.RELATIONSHIPS,
                SettingsService.getSettings().Features_Turned_On__c,
                'A feature turned on later replaces the marker'
            );
        }
    }

    @IsTest
    static void anUpgradedOrgWithAnEditionNeverSeesTheWindow() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Suite__c', ModuleDetectionService.SUITE_COMMUNITY);

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            Test.stopTest();

            Assert.isFalse(state.needsSetup, 'Every feature is on and the edition is saved');
        }
    }

    @IsTest
    static void anUnknownFeatureKeepsNothing() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();
            Exception refused;

            Test.startTest();
            try {
                FirstRunController.finish(
                    ModuleDetectionService.SUITE_IMPACT,
                    new List<String>{ 'Rollups' }
                );
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_FirstRun_SaveError,
                refused.getMessage(),
                'Maria sees a message she can act on'
            );
        }
    }

    @IsTest
    static void anUnknownEditionIsRefused() {
        System.runAs(TestUsers.admin()) {
            Exception refused;

            Test.startTest();
            try {
                FirstRunController.finish('Enterprise', new List<String>());
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_SuiteChoice_UnknownSuiteError,
                refused.getMessage(),
                'Only the two editions are accepted'
            );
        }
    }

    @IsTest
    static void davidSeesTheWindowButCannotFinish() {
        System.runAs(david()) {
            Exception refused;

            Test.startTest();
            FirstRunController.FirstRunState state = FirstRunController.getState();
            try {
                FirstRunController.finish(
                    ModuleDetectionService.SUITE_COMMUNITY,
                    new List<String>()
                );
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.isTrue(state.needsSetup, 'The window shows for David too');
            Assert.isFalse(state.canFinish, 'He is told an administrator needs to finish');
            Assert.isTrue(state.features.isEmpty(), 'And is shown no choices');
            Assert.isNotNull(refused, 'Finishing needs Manage BarnCRM Settings');
        }
    }
}
