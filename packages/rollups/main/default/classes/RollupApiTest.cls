/**
 * Rollup Builder parity operations (ADR-0136): the Bypass Permission (R-R4a), the Recalculate
 * totals on this record Flow action and the global `RollupApi`. As in `RollupRecalcActionTest`,
 * organizations counting their child organizations (`ParentId`) stand in for an administrator's
 * own object: Account has no packaged rollup trigger, so only the calls under test count them.
 *
 * The test admin holds Manage BarnCRM Settings (BarnCRM Admin) and not Erase People, two custom
 * permissions Core ships, so neither the test nor the package needs a custom permission of its
 * own.
 */
@IsTest(
    testFor='ApexClass:RollupApi, ApexClass:RollupRecalcRecordAction, ApexClass:RollupService, ApexClass:RollupDefinitionValidationHandler'
)
private class RollupApiTest {
    private static final String HELD = 'Manage_BarnCRM_Settings';
    private static final String NOT_HELD = 'Erase_People';
    private static final String CHILD_COUNT_KEY = 'Core_Api_Child_Count';

    /** Totals read right after each call: recalculated in the transaction when there is room. */
    @TestSetup
    static void recalculateInTheSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
        }
    }

    private static Rollup_Definition__c childCount(String bypassPermission) {
        return new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = CHILD_COUNT_KEY,
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true,
            Bypass_Permission__c = bypassPermission
        );
    }

    /** A second rollup on the same records, nightly only, so a request by name can be told apart. */
    private static Rollup_Definition__c nightlyChildCount() {
        return new Rollup_Definition__c(
            Name = 'Child organizations (nightly)',
            Definition_Key__c = 'Core_Api_Child_Count_Nightly',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'AnnualRevenue',
            Mode__c = RollupService.MODE_SCHEDULED,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Account organization(String name, Id parentId) {
        return new Account(
            Name = name,
            ParentId = parentId,
            RecordTypeId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId()
        );
    }

    /** A parent with one child organization, neither counted yet. */
    private static Account parentWithOneChild() {
        Account parent = organization('Parent', null);
        insert parent;
        insert organization('Child', parent.Id);
        return parent;
    }

    private static List<Account> childrenOf(Id parentId) {
        return [SELECT Id, ParentId FROM Account WHERE ParentId = :parentId];
    }

    private static Account totalsOn(Id parentId) {
        return [SELECT NumberOfEmployees, AnnualRevenue FROM Account WHERE Id = :parentId];
    }

    private static Integer queued() {
        return [SELECT COUNT() FROM Rollup_Queue__c WITH SYSTEM_MODE];
    }

    private static RollupRecalcRecordAction.Request request(Id recordId, String rollup) {
        RollupRecalcRecordAction.Request request = new RollupRecalcRecordAction.Request();
        request.recordId = recordId;
        request.rollup = rollup;
        return request;
    }

    @IsTest
    static void aSaveByAHolderOfTheBypassPermissionNeitherRecalculatesNorQueues() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount(HELD);
            Account parent = parentWithOneChild();

            Test.startTest();
            RollupApi.recalculateChanges(childrenOf(parent.Id), null, false);
            Test.stopTest();

            System.Assert.isNull(totalsOn(parent.Id).NumberOfEmployees, 'The holder skipped it');
            System.Assert.areEqual(0, queued(), 'Nothing was queued for the holder either');
        }
    }

    @IsTest
    static void recalculateAndTheFullRunStillCoverABypassedRollup() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = childCount(HELD);
            insert definition;
            Account parent = parentWithOneChild();
            RollupApi.recalculate(new Set<Id>{ parent.Id });
            System.Assert.areEqual(
                1,
                totalsOn(parent.Id).NumberOfEmployees,
                'Asking for the record is not a save, so it is never bypassed'
            );

            insert organization('Second child', parent.Id);
            Test.startTest();
            RollupService.recalculate(definition.Id);
            Test.stopTest();

            System.Assert.areEqual(
                2,
                totalsOn(parent.Id).NumberOfEmployees,
                'Recalculate still covers it'
            );
        }
    }

    @IsTest
    static void aPermissionTheUserDoesNotHoldBypassesNobody() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount(NOT_HELD);
            Account parent = parentWithOneChild();

            Test.startTest();
            RollupApi.recalculateChanges(childrenOf(parent.Id), null, false);
            Test.stopTest();

            System.Assert.areEqual(1, totalsOn(parent.Id).NumberOfEmployees, 'Counted as usual');
        }
    }

    @IsTest
    static void aBypassPermissionThatDoesNotExistIsRefusedOnSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = childCount(null);
            insert definition;

            definition.Bypass_Permission__c = 'No_Such_Permission_Here';
            Database.SaveResult renamed = Database.update(definition, false);
            Database.SaveResult prefixed = Database.insert(
                new Rollup_Definition__c(
                    Name = 'Prefixed',
                    Definition_Key__c = 'Core_Api_Prefixed',
                    Source_Object__c = 'Account',
                    Target_Object__c = 'Account',
                    Relationship_Path__c = 'ParentId',
                    Aggregate__c = 'COUNT',
                    Target_Field__c = 'AnnualRevenue',
                    Mode__c = RollupService.MODE_BOTH,
                    Active__c = false,
                    Bypass_Permission__c = 'nosuchprefix__' + HELD
                ),
                false
            );

            System.Assert.isFalse(renamed.isSuccess(), 'An unknown name is refused');
            System.Assert.isTrue(
                renamed.getErrors()[0].getMessage().contains('No_Such_Permission_Here'),
                'The message names it'
            );
            System.Assert.isFalse(prefixed.isSuccess(), 'A prefix that matches nothing is refused');
        }
    }

    @IsTest
    static void theBuilderSavesAndReadsTheBypassPermission() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c definition = childCount(' ' + NOT_HELD + ' ');
            insert definition;

            RollupBuilderController.Draft draft = RollupBuilderController.getDraft(definition.Id);

            System.Assert.areEqual(NOT_HELD, draft.bypassPermission.trim(), 'Read back');
        }
    }

    @IsTest
    static void theRecordActionRecalculatesEveryRollupOrTheOneNamed() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new List<Rollup_Definition__c>{ childCount(null), nightlyChildCount() };
            Account parent = parentWithOneChild();

            RollupRecalcRecordAction.recalculate(
                new List<RollupRecalcRecordAction.Request>{ request(parent.Id, CHILD_COUNT_KEY) }
            );
            Account named = totalsOn(parent.Id);
            System.Assert.areEqual(1, named.NumberOfEmployees, 'The named rollup ran');
            System.Assert.isNull(named.AnnualRevenue, 'The other one did not');

            Test.startTest();
            RollupRecalcRecordAction.recalculate(
                new List<RollupRecalcRecordAction.Request>{ request(parent.Id, null), null }
            );
            Test.stopTest();

            System.Assert.areEqual(
                1,
                totalsOn(parent.Id).AnnualRevenue,
                'Every active rollup on the record ran, the nightly one too'
            );
        }
    }

    @IsTest
    static void aRollupNameThatMatchesNothingRecalculatesNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount(null);
            Account parent = parentWithOneChild();

            Test.startTest();
            RollupRecalcRecordAction.recalculate(
                new List<RollupRecalcRecordAction.Request>{ request(parent.Id, 'No such rollup') }
            );
            Test.stopTest();

            System.Assert.isNull(totalsOn(parent.Id).NumberOfEmployees, 'Nothing ran');
            System.Assert.areEqual(0, queued(), 'Nothing was queued');
        }
    }

    @IsTest
    static void aRequestTooLargeForTheTransactionIsQueued() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount(null);
            Account parent = parentWithOneChild();
            RollupService.instantLimit = 0;

            Test.startTest();
            RollupApi.recalculate(new Set<Id>{ parent.Id });
            System.Assert.areEqual(1, queued(), 'Queued instead of recalculated now');
            Test.stopTest();
        }
    }

    @IsTest
    static void aDeleteThroughTheApiQueuesItsTotals() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert childCount(null);
            Account parent = parentWithOneChild();

            Test.startTest();
            RollupApi.recalculateChanges(childrenOf(parent.Id), new Map<Id, SObject>(), true);
            System.Assert.areEqual(1, queued(), 'Queued for after the delete');
            RollupApi.recalculateChanges(null, null, null);
            RollupApi.recalculate(null);
            Test.stopTest();
        }
    }
}
