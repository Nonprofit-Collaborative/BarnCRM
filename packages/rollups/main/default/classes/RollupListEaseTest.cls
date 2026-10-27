/**
 * The rollup list's plain sentence (U1) and its grouping by object (U12), from the
 * Apex side. Core holds no giving objects, so organizations count their child organizations
 * (`ParentId`) into Account fields, as the Builder's own tests do.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupSentence, ApexClass:RollupController')
private class RollupListEaseTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Integer fakeIds = 0;

    /** The object's describe without its child relationships. */
    private static Schema.DescribeSObjectResult describe(Schema.SObjectType objectType) {
        return objectType.getDescribe(SObjectDescribeOptions.DEFERRED);
    }

    /** An unsaved definition with an Id, so pairs can be compared without the save's checks. */
    private static Rollup_Definition__c rollup(String name, String targetField, Boolean active) {
        fakeIds++;
        String prefix = describe(Rollup_Definition__c.SObjectType).getKeyPrefix();
        return new Rollup_Definition__c(
            Id = Id.valueOf(prefix + String.valueOf(fakeIds).leftPad(12, '0')),
            Name = name,
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = targetField,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = active
        );
    }

    private static String nameIs(String value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Name',
                        'operator' => 'equals',
                        'value' => value
                    }
                }
            }
        );
    }

    private static String label(Schema.SObjectField field) {
        return field.getDescribe().getLabel();
    }

    // -------------------------------------------------------------------------------- sentence

    @IsTest
    static void aCountReadsAsASentenceByLabels() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            String sentence = RollupSentence.of(rollup('Children', 'Member_Count__c', true));

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_SentenceRecords,
                    new List<String>{
                        Label.Core_RollupEase_CalcCount,
                        describe(Account.SObjectType).getLabelPlural(),
                        label(Account.ParentId).removeEndIgnoreCase(' ID'),
                        label(Account.Member_Count__c),
                        describe(Account.SObjectType).getLabel()
                    }
                ),
                sentence,
                'U1: labels, never API names'
            );
        }
    }

    @IsTest
    static void aSumNamesItsFieldAndWhatLimitsTheRecords() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = rollup('Staff', 'AnnualRevenue', true);
            definition.Aggregate__c = 'SUM';
            definition.Source_Field__c = 'NumberOfEmployees';
            definition.Filter_JSON__c = nameIs('A');
            definition.Fiscal_Year_Aware__c = true;
            definition.Fiscal_Year_Offset__c = -1;
            definition.Row_Limit__c = 3;

            String sentence = RollupSentence.of(definition);

            System.Assert.isTrue(
                sentence.startsWith(
                    String.format(
                        Label.Core_RollupEase_CalcSum,
                        new List<String>{ label(Account.NumberOfEmployees) }
                    )
                ),
                sentence
            );
            System.Assert.isTrue(sentence.contains(Label.Core_RollupEase_SentenceConditions));
            System.Assert.isTrue(sentence.contains(Label.Core_RollupEase_SentenceLastYear));
            System.Assert.isTrue(
                sentence.contains(
                    String.format(
                        Label.Core_RollupEase_SentenceLimit,
                        new List<String>{ (3).format() }
                    )
                )
            );
        }
    }

    @IsTest
    static void aHouseholdPathAndAnUnknownObjectStillRead() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            String household = RollupSentence.linkOf(
                Account.SObjectType,
                'Primary_Contact__c > ' + RollupPath.TOKEN_HOUSEHOLD
            );
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_LinkHousehold,
                    new List<String>{ label(Account.Primary_Contact__c).removeEndIgnoreCase(' ID') }
                ),
                household
            );
            Rollup_Definition__c gone = rollup('Gone', 'Total__c', true);
            gone.Source_Object__c = 'Not_An_Object__c';
            gone.Target_Object__c = 'Not_An_Object__c';
            String sentence = RollupSentence.of(gone);
            System.Assert.isTrue(sentence.contains('Not_An_Object__c'), 'Named by its API name');
            System.Assert.isTrue(sentence.contains('Total__c'), sentence);
            System.Assert.areEqual('MEDIAN', RollupSentence.calculation('MEDIAN', 'Amount'));
        }
    }

    // ------------------------------------------------------------------------------------ page

    @IsTest
    static void thePageCarriesTheSentenceAndGroup() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c saved = rollup('Children', 'Member_Count__c', false);
            saved.Id = null;
            saved.Definition_Key__c = 'Test_Children';
            insert saved;

            RollupController.RollupView view = RollupController.getPage().rollups[0];

            System.Assert.areEqual(RollupSentence.of(saved), view.sentence);
            System.Assert.areEqual(
                describe(Account.SObjectType).getLabel(),
                view.targetObjectLabel
            );
        }
    }
}
