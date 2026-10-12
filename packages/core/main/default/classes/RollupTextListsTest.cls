/**
 * COUNT_DISTINCT and the text lists of BarnCRM's own rollup engine (ADR-NEXT
 * `NEXT-barncrm-owns-its-rollup-engine.md`, decision 10; canonical model R-R15), on the instant
 * path and in the full recalculation. Any, None, First and Last are in `RollupOperationsTest`.
 *
 * Core holds no giving objects, so people (Contact) roll up to their organization (`AccountId`),
 * which is registered for instant totals by `Core_Rollups_Contact`, and to their household
 * through `{Household}`. These tests have not been executed: no Salesforce org exists in this
 * environment.
 */
@IsTest
private class RollupTextListsTest {
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
            Definition_Key__c = 'Test_Lists_' + aggregate + '_' + targetField,
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
                    NumberOfEmployees = 99,
                    Description = 'stale',
                    AccountNumber = 'stale'
                )
            );
        }
        insert created;
        return created;
    }

    /** Twenty people per organization, last names P00 to P19, titles Role 0 to Role 3 or blank. */
    private static List<Contact> people(List<Account> organizations) {
        List<Contact> created = new List<Contact>();
        for (Account organization : organizations) {
            for (Integer j = PEOPLE_EACH - 1; j >= 0; j--) {
                created.add(
                    new Contact(
                        LastName = 'P' + String.valueOf(j).leftPad(2, '0'),
                        Title = Math.mod(j, 5) == 4 ? null : 'Role ' + Math.mod(j, 4),
                        AccountId = organization.Id
                    )
                );
            }
        }
        return created;
    }

    /** Count distinct, a text list by semicolons, and each title once, on three attributes. */
    private static List<Rollup_Definition__c> everyList(String mode) {
        Rollup_Definition__c names = definition('TEXT_LIST', 'LastName', 'Description', mode);
        names.Delimiter__c = 'Semicolon';
        return new List<Rollup_Definition__c>{
            definition('COUNT_DISTINCT', 'Title', 'NumberOfEmployees', mode),
            names,
            definition('TEXT_LIST_DISTINCT', 'Title', 'AccountNumber', mode)
        };
    }

    private static Map<Id, Account> reread(List<Account> organizations) {
        return new Map<Id, Account>(
            [
                SELECT Id, NumberOfEmployees, Description, AccountNumber, Sample_Data_Key__c
                FROM Account
                WHERE Id IN :organizations
            ]
        );
    }

    /** The names are inserted P19 first, so the alphabetical order is the list's own work. */
    private static void assertEveryList(List<Account> organizations, String context) {
        List<String> names = new List<String>();
        for (Integer j = 0; j < PEOPLE_EACH; j++) {
            names.add('P' + String.valueOf(j).leftPad(2, '0'));
        }
        Map<Id, Account> stored = reread(organizations);
        for (Account organization : organizations) {
            Account result = stored.get(organization.Id);
            Assert.areEqual(
                4,
                result.NumberOfEmployees,
                context + ': four titles, blanks not counted'
            );
            Assert.areEqual(
                String.join(names, '; '),
                result.Description,
                context + ': every name, alphabetically'
            );
            Assert.areEqual(
                'Role 0, Role 1, Role 2, Role 3',
                result.AccountNumber,
                context + ': each title once, blanks left out, a comma by default'
            );
        }
    }

    // ------------------------------------------------------------------------------ instant path

    @IsTest
    static void twoHundredPeopleSavedAtOnceFillEveryListInTheSameSave() {
        insert everyList(RollupService.MODE_REAL_TIME);
        List<Account> organizations = organizations(ORGANIZATIONS);

        Test.startTest();
        insert people(organizations);
        Test.stopTest();

        assertEveryList(organizations, 'Instant');
    }

    @IsTest
    static void aDeleteAndAMoveToAnotherParentMoveTheValues() {
        insert everyList(RollupService.MODE_REAL_TIME);
        List<Account> organizations = organizations(2);
        Account leaving = organizations[0];
        Account joining = organizations[1];
        List<Contact> staff = new List<Contact>{
            new Contact(LastName = 'Ames', Title = 'Role 1', AccountId = leaving.Id),
            new Contact(LastName = 'Baker', Title = 'Role 2', AccountId = leaving.Id),
            new Contact(LastName = 'Cole', Title = 'Role 2', AccountId = leaving.Id)
        };
        insert staff;

        Test.startTest();
        TriggerHandler.clearRunClaims();
        staff[0].AccountId = joining.Id;
        update staff[0];
        Map<Id, Account> afterMove = reread(organizations);
        TriggerHandler.clearRunClaims();
        delete new List<Contact>{ staff[1], staff[2] };
        Test.stopTest();

        Assert.areEqual('Baker; Cole', afterMove.get(leaving.Id).Description, 'Ames moved out');
        Assert.areEqual('Role 2', afterMove.get(leaving.Id).AccountNumber, 'Role 2 listed once');
        Assert.areEqual(1, afterMove.get(leaving.Id).NumberOfEmployees, 'One title left');
        Assert.areEqual('Ames', afterMove.get(joining.Id).Description, 'Ames moved in');
        Account emptied = reread(organizations).get(leaving.Id);
        Assert.isNull(emptied.Description, 'A list of nobody is blank');
        Assert.isNull(emptied.AccountNumber, 'Each value once, of nobody, is blank');
        Assert.areEqual(0, emptied.NumberOfEmployees, 'No titles to count');
    }

    // --------------------------------------------------------------------- full recalculation

    @IsTest
    static void theFullRecalculationGivesTheSameListsAndASecondRunWritesNothing() {
        List<Rollup_Definition__c> definitions = everyList(RollupService.MODE_SCHEDULED);
        insert definitions;
        List<Account> organizations = organizations(ORGANIZATIONS);
        insert people(organizations);
        List<Account> empty = organizations(1);

        Test.startTest();
        RollupFullRecalcBatch.begin(definitions);
        Test.stopTest();

        assertEveryList(organizations, 'Full');
        Account cleared = reread(empty).get(empty[0].Id);
        Assert.areEqual(0, cleared.NumberOfEmployees, 'A parent with nobody is zeroed');
        Assert.isNull(cleared.Description, 'And its stale list is cleared');
        Set<Id> ids = new Map<Id, Account>(organizations).keySet();
        Assert.isTrue(
            RollupEngine.recalculate(ids, definitions).written.isEmpty(),
            'Recalculating again changes nothing, so writes nothing'
        );
    }

    // ------------------------------------------------------------------------------ edge cases

    @IsTest
    static void blanksAreLeftOutAndADelimiterInAValueIsKept() {
        List<Account> organizations = organizations(1);
        insert new List<Contact>{
            new Contact(LastName = 'A', Title = 'Chair, Board', AccountId = organizations[0].Id),
            new Contact(LastName = 'B', Title = null, AccountId = organizations[0].Id),
            new Contact(LastName = 'C', Title = 'Treasurer', AccountId = organizations[0].Id)
        };

        Test.startTest();
        RollupEngine.recalculate(
            new Set<Id>{ organizations[0].Id },
            new List<Rollup_Definition__c>{
                definition('TEXT_LIST', 'Title', 'Description', RollupService.MODE_SCHEDULED),
                definition(
                    'COUNT_DISTINCT',
                    'Title',
                    'NumberOfEmployees',
                    RollupService.MODE_SCHEDULED
                )
            }
        );
        Test.stopTest();

        Account stored = reread(organizations).get(organizations[0].Id);
        Assert.areEqual(
            'Chair, Board, Treasurer',
            stored.Description,
            'A comma by default, the blank left out, the comma in a value not escaped'
        );
        Assert.areEqual(2, stored.NumberOfEmployees, 'The blank is not a value');
    }

    @IsTest
    static void aLongListIsCutAtTheFieldLengthAndNotWrittenAgain() {
        List<Account> organizations = organizations(1);
        insert new List<Contact>{
            new Contact(LastName = 'Aaaaaaaaaa', AccountId = organizations[0].Id),
            new Contact(LastName = 'Bbbbbbbbbb', AccountId = organizations[0].Id),
            new Contact(LastName = 'Cccccccccc', AccountId = organizations[0].Id)
        };
        List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
            definition('TEXT_LIST', 'LastName', 'Sample_Data_Key__c', RollupService.MODE_SCHEDULED)
        };
        Set<Id> ids = new Set<Id>{ organizations[0].Id };

        Test.startTest();
        RollupEngine.Result firstRun = RollupEngine.recalculate(ids, definitions);
        RollupEngine.Result secondRun = RollupEngine.recalculate(ids, definitions);
        Test.stopTest();

        Assert.areEqual(
            'Aaaaaaaaaa, Bbbbbbbb',
            reread(organizations).get(organizations[0].Id).Sample_Data_Key__c,
            'Cut at the 20 characters the field holds'
        );
        Assert.isTrue(firstRun.failed.isEmpty(), 'The save did not fail on the length');
        Assert.isTrue(secondRun.written.isEmpty(), 'The cut value is the same on the next run');
    }

    @IsTest
    static void eachValueOnceIsExactAndFollowsTheOrderField() {
        List<Account> organizations = organizations(1);
        Id organizationId = organizations[0].Id;
        Date start = Date.newInstance(1970, 1, 1);
        insert new List<Contact>{
            new Contact(
                LastName = 'W',
                Title = 'Gold',
                Birthdate = start.addDays(1),
                AccountId = organizationId
            ),
            new Contact(
                LastName = 'X',
                Title = 'gold',
                Birthdate = start.addDays(2),
                AccountId = organizationId
            ),
            new Contact(
                LastName = 'Y',
                Title = 'Gold',
                Birthdate = start.addDays(3),
                AccountId = organizationId
            ),
            new Contact(
                LastName = 'Z',
                Title = 'Silver',
                Birthdate = start,
                AccountId = organizationId
            ),
            new Contact(
                LastName = 'V',
                Title = 'Bronze',
                Birthdate = null,
                AccountId = organizationId
            )
        };
        Rollup_Definition__c ordered = definition(
            'TEXT_LIST_DISTINCT',
            'Title',
            'Description',
            RollupService.MODE_SCHEDULED
        );
        ordered.Order_By_Field__c = 'Birthdate';
        ordered.Delimiter__c = 'New line';

        Test.startTest();
        RollupEngine.recalculate(
            new Set<Id>{ organizationId },
            new List<Rollup_Definition__c>{
                ordered,
                definition(
                    'COUNT_DISTINCT',
                    'Title',
                    'NumberOfEmployees',
                    RollupService.MODE_SCHEDULED
                )
            }
        );
        Test.stopTest();

        Account stored = reread(organizations).get(organizationId);
        Assert.areEqual(
            'Silver\nGold\ngold\nBronze',
            stored.Description,
            'By birthdate, a blank birthdate last, letter case counts'
        );
        Assert.areEqual(4, stored.NumberOfEmployees, 'Gold and gold are two values');
    }

    @IsTest
    static void aValueSharedByTwoHouseholdMembersIsCountedOnce() {
        Account household = new Account(
            Name = 'Rivera Household',
            RecordTypeId = HouseholdService.householdRecordTypeId()
        );
        insert household;
        insert new List<Contact>{
            new Contact(
                LastName = 'Rivera',
                FirstName = 'Ana',
                Title = 'Gold',
                AccountId = household.Id
            ),
            new Contact(
                LastName = 'Rivera',
                FirstName = 'Luis',
                Title = 'Gold',
                AccountId = household.Id
            )
        };
        Rollup_Definition__c titles = definition(
            'TEXT_LIST_DISTINCT',
            'Title',
            'AccountNumber',
            RollupService.MODE_SCHEDULED
        );
        titles.Relationship_Path__c = '{Household}';
        Rollup_Definition__c distinct = definition(
            'COUNT_DISTINCT',
            'Title',
            'NumberOfEmployees',
            RollupService.MODE_SCHEDULED
        );
        distinct.Relationship_Path__c = '{Household}';

        Test.startTest();
        RollupEngine.recalculate(
            new Set<Id>{ household.Id },
            new List<Rollup_Definition__c>{ titles, distinct }
        );
        Test.stopTest();

        Account stored = [
            SELECT AccountNumber, NumberOfEmployees
            FROM Account
            WHERE Id = :household.Id
        ];
        Assert.areEqual('Gold', stored.AccountNumber, 'Listed once across the two members');
        Assert.areEqual(1, stored.NumberOfEmployees, 'And counted once');
    }

    @IsTest
    static void aListWithNothingToReadIsRefusedAndTheDelimiterDefaultsToComma() {
        RollupPlanner.Plan plan = RollupPlanner.plan(
            Account.SObjectType,
            new List<Rollup_Definition__c>{
                definition('TEXT_LIST', null, 'Description', RollupService.MODE_BOTH),
                definition('TEXT_LIST', 'LastName', 'Description', RollupService.MODE_BOTH)
            }
        );

        Assert.areEqual(1, plan.refused.size(), 'The list with no source field');
        Assert.areEqual(RollupPlanner.KIND_LISTED, plan.queries[0].kind, 'Read as rows');
        Assert.isNull(plan.queries[0].orderBy, 'Alphabetical when no order is given');
        Assert.areEqual(', ', RollupPlanner.separatorFor(null), 'Comma by default');
        Assert.areEqual('; ', RollupPlanner.separatorFor('Semicolon'), 'Semicolon');
        Assert.areEqual('\n', RollupPlanner.separatorFor('New line'), 'A line break');
    }
}
