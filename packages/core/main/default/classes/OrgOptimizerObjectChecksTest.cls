/**
 * OrgOptimizerObjectChecks: objects near their custom field limit and record types no record
 * uses, over BarnCRM's own objects plus Account and Contact, read as the person.
 */
@IsTest(testFor='ApexClass:OrgOptimizerObjectChecks')
private class OrgOptimizerObjectChecksTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void listsAnObjectAtItsFieldLimitAndNotOneFarBelowIt() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerObjectChecks.fieldLimitOverride = 1;
            OrgOptimizerSetupController.Finding near = OrgOptimizerObjectChecks.nearFieldLimit();

            Assert.isFalse(near.failed, 'Describes are always readable.');
            Assert.isTrue(near.count >= 1, 'Account has more than one custom field.');
            Assert.isTrue(
                String.join(near.examples, '|')
                    .contains(
                        Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                    ),
                'Account is named: ' + near.examples
            );

            OrgOptimizerObjectChecks.fieldLimitOverride = 100000;
            Assert.areEqual(
                0,
                OrgOptimizerObjectChecks.nearFieldLimit().count,
                'Nothing is near an enormous limit.'
            );
        }
    }

    @IsTest
    static void listsAnAccountRecordTypeNoRecordUsesUntilOneDoes() {
        System.runAs(TestUsers.admin()) {
            OrgOptimizerSetupController.Finding before = OrgOptimizerObjectChecks.unusedRecordTypes();
            Assert.isFalse(before.failed, 'Record types are readable by an administrator.');
            Integer unusedBefore = before.count;
            Assert.isTrue(unusedBefore >= 1, 'With no records, the Household type is unused.');

            Database.insert(
                HouseholdTestDataFactory.newHousehold('The Used Household'),
                AccessLevel.SYSTEM_MODE
            );

            OrgOptimizerSetupController.Finding after = OrgOptimizerObjectChecks.unusedRecordTypes();
            Assert.areEqual(unusedBefore - 1, after.count, 'A household now uses its type.');
            Assert.isTrue(after.examples.size() <= 5, 'At most five examples.');
        }
    }
}
