/**
 * The operations slice of BarnCRM's own rollup engine (ADR-0082
 * `0082-barncrm-owns-its-rollup-engine.md`, decision 10; canonical model R-R15): ANY and NONE
 * into checkboxes and FIRST and LAST into text, on the instant path and in the full
 * recalculation. COUNT_DISTINCT and the text lists are in `RollupTextListsTest`.
 *
 * Core holds no giving objects, so people (Contact) roll up to their organization (`AccountId`),
 * which is registered for instant totals by `Core_Rollups_Contact`. These tests have not been
 * executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupPlanner, ApexClass:RollupEngine, ApexClass:RollupService')
private class RollupOperationsTest {
    /** Totals read right after each save: recalculated in the save (RollupTestSupport). */
    @TestSetup
    static void recalculateInTheSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
        }
    }

    private static final Integer ORGANIZATIONS = 10;
    private static final Integer PEOPLE_EACH = 20;

    private static Rollup_Definition__c definition(
        String aggregate,
        String sourceField,
        String targetField,
        String mode
    ) {
        return new Rollup_Definition__c(
            Name = aggregate + ' ' + targetField,
            Definition_Key__c = 'Test_Ops_' + aggregate + '_' + targetField,
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = aggregate,
            Source_Field__c = sourceField,
            Target_Object__c = 'Account',
            Target_Field__c = targetField,
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static String filter(String field, String operator, Object value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => field,
                        'operator' => operator,
                        'value' => value
                    }
                }
            }
        );
    }

    private static List<Account> organizations(Integer count) {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        List<Account> created = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            created.add(
                new Account(
                    Name = 'Organization ' + i,
                    RecordTypeId = organizationType,
                    // Targets are attributes BarnCRM Admin grants: a standard one such as Site
                    // may be hidden by the profile, and then the engine cannot write it.
                    Preferred_Name__c = 'stale',
                    Sample_Data_Key__c = 'stale',
                    Sample_Data__c = true,
                    Exclude_From_Greetings__c = false
                )
            );
        }
        insert created;
        return created;
    }

    /**
     * Twenty people per organization, born a day apart. Titles are Role 0 to Role 3, blank for
     * every fifth; only the even organizations have a Board member.
     */
    private static List<Contact> people(List<Account> organizations) {
        List<Contact> created = new List<Contact>();
        for (Integer i = 0; i < organizations.size(); i++) {
            for (Integer j = 0; j < PEOPLE_EACH; j++) {
                created.add(
                    new Contact(
                        LastName = 'P' + String.valueOf(j).leftPad(2, '0'),
                        Title = Math.mod(j, 5) == 4 ? null : 'Role ' + Math.mod(j, 4),
                        Department = Math.mod(i, 2) == 0 && j == 0 ? 'Board' : 'Staff',
                        Birthdate = Date.newInstance(1980, 1, 1).addDays(j),
                        AccountId = organizations[i].Id
                    )
                );
            }
        }
        return created;
    }

    /** Any and None into two checkboxes, First and Last into two text attributes. */
    private static List<Rollup_Definition__c> everyOperation(String mode) {
        Rollup_Definition__c anyRoleOne = definition('ANY', null, 'Sample_Data__c', mode);
        anyRoleOne.Filter_JSON__c = filter('Title', 'equals', 'Role 1');
        Rollup_Definition__c noBoard = definition('NONE', null, 'Exclude_From_Greetings__c', mode);
        noBoard.Filter_JSON__c = filter('Department', 'equals', 'Board');
        Rollup_Definition__c eldest = definition('FIRST', 'Title', 'Preferred_Name__c', mode);
        eldest.Order_By_Field__c = 'Birthdate';
        Rollup_Definition__c youngest = definition('LAST', 'LastName', 'Sample_Data_Key__c', mode);
        youngest.Order_By_Field__c = 'Birthdate';
        return new List<Rollup_Definition__c>{ anyRoleOne, noBoard, eldest, youngest };
    }

    private static Map<Id, Account> reread(List<Account> organizations) {
        return new Map<Id, Account>(
            [
                SELECT
                    Id,
                    Sample_Data__c,
                    Exclude_From_Greetings__c,
                    Preferred_Name__c,
                    Sample_Data_Key__c
                FROM Account
                WHERE Id IN :organizations
            ]
        );
    }

    private static void assertEveryOperation(List<Account> organizations, String context) {
        Map<Id, Account> stored = reread(organizations);
        for (Integer i = 0; i < organizations.size(); i++) {
            Account organization = stored.get(organizations[i].Id);
            Assert.isTrue(organization.Sample_Data__c, context + ': someone is Role 1');
            Assert.areEqual(
                Math.mod(i, 2) == 1,
                organization.Exclude_From_Greetings__c,
                context + ': None is checked only where nobody is on the Board'
            );
            Assert.areEqual(
                'Role 0',
                organization.Preferred_Name__c,
                context + ': the eldest person\'s title'
            );
            Assert.areEqual(
                'P19',
                organization.Sample_Data_Key__c,
                context + ': the youngest person\'s name'
            );
        }
    }

    // ------------------------------------------------------------------------------ instant path

    @IsTest
    static void twoHundredPeopleSavedAtOnceFillEveryOperationInTheSameSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert everyOperation(RollupService.MODE_REAL_TIME);
            List<Account> organizations = organizations(ORGANIZATIONS);

            Test.startTest();
            insert people(organizations);
            Test.stopTest();

            assertEveryOperation(organizations, 'Instant');
        }
    }

    @IsTest
    static void aDeleteAndAMoveToAnotherParentMoveTheAnswers() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert everyOperation(RollupService.MODE_REAL_TIME);
            List<Account> organizations = organizations(2);
            Account leaving = organizations[0];
            Account joining = organizations[1];
            Date born = Date.newInstance(1990, 1, 1);
            List<Contact> staff = new List<Contact>{
                new Contact(
                    LastName = 'Ames',
                    Title = 'Role 1',
                    Birthdate = born,
                    AccountId = leaving.Id
                ),
                new Contact(
                    LastName = 'Baker',
                    Title = 'Role 2',
                    Department = 'Board',
                    Birthdate = born.addDays(1),
                    AccountId = leaving.Id
                )
            };
            insert staff;

            Test.startTest();
            TriggerHandler.clearRunClaims();
            staff[0].AccountId = joining.Id;
            update staff[0];
            Map<Id, Account> afterMove = reread(organizations);
            TriggerHandler.clearRunClaims();
            delete staff[1];
            Test.stopTest();

            Assert.isFalse(afterMove.get(leaving.Id).Sample_Data__c, 'Role 1 moved out');
            Assert.areEqual(
                'Role 2',
                afterMove.get(leaving.Id).Preferred_Name__c,
                'Baker is now the eldest'
            );
            Assert.isTrue(afterMove.get(joining.Id).Sample_Data__c, 'And moved in');
            Assert.areEqual(
                'Ames',
                afterMove.get(joining.Id).Sample_Data_Key__c,
                'Ames is the youngest'
            );

            Account emptied = reread(organizations).get(leaving.Id);
            Assert.isFalse(emptied.Sample_Data__c, 'Any of nobody is unchecked');
            Assert.isTrue(emptied.Exclude_From_Greetings__c, 'None of nobody is checked');
            Assert.isNull(emptied.Preferred_Name__c, 'First of nobody is blank');
            Assert.isNull(emptied.Sample_Data_Key__c, 'Last of nobody is blank');
        }
    }

    // --------------------------------------------------------------------- full recalculation

    @IsTest
    static void theFullRecalculationGivesTheSameAnswersAndASecondRunWritesNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<Rollup_Definition__c> definitions = everyOperation(RollupService.MODE_SCHEDULED);
            insert definitions;
            List<Account> organizations = organizations(ORGANIZATIONS);
            insert people(organizations);
            List<Account> empty = organizations(1);
            Assert.areEqual(
                'stale',
                reread(organizations).get(organizations[0].Id).Preferred_Name__c,
                'Nothing ran on save'
            );

            Test.startTest();
            RollupFullRecalcBatch.begin(definitions);
            Test.stopTest();

            assertEveryOperation(organizations, 'Full');
            Account cleared = reread(empty).get(empty[0].Id);
            Assert.isFalse(cleared.Sample_Data__c, 'Any of nobody is unchecked');
            Assert.isTrue(cleared.Exclude_From_Greetings__c, 'None of nobody is checked');
            Assert.isNull(cleared.Preferred_Name__c, 'A stale First is cleared');
            Set<Id> ids = new Map<Id, Account>(organizations).keySet();
            Assert.isTrue(
                RollupEngine.recalculate(ids, definitions).written.isEmpty(),
                'Recalculating again changes nothing, so writes nothing'
            );
        }
    }

    // ------------------------------------------------------------------------------ edge cases

    @IsTest
    static void tiesGoToTheLowerRecordIdForFirstAndLast() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<Account> organizations = organizations(1);
            Date sameDay = Date.newInstance(1990, 5, 5);
            insert new List<Contact>{
                new Contact(
                    LastName = 'Alpha',
                    Birthdate = sameDay,
                    AccountId = organizations[0].Id
                ),
                new Contact(
                    LastName = 'Beta',
                    Birthdate = sameDay,
                    AccountId = organizations[0].Id
                ),
                new Contact(
                    LastName = 'Gamma',
                    Birthdate = sameDay,
                    AccountId = organizations[0].Id
                )
            };
            Rollup_Definition__c first = definition(
                'FIRST',
                'LastName',
                'Preferred_Name__c',
                RollupService.MODE_SCHEDULED
            );
            first.Order_By_Field__c = 'Birthdate';
            Rollup_Definition__c last = definition(
                'LAST',
                'LastName',
                'Sample_Data_Key__c',
                RollupService.MODE_SCHEDULED
            );
            last.Order_By_Field__c = 'Birthdate';
            String lowest = [SELECT LastName FROM Contact ORDER BY Id LIMIT 1].LastName;

            Test.startTest();
            RollupEngine.recalculate(
                new Set<Id>{ organizations[0].Id },
                new List<Rollup_Definition__c>{ first, last }
            );
            Test.stopTest();

            Account stored = reread(organizations).get(organizations[0].Id);
            Assert.areEqual(lowest, stored.Preferred_Name__c, 'First takes the lower Id on a tie');
            Assert.areEqual(lowest, stored.Sample_Data_Key__c, 'And so does Last');
        }
    }

    @IsTest
    static void aDateIsCopiedIntoTextPlainlyAndALongValueIsCut() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<Account> organizations = organizations(1);
            insert new List<Contact>{
                new Contact(
                    LastName = 'Abcdefghijklmnopqrstuvwxyz',
                    Birthdate = Date.newInstance(1970, 3, 1),
                    AccountId = organizations[0].Id
                )
            };
            Rollup_Definition__c birthday = definition(
                'FIRST',
                'Birthdate',
                'Preferred_Name__c',
                RollupService.MODE_SCHEDULED
            );
            birthday.Order_By_Field__c = 'Birthdate';
            Rollup_Definition__c name = definition(
                'LAST',
                'LastName',
                'Sample_Data_Key__c',
                RollupService.MODE_SCHEDULED
            );
            name.Order_By_Field__c = 'Birthdate';
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                birthday,
                name
            };
            Set<Id> ids = new Set<Id>{ organizations[0].Id };

            Test.startTest();
            RollupEngine.Result firstRun = RollupEngine.recalculate(ids, definitions);
            RollupEngine.Result secondRun = RollupEngine.recalculate(ids, definitions);
            Test.stopTest();

            Account stored = reread(organizations).get(organizations[0].Id);
            Assert.areEqual('1970-03-01', stored.Preferred_Name__c, 'A date, written plainly');
            Assert.areEqual(
                'Abcdefghijklmnopqrst',
                stored.Sample_Data_Key__c,
                'Cut at the 20 characters the field holds'
            );
            Assert.isTrue(firstRun.failed.isEmpty(), 'The save did not fail on the length');
            Assert.isTrue(secondRun.written.isEmpty(), 'The cut value is the same on the next run');
        }
    }

    // ------------------------------------------------------------------------------ the planner

    @IsTest
    static void eachOperationFillsOnlyTheTypesItSuits() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.isNull(
                RollupPlanner.targetTypeProblem('ANY', Schema.DisplayType.BOOLEAN),
                'Any into a checkbox'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorTargetNeedsCheckbox,
                RollupPlanner.targetTypeProblem('NONE', Schema.DisplayType.DOUBLE),
                'None into a number'
            );
            Assert.isNull(
                RollupPlanner.targetTypeProblem('TEXT_LIST', Schema.DisplayType.TEXTAREA),
                'A list into long text'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorTargetNeedsText,
                RollupPlanner.targetTypeProblem('TEXT_LIST_DISTINCT', Schema.DisplayType.DATE),
                'A list into a date'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorTargetNeedsNumber,
                RollupPlanner.targetTypeProblem('COUNT_DISTINCT', Schema.DisplayType.STRING),
                'Count distinct into text'
            );
            Assert.isNull(
                RollupPlanner.targetTypeProblem('LAST', Schema.DisplayType.STRING),
                'Last into text'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorTextTarget,
                RollupPlanner.targetTypeProblem('SUM', Schema.DisplayType.STRING),
                'A sum into text'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorCheckboxTarget,
                RollupPlanner.targetTypeProblem('COUNT', Schema.DisplayType.BOOLEAN),
                'A count into a checkbox'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorTargetType,
                RollupPlanner.targetTypeProblem('MAX', Schema.DisplayType.PICKLIST),
                'A maximum into a picklist'
            );
        }
    }

    @IsTest
    static void anIncompatibleTargetIsRefusedAloneAndAnyNeedsNoSourceField() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c anyIntoNumber = definition(
                'ANY',
                null,
                'NumberOfEmployees',
                RollupService.MODE_BOTH
            );
            Rollup_Definition__c firstWithNothing = definition(
                'FIRST',
                null,
                'Preferred_Name__c',
                RollupService.MODE_BOTH
            );
            firstWithNothing.Order_By_Field__c = 'Birthdate';
            Rollup_Definition__c anyone = definition(
                'ANY',
                null,
                'Sample_Data__c',
                RollupService.MODE_BOTH
            );

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{ anyIntoNumber, firstWithNothing, anyone }
            );

            Assert.areEqual(
                2,
                plan.refused.size(),
                'Any into a number, and First with nothing to read'
            );
            Assert.areEqual(
                1,
                plan.definitions.size(),
                'Any into a checkbox needs no source field'
            );
            Assert.isNull(plan.queries[0].measures[0].field, 'And reads none');
            Assert.isFalse(plan.queries[0].measures[0].asText, 'A checkbox is not text');
        }
    }
}
