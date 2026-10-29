/**
 * Starter templates (Rollup Builder ease of use U2, ADR-0136): nothing is added unless ticked,
 * each added rollup is switched off and passes the Builder's checks, and a rollup whose field is
 * missing or already filled is reported, not added.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupTemplates')
private class RollupTemplatesTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
        );
    }

    /**
     * Edit on one field for one person, from a permission set built in Setup. Written inside
     * `runAs` because a permission set is a setup object.
     */
    private static void grantEdit(User person, String objectName, String fieldName) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            String name = 'Rollup_Target_Edit_Test';
            PermissionSet granted = new PermissionSet(Name = name, Label = name);
            insert granted;
            insert new FieldPermissions(
                ParentId = granted.Id,
                SobjectType = objectName,
                Field = objectName + '.' + fieldName,
                PermissionsRead = true,
                PermissionsEdit = true
            );
            insert new PermissionSetAssignment(
                AssigneeId = person.Id,
                PermissionSetId = granted.Id
            );
        }
    }

    /** Whether Giving's gift and appeal objects are in this org. */
    private static Boolean givingInstalled() {
        return SettingsService.typeByName('Gift__c') != null &&
            SettingsService.typeByName('Appeal__c') != null;
    }

    @IsTest
    static void theStarterListsEveryRollupAndNoneIsAddedByOpeningIt() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupTemplates.Template> templates;
            System.runAs(maria()) {
                templates = RollupTemplates.getTemplates();
            }

            System.Assert.areEqual(1, templates.size());
            RollupTemplates.Template starter = templates[0];
            System.Assert.areEqual(RollupTemplates.NONPROFIT_STARTER, starter.key);
            System.Assert.areEqual(Label.Core_RollupEase_TplStarter, starter.name);
            System.Assert.areEqual(7, starter.items.size());
            for (RollupTemplates.Item item : starter.items) {
                System.Assert.isFalse(item.draft.active, item.key + ' is added switched off');
                System.Assert.isNotNull(item.sentence, item.key + ' says what it adds up');
                System.Assert.isNotNull(item.status, item.key + ' says whether it can be added');
                // The starter's fields are not shipped, so none can be added until it is made.
                System.Assert.isFalse(item.available, item.key);
                System.Assert.areEqual(givingInstalled(), item.canOpen, item.key);
                System.Assert.areEqual(givingInstalled(), item.needsField, item.key);
            }
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing added');
        }
    }

    @IsTest
    static void nothingIsAddedUnlessTicked() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.runAs(maria()) {
                System.Assert.isTrue(
                    RollupTemplates.addRollups(RollupTemplates.NONPROFIT_STARTER, null).isEmpty()
                );
                System.Assert.isTrue(
                    RollupTemplates.addRollups(
                            RollupTemplates.NONPROFIT_STARTER,
                            new List<String>()
                        )
                        .isEmpty()
                );
                System.Assert.isTrue(
                    RollupTemplates.addRollups('noSuchTemplate', new List<String>{ 'averageGift' })
                        .isEmpty()
                );
            }
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c]);
        }
    }

    @IsTest
    static void aTickedRollupWhoseFieldIsMissingIsReportedNotAdded() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupTemplates.Outcome> outcomes;
            System.runAs(maria()) {
                outcomes = RollupTemplates.addRollups(
                    RollupTemplates.NONPROFIT_STARTER,
                    new List<String>{ 'averageGift', 'appealDonors' }
                );
            }

            System.Assert.areEqual(2, outcomes.size());
            for (RollupTemplates.Outcome outcome : outcomes) {
                System.Assert.isFalse(outcome.added, outcome.name);
                System.Assert.isNotNull(outcome.message, outcome.name);
            }
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c]);
        }
    }

    @IsTest
    static void aRollupWithItsFieldIsAddedSwitchedOffAndOnlyOnce() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            if (!givingInstalled()) {
                return;
            }
            // A shipped field stands in for the one the administrator would create. Giving makes
            // it read only to everyone (ADR-0033), so Maria is given Edit on it, as the field
            // access step of Create a Field gives the administrator on a field they make. She
            // holds Giving Admin too, because a rollup may read only gift fields its author can
            // see (RollupDefinitionGuard, security review R-H1).
            RollupTemplates.Spec spec = RollupTemplates.nonprofitStarter()[0];
            spec.draft.targetField = 'Total_Giving__c';
            RollupTemplates.Outcome first;
            RollupTemplates.Outcome second;
            User maria = TestDataFactory.createUser(
                'Maria',
                new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin', 'Giving_Admin' }
            );
            grantEdit(maria, 'Contact', 'Total_Giving__c');
            System.runAs(maria) {
                first = RollupTemplates.add(spec, RollupTemplates.filledBy());
                second = RollupTemplates.add(spec, RollupTemplates.filledBy());
            }

            System.Assert.isTrue(first.added, first.message);
            System.Assert.areEqual(Label.Core_RollupEase_TplAdded, first.message);
            Rollup_Definition__c saved = [
                SELECT Name, Active__c, Mode__c, Aggregate__c, Target_Field__c
                FROM Rollup_Definition__c
            ];
            System.Assert.isFalse(saved.Active__c, 'Added switched off');
            System.Assert.areEqual(RollupService.MODE_BOTH, saved.Mode__c);
            System.Assert.areEqual('AVG', saved.Aggregate__c);
            System.Assert.areEqual(Label.Core_RollupEase_TplAverageGift, saved.Name);

            System.Assert.isFalse(second.added, 'A field is filled by one rollup');
            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_TplFilled, new List<String>{ saved.Name }),
                second.message
            );
            System.Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Definition__c]);
        }
    }

    @IsTest
    static void someoneWithoutTheSettingsPermissionSeesNoTemplates() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String listing;
            String adding;
            System.runAs(david) {
                try {
                    RollupTemplates.getTemplates();
                } catch (AuraHandledException refused) {
                    listing = refused.getMessage();
                }
                try {
                    RollupTemplates.addRollups(
                        RollupTemplates.NONPROFIT_STARTER,
                        new List<String>{ 'averageGift' }
                    );
                } catch (AuraHandledException refused) {
                    adding = refused.getMessage();
                }
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, listing);
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, adding);
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c]);
        }
    }
}
