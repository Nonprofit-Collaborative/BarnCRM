/**
 * Explain These Totals (Rollup Builder ease of use U5, ADR-0136): each total a rollup fills on a
 * record, with what it counts, the counted and left-out records, the last calculation, and, for
 * an administrator, what it would calculate now. Organizations count their child organizations
 * (`ParentId`), as in `RollupBuilderControllerTest`.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupExplainController')
private class RollupExplainTest {
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

    private static Rollup_Definition__c kidCount(String targetFilter, Boolean active) {
        return new Rollup_Definition__c(
            Name = 'Kid count',
            Definition_Key__c = 'Test_Kid_count',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Filter_JSON__c = nameStartsWith('Kid'),
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

    private static Account parent() {
        return parent(UserInfo.getUserId());
    }

    /** The organization and its children, owned by this person so they can open them. */
    private static Account parent(Id ownerId) {
        Account parent = new Account(Name = 'Parent Org', Member_Count__c = 2, OwnerId = ownerId);
        insert parent;
        insert new List<Account>{
            new Account(Name = 'Kid One', ParentId = parent.Id, OwnerId = ownerId),
            new Account(Name = 'Kid Two', ParentId = parent.Id, OwnerId = ownerId),
            new Account(Name = 'Other', ParentId = parent.Id, OwnerId = ownerId)
        };
        return parent;
    }

    @IsTest
    static void eachTotalIsExplainedWithItsCountsAndRecords() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupExplainController.Explanation> explained;
            Rollup_Definition__c rollup = kidCount(null, true);
            System.runAs(maria()) {
                Account org = parent();
                insert rollup;
                explained = RollupExplainController.explain(org.Id);
            }

            System.Assert.areEqual(1, explained.size());
            RollupExplainController.Explanation only = explained[0];
            System.Assert.areEqual(rollup.Id, only.definitionId);
            System.Assert.areEqual(
                Account.Member_Count__c.getDescribe().getLabel(),
                only.fieldLabel
            );
            System.Assert.areEqual((2).format(), only.value);
            System.Assert.areEqual(RollupSentence.of(rollup), only.sentence);
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_ExplainCounts,
                    new List<String>{ (2).format(), (3).format(), (1).format() }
                ),
                only.counts,
                'Two kids count, Other is left out'
            );
            System.Assert.areEqual(3, only.rows.rows.size());
            System.Assert.areEqual(Label.Core_RollupEase_ExplainNever, only.lastCalculated);
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_PreviewResult,
                    new List<String>{ (2).format(), (2).format() }
                ),
                only.calculatedNow,
                'An administrator sees what it would calculate now'
            );
        }
    }

    @IsTest
    static void aRollupThatDoesNotFillTheRecordOrIsOffIsNotListed() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupExplainController.Explanation> filtered;
            List<RollupExplainController.Explanation> off;
            System.runAs(maria()) {
                Account org = parent();
                Rollup_Definition__c betaOnly = kidCount(nameStartsWith('Beta'), true);
                insert betaOnly;
                filtered = RollupExplainController.explain(org.Id);
                betaOnly.Active__c = false;
                betaOnly.Target_Filter_JSON__c = null;
                update betaOnly;
                off = RollupExplainController.explain(org.Id);
            }

            System.Assert.isTrue(filtered.isEmpty(), 'Parent Org does not start with Beta');
            System.Assert.isTrue(off.isEmpty(), 'A rollup switched off is not explained');
        }
    }

    @IsTest
    static void someoneWhoIsNotAnAdministratorDoesNotSeeTheRecalculation() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User reader = TestDataFactory.createUser(
                'Rhea',
                new List<String>{ 'BarnCRM_Staff', 'Rollup_Builder_User' }
            );
            Account org;
            System.runAs(maria()) {
                // Rhea owns the records, so she can open them whatever the org's sharing.
                org = parent(reader.Id);
                insert kidCount(null, true);
            }
            List<RollupExplainController.Explanation> explained;
            System.runAs(reader) {
                explained = RollupExplainController.explain(org.Id);
            }

            System.Assert.areEqual(1, explained.size(), 'Rhea sees the total explained');
            System.Assert.areEqual((2).format(), explained[0].value);
            System.Assert.isNull(explained[0].calculatedNow, 'Only an administrator sees it');
        }
    }

    @IsTest
    static void aRecordThatIsGoneExplainsNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupExplainController.Explanation> explained;
            System.runAs(maria()) {
                insert kidCount(null, true);
                // Deleted after the page loaded: the record query finds nothing to read.
                Account gone = new Account(Name = 'Gone Org');
                insert gone;
                delete gone;
                explained = RollupExplainController.explain(gone.Id);
            }

            System.Assert.isTrue(explained.isEmpty(), 'Nothing to explain, and no error');
        }
    }

    @IsTest
    static void noRecordExplainsNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.isTrue(RollupExplainController.explain(null).isEmpty());
        }
    }
}
