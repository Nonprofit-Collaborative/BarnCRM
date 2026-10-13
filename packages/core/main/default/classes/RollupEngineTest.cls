/**
 * BarnCRM's own rollup engine: planner, calculator and changed-only writer (rollup proposal, slice
 * S5). Core holds no giving objects, so these tests roll organizations up to their parent account
 * (`ParentId`) and people up to households, which exercises the same code the giving totals run.
 * The giving totals themselves are judged by the regression suite in Giving.
 */
@IsTest(testFor='ApexClass:RollupEngine')
private class RollupEngineTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id organizationType() {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
    }

    private static Account organization(String name, Id parentId) {
        return new Account(Name = name, RecordTypeId = organizationType(), ParentId = parentId);
    }

    private static Rollup_Definition__c definition(
        String sourceObject,
        String path,
        String aggregate,
        String sourceField,
        String targetObject,
        String targetField
    ) {
        return new Rollup_Definition__c(
            Name = aggregate + ' ' + targetField,
            Definition_Key__c = 'Test_' + aggregate + '_' + targetField,
            Source_Object__c = sourceObject,
            Relationship_Path__c = path,
            Aggregate__c = aggregate,
            Source_Field__c = sourceField,
            Target_Object__c = targetObject,
            Target_Field__c = targetField,
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static Rollup_Definition__c fromChildren(
        String aggregate,
        String sourceField,
        String targetField
    ) {
        return definition('Account', 'ParentId', aggregate, sourceField, 'Account', targetField);
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

    private static Account reread(Id accountId) {
        return [
            SELECT Id, Member_Count__c, NumberOfEmployees, Anniversary__c, AnnualRevenue
            FROM Account
            WHERE Id = :accountId
        ];
    }

    // ------------------------------------------------------------------------------- calculator

    @IsTest
    static void everyAggregateIsRecomputedAndAnEmptyParentIsZeroed() {
        System.runAs(TestUsers.admin()) {
            Account busy = organization('Busy Parent', null);
            Account empty = organization('Empty Parent', null);
            empty.Member_Count__c = 99;
            empty.Anniversary__c = Date.newInstance(2001, 1, 1);
            insert new List<Account>{ busy, empty };
            insert new List<Account>{
                new Account(
                    Name = 'Child A',
                    RecordTypeId = organizationType(),
                    ParentId = busy.Id,
                    NumberOfEmployees = 10,
                    AnnualRevenue = 100,
                    Anniversary__c = Date.newInstance(2020, 3, 1)
                ),
                new Account(
                    Name = 'Child B',
                    RecordTypeId = organizationType(),
                    ParentId = busy.Id,
                    NumberOfEmployees = 20,
                    AnnualRevenue = 200,
                    Anniversary__c = Date.newInstance(2022, 6, 1)
                ),
                new Account(
                    Name = 'Child C',
                    RecordTypeId = organizationType(),
                    ParentId = busy.Id,
                    NumberOfEmployees = 30,
                    AnnualRevenue = 300,
                    Anniversary__c = Date.newInstance(2019, 1, 1)
                )
            };
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                fromChildren('SUM', 'NumberOfEmployees', 'Member_Count__c'),
                fromChildren('COUNT', null, 'NumberOfEmployees'),
                fromChildren('MAX', 'Anniversary__c', 'Anniversary__c'),
                fromChildren('AVG', 'AnnualRevenue', 'AnnualRevenue')
            };

            Test.startTest();
            RollupEngine.Result result = RollupEngine.recalculate(
                new Set<Id>{ busy.Id, empty.Id },
                definitions
            );
            Test.stopTest();

            Account parent = reread(busy.Id);
            Assert.areEqual(60, parent.Member_Count__c, 'The sum of the children');
            Assert.areEqual(3, parent.NumberOfEmployees, 'The count of the children');
            Assert.areEqual(Date.newInstance(2022, 6, 1), parent.Anniversary__c, 'The latest date');
            Assert.areEqual(200, parent.AnnualRevenue, 'The average');
            Account zeroed = reread(empty.Id);
            Assert.areEqual(0, zeroed.Member_Count__c, 'A sum of nothing is zero, not left behind');
            Assert.areEqual(0, zeroed.NumberOfEmployees, 'A count of nothing is zero');
            Assert.isNull(zeroed.Anniversary__c, 'A maximum of nothing is blank');
            Assert.areEqual(4, result.ran.size(), 'Every definition ran');
            Assert.areEqual(2, result.written.size(), 'Both parents changed');
        }
    }

    @IsTest
    static void aFilterLimitsTheRowsCounted() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert new List<Account>{
                new Account(
                    Name = 'Small',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    NumberOfEmployees = 5
                ),
                new Account(
                    Name = 'Large',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    NumberOfEmployees = 50
                )
            };
            Rollup_Definition__c large = fromChildren(
                'SUM',
                'NumberOfEmployees',
                'Member_Count__c'
            );
            large.Filter_JSON__c = filter('NumberOfEmployees', 'greater than', 10);

            RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                new List<Rollup_Definition__c>{ large }
            );

            Assert.areEqual(50, reread(parent.Id).Member_Count__c, 'Only the large child');
        }
    }

    @IsTest
    static void firstAndLastFollowTheOrderAttribute() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert new List<Account>{
                new Account(
                    Name = 'Older',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    NumberOfEmployees = 7,
                    Anniversary__c = Date.newInstance(2010, 1, 1)
                ),
                new Account(
                    Name = 'Newer',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    NumberOfEmployees = 9,
                    Anniversary__c = Date.newInstance(2020, 1, 1)
                ),
                new Account(
                    Name = 'Undated',
                    RecordTypeId = organizationType(),
                    ParentId = parent.Id,
                    NumberOfEmployees = 1
                )
            };
            Rollup_Definition__c first = fromChildren(
                'FIRST',
                'NumberOfEmployees',
                'Member_Count__c'
            );
            first.Order_By_Field__c = 'Anniversary__c';
            Rollup_Definition__c last = fromChildren(
                'LAST',
                'NumberOfEmployees',
                'NumberOfEmployees'
            );
            last.Order_By_Field__c = 'Anniversary__c';

            RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                new List<Rollup_Definition__c>{ first, last }
            );

            Account reread = reread(parent.Id);
            Assert.areEqual(7, reread.Member_Count__c, 'The earliest by date');
            Assert.areEqual(
                9,
                reread.NumberOfEmployees,
                'The latest by date; undated rows never win'
            );
        }
    }

    // ---------------------------------------------------------------------------- target filters

    /**
     * Two definitions write one attribute for different records (R-R8, bug 2). Each writes only
     * the records its target filter admits, in either order.
     */
    @IsTest
    static void targetFiltersKeepTwoDefinitionsApart() {
        System.runAs(TestUsers.admin()) {
            Account north = organization('North Parent', null);
            Account south = organization('South Parent', null);
            insert new List<Account>{ north, south };
            insert new List<Account>{
                new Account(
                    Name = 'N1',
                    RecordTypeId = organizationType(),
                    ParentId = north.Id,
                    NumberOfEmployees = 40
                ),
                new Account(
                    Name = 'N2',
                    RecordTypeId = organizationType(),
                    ParentId = north.Id,
                    NumberOfEmployees = 60
                ),
                new Account(
                    Name = 'S1',
                    RecordTypeId = organizationType(),
                    ParentId = south.Id,
                    NumberOfEmployees = 5
                )
            };
            Rollup_Definition__c sum = fromChildren('SUM', 'NumberOfEmployees', 'Member_Count__c');
            sum.Target_Filter_JSON__c = filter('Name', 'starts with', 'North');
            Rollup_Definition__c count = fromChildren('COUNT', null, 'Member_Count__c');
            count.Definition_Key__c = 'Test_Count_South';
            count.Target_Filter_JSON__c = filter('Name', 'starts with', 'South');
            Set<Id> both = new Set<Id>{ north.Id, south.Id };

            RollupEngine.recalculate(both, new List<Rollup_Definition__c>{ sum, count });
            Assert.areEqual(100, reread(north.Id).Member_Count__c, 'North: the sum');
            Assert.areEqual(1, reread(south.Id).Member_Count__c, 'South: the count');

            RollupEngine.recalculate(both, new List<Rollup_Definition__c>{ count, sum });
            Assert.areEqual(100, reread(north.Id).Member_Count__c, 'Order does not matter');
            Assert.areEqual(1, reread(south.Id).Member_Count__c, 'Order does not matter');
        }
    }

    // ----------------------------------------------------------------------------------- writer

    @IsTest
    static void aSecondRunWritesNothing() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert organization('Child', parent.Id);
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                fromChildren('COUNT', null, 'Member_Count__c')
            };

            RollupEngine.Result first = RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                definitions
            );
            RollupEngine.Result second = RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                definitions
            );

            Assert.areEqual(1, first.written.size(), 'The first run wrote the count');
            Assert.areEqual(0, second.written.size(), 'Nothing changed, so nothing is saved');
        }
    }

    // ---------------------------------------------------------------------------------- refusal

    @IsTest
    static void aBrokenDefinitionIsRefusedAndTheOthersRun() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert organization('Child', parent.Id);
            Rollup_Definition__c good = fromChildren('COUNT', null, 'Member_Count__c');
            Rollup_Definition__c checkbox = fromChildren('COUNT', null, 'Custom_Name__c');
            Rollup_Definition__c missing = fromChildren('COUNT', null, 'No_Such_Field__c');
            Rollup_Definition__c midToken = fromChildren('COUNT', null, 'NumberOfEmployees');
            midToken.Relationship_Path__c = '{Household} > ParentId';
            Rollup_Definition__c badFilter = fromChildren('COUNT', null, 'NumberOfEmployees');
            badFilter.Definition_Key__c = 'Test_Bad_Filter';
            badFilter.Filter_JSON__c = filter('No_Such_Field__c', 'equals', 1);

            RollupEngine.Result result = RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                new List<Rollup_Definition__c>{ good, checkbox, missing, midToken, badFilter }
            );

            Assert.areEqual(1, reread(parent.Id).Member_Count__c, 'The good one still ran');
            Assert.areEqual(1, result.ran.size(), 'Only the good one ran');
            Assert.areEqual(
                4,
                result.refused.size(),
                'Checkbox, missing, token, unqueryable filter'
            );
        }
    }

    @IsTest
    static void theTargetEntryPointRunsTheActiveDefinitions() {
        System.runAs(TestUsers.admin()) {
            Account parent = organization('Parent', null);
            insert parent;
            insert organization('Child', parent.Id);
            Rollup_Definition__c active = fromChildren('COUNT', null, 'Member_Count__c');
            Rollup_Definition__c inactive = fromChildren(
                'SUM',
                'NumberOfEmployees',
                'NumberOfEmployees'
            );
            inactive.Active__c = false;
            insert new List<Rollup_Definition__c>{ active, inactive };

            RollupEngine.Result result = RollupEngine.recalculate(
                new Set<Id>{ parent.Id },
                Account.SObjectType
            );

            Assert.areEqual(1, result.ran.size(), 'Only the active definition');
            Assert.areEqual(1, reread(parent.Id).Member_Count__c, 'Written');
        }
    }

    // ------------------------------------------------------------------------- household tokens

    /** Contacts reporting to Ana count towards Ana's household: `ReportsToId > {Household}`. */
    private static void assertHouseholdToken(Account household, Contact ana) {
        insert new List<Contact>{
            new Contact(
                LastName = 'Older',
                ReportsToId = ana.Id,
                Birthdate = Date.newInstance(1980, 1, 1)
            ),
            new Contact(
                LastName = 'Younger',
                ReportsToId = ana.Id,
                Birthdate = Date.newInstance(1990, 5, 5)
            )
        };
        Rollup_Definition__c latest = definition(
            'Contact',
            'ReportsToId > {Household}',
            'MAX',
            'Birthdate',
            'Account',
            'Anniversary__c'
        );
        latest.Target_Filter_JSON__c = filter('RecordType.DeveloperName', 'equals', 'Household');

        Test.startTest();
        RollupEngine.recalculate(
            new Set<Id>{ household.Id },
            new List<Rollup_Definition__c>{ latest }
        );
        Test.stopTest();

        Assert.areEqual(
            Date.newInstance(1990, 5, 5),
            reread(household.Id).Anniversary__c,
            'Reached through Ana, resolved to her household'
        );
    }

    @IsTest
    static void aHouseholdTokenResolvesInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Nolan Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Nolan');
            ana.AccountId = household.Id;
            insert ana;
            assertHouseholdToken(household, ana);
        }
    }

    @IsTest
    static void aHouseholdTokenResolvesInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Garcia');
            insert ana;
            insert new Household_Member__c(
                Household__c = household.Id,
                Contact__c = ana.Id,
                Is_Primary__c = true
            );
            assertHouseholdToken(household, ana);
        }
    }

    @IsTest
    static void theMembersTokenReachesEveryMember() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Nolan Family');
            insert household;
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Nolan');
            Contact luis = HouseholdTestDataFactory.newContact('Luis', 'Nolan');
            ana.AccountId = household.Id;
            luis.AccountId = household.Id;
            insert new List<Contact>{ ana, luis };
            insert new Contact(
                LastName = 'Report',
                ReportsToId = ana.Id,
                Birthdate = Date.newInstance(1985, 2, 2)
            );
            Rollup_Definition__c members = definition(
                'Contact',
                'ReportsToId > {HouseholdMembers}',
                'MIN',
                'Birthdate',
                'Contact',
                'Birthdate'
            );

            RollupEngine.recalculate(
                new Set<Id>{ luis.Id },
                new List<Rollup_Definition__c>{ members }
            );

            Assert.areEqual(
                Date.newInstance(1985, 2, 2),
                [SELECT Birthdate FROM Contact WHERE Id = :luis.Id].Birthdate,
                'Luis shares in what reached Ana, his household member'
            );
        }
    }

    // -------------------------------------------------------------------------------- bulk, skew

    @IsTest
    static void twoHundredParentsInOnePass() {
        System.runAs(TestUsers.admin()) {
            List<Account> parents = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                parents.add(organization('Parent ' + i, null));
            }
            insert parents;
            List<Account> children = new List<Account>();
            for (Account parent : parents) {
                children.add(
                    new Account(
                        Name = 'C1',
                        RecordTypeId = organizationType(),
                        ParentId = parent.Id,
                        NumberOfEmployees = 3
                    )
                );
                children.add(
                    new Account(
                        Name = 'C2',
                        RecordTypeId = organizationType(),
                        ParentId = parent.Id,
                        NumberOfEmployees = 4
                    )
                );
            }
            insert children;
            List<Rollup_Definition__c> definitions = new List<Rollup_Definition__c>{
                fromChildren('SUM', 'NumberOfEmployees', 'Member_Count__c'),
                fromChildren('COUNT', null, 'NumberOfEmployees')
            };

            Test.startTest();
            RollupEngine.Result result = RollupEngine.recalculate(
                new Map<Id, Account>(parents).keySet(),
                definitions
            );
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(200, result.written.size(), 'Every parent written');
            // Two engine queries; the rest is account automation running on the one save.
            Assert.isTrue(queries < 50, 'Not one query per parent: ' + queries);
            for (Account parent : [
                SELECT Member_Count__c, NumberOfEmployees
                FROM Account
                WHERE Id IN :parents
            ]) {
                Assert.areEqual(7, parent.Member_Count__c, 'Each parent\'s sum');
                Assert.areEqual(2, parent.NumberOfEmployees, 'Each parent\'s count');
            }
        }
    }

    /** One parent with 5,000 children: aggregated in the query, not read row by row. */
    @IsTest
    static void oneParentWithFiveThousandChildren() {
        System.runAs(TestUsers.admin()) {
            Account anonymous = organization('Anonymous', null);
            insert anonymous;
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 5000; i++) {
                people.add(new Contact(LastName = 'Donor' + i, AccountId = anonymous.Id));
            }
            // Household upkeep runs once per 200 people saved, 25 times in one test transaction,
            // which is the platform's limit being tested rather than the engine's.
            AutomationControl.bypass('ContactTriggerHandler');
            insert people;
            AutomationControl.clearBypass('ContactTriggerHandler');
            Rollup_Definition__c count = definition(
                'Contact',
                'AccountId',
                'COUNT',
                null,
                'Account',
                'Member_Count__c'
            );

            Test.startTest();
            RollupEngine.recalculate(
                new Set<Id>{ anonymous.Id },
                new List<Rollup_Definition__c>{ count }
            );
            Test.stopTest();

            Assert.areEqual(5000, reread(anonymous.Id).Member_Count__c, 'Every child counted');
        }
    }
}
