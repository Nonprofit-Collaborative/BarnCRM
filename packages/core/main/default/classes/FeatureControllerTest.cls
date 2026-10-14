/**
 * Maria sees every Core feature in General and turns one on for good; David, without Manage
 * BarnCRM Settings, sees the list and cannot (ADR-NEXT).
 */
@IsTest(testFor='ApexClass:FeatureController')
private class FeatureControllerTest {
    @TestSetup
    static void createTestUsers() {
        System.runAs(TestUsers.admin()) {
            TestUsers.standardUserWith('Okonkwo', new List<String>{ 'BarnCRM_Read_Only' });
        }
    }

    @IsTest
    static void listsEveryFeatureWithItsNameAndState() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FeatureController.FeaturesModel model = FeatureController.getFeatures();
            Test.stopTest();

            Assert.isTrue(model.canEdit, 'Maria may turn features on');
            Assert.areEqual(8, model.features.size(), 'Three tools and five groups');
            for (FeatureController.FeatureRow row : model.features) {
                Assert.areNotEqual(row.key, row.name, 'Each feature has a label name: ' + row.key);
                Assert.isNotNull(row.description, 'And a description: ' + row.key);
                Assert.isFalse(row.isOn, 'A new install has every feature off');
            }
        }
    }

    @IsTest
    static void mariaTurnsAFeatureOn() {
        System.runAs(TestUsers.admin()) {
            FeatureSwitchService.markNewInstall();

            Test.startTest();
            FeatureController.FeaturesModel model = FeatureController.turnOn(
                FeatureSwitchService.AFFILIATIONS
            );
            Test.stopTest();

            for (FeatureController.FeatureRow row : model.features) {
                Assert.areEqual(
                    row.key == FeatureSwitchService.AFFILIATIONS,
                    row.isOn,
                    'Only Affiliations is on: ' + row.key
                );
            }
        }
    }

    @IsTest
    static void davidCannotTurnAFeatureOn() {
        User david = [
            SELECT Id
            FROM User
            WHERE LastName = 'Okonkwo'
            WITH SYSTEM_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        System.runAs(david) {
            Exception refused;

            Test.startTest();
            try {
                FeatureController.turnOn(FeatureSwitchService.AFFILIATIONS);
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.isNotNull(refused, 'Turning a feature on needs Manage BarnCRM Settings');
        }
    }

    @IsTest
    static void reportsAKeyThatIsNotAFeature() {
        System.runAs(TestUsers.admin()) {
            Exception refused;

            Test.startTest();
            try {
                FeatureController.turnOn('Rollups');
            } catch (AuraHandledException e) {
                refused = e;
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Core_Feature_SaveError,
                refused.getMessage(),
                'The page shows a message Maria can act on'
            );
        }
    }
}
