/**
 * Deleting a rollup with the choice to keep or clear what it wrote (Rollup Builder ease of use
 * U11, ADR-0136). Keeping is the default; clearing blanks the field in the background on the
 * records the rollup fills, and is refused while another active rollup fills the same field for
 * the same records.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupClearBatch, ApexClass:RollupController, ApexClass:RollupConflicts')
private class RollupDeleteEaseTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Rollup_Definition__c rollup(String name, String targetFilter, Boolean active) {
        return new Rollup_Definition__c(
            Name = name,
            Definition_Key__c = 'Test_' + name.replace(' ', '_'),
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Target_Filter_JSON__c = targetFilter,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = active
        );
    }

    private static String nameStartsWith(String value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Name',
                        'operator' => 'starts with',
                        'value' => value
                    }
                }
            }
        );
    }

    private static Integer clearJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = :RollupClearBatch.CLASS_NAME
        ];
    }

    @IsTest
    static void keepingTheValuesLeavesThemAndStartsNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Account org = new Account(Name = 'Alpha Org', Member_Count__c = 4);
            insert org;
            Rollup_Definition__c mine = rollup('Alpha count', null, true);
            insert mine;

            Test.startTest();
            RollupController.deleteRollup(mine.Id, false);
            Test.stopTest();

            System.Assert.areEqual(0, clearJobs(), 'Nothing is cleared');
            System.Assert.areEqual(
                4,
                [SELECT Member_Count__c FROM Account WHERE Id = :org.Id].Member_Count__c
            );
        }
    }

    @IsTest
    static void clearingBlanksTheFieldOnTheRecordsTheRollupFillsOnly() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Account alpha = new Account(Name = 'Alpha Org', Member_Count__c = 4);
            Account beta = new Account(Name = 'Beta Org', Member_Count__c = 7);
            insert new List<Account>{ alpha, beta };
            Rollup_Definition__c mine = rollup('Alpha count', nameStartsWith('Alpha'), true);
            insert mine;

            Test.startTest();
            RollupController.RollupPageView page = RollupController.deleteRollup(mine.Id, true);
            Test.stopTest();

            System.Assert.areEqual(0, page.rollups.size(), 'The rollup is gone');
            System.Assert.isNull(
                [SELECT Member_Count__c FROM Account WHERE Id = :alpha.Id].Member_Count__c,
                'A record the rollup filled is cleared'
            );
            System.Assert.areEqual(
                7,
                [SELECT Member_Count__c FROM Account WHERE Id = :beta.Id].Member_Count__c,
                'A record outside its conditions keeps its value'
            );
        }
    }

    @IsTest
    static void clearingIsRefusedWhileAnotherActiveRollupFillsTheField() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c mine = rollup('Old count', null, false);
            Rollup_Definition__c other = rollup('New count', null, true);
            insert new List<Rollup_Definition__c>{ mine, other };

            String message;
            try {
                RollupController.deleteRollup(mine.Id, true);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }

            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_ClearShared, new List<String>{ 'New count' }),
                message
            );
            System.Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Definition__c WHERE Id = :mine.Id],
                'Nothing is deleted'
            );
            System.Assert.areEqual(other.Id, RollupConflicts.sharerOf(mine).Id);
        }
    }

    @IsTest
    static void theClearReadsOnlyRecordsWithAValueThatMeetTheConditions() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            String query = new RollupClearBatch(
                    rollup('Alpha count', nameStartsWith('Alpha'), true)
                )
                .query();
            System.Assert.isTrue(
                query.startsWith('SELECT Id, Member_Count__c FROM Account WHERE ')
            );
            System.Assert.isTrue(query.contains('Member_Count__c != null'));
            System.Assert.isTrue(query.contains('Alpha'), 'Within the target conditions');

            Rollup_Definition__c gone = rollup('Gone', null, true);
            gone.Target_Field__c = 'No_Such_Field__c';
            System.Assert.areEqual(
                'SELECT Id FROM Rollup_Definition__c WHERE Id = null',
                new RollupClearBatch(gone).query(),
                'A field that is gone clears nothing'
            );
        }
    }
}
