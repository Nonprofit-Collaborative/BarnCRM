/**
 * The planner of BarnCRM's own rollup engine: one pass per target entity, definitions that read
 * the same rows sharing one query, and broken definitions refused one by one (rollup proposal S5).
 */
@IsTest(testFor='ApexClass:RollupPlanner')
private class RollupPlannerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static Rollup_Definition__c fromChildren(
        String aggregate,
        String sourceField,
        String targetField
    ) {
        return new Rollup_Definition__c(
            Name = aggregate + ' ' + targetField,
            Source_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = aggregate,
            Source_Field__c = sourceField,
            Target_Object__c = 'Account',
            Target_Field__c = targetField,
            Active__c = true
        );
    }

    @IsTest
    static void definitionsReadingTheSameRowsShareOneQuery() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c filtered = fromChildren('SUM', 'AnnualRevenue', 'AnnualRevenue');
            filtered.Filter_JSON__c = '{"version": 1, "conditions": [{"id": 1, "field": "Name", "operator": "equals", "value": "A"}]}';

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{
                    fromChildren('SUM', 'NumberOfEmployees', 'Member_Count__c'),
                    fromChildren('COUNT', null, 'NumberOfEmployees'),
                    fromChildren('MAX', 'Anniversary__c', 'Anniversary__c'),
                    filtered
                }
            );

            Assert.areEqual(4, plan.definitions.size(), 'All four are planned');
            Assert.areEqual(2, plan.queries.size(), 'One query per distinct filter');
            Assert.areEqual(3, plan.queries[0].measures.size(), 'The unfiltered three share one');
            Assert.areEqual('ParentId', plan.queries[0].keyExpression, 'Grouped by the lookup');
        }
    }

    @IsTest
    static void eachBrokenDefinitionIsRefusedAlone() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c unordered = fromChildren(
                'FIRST',
                'NumberOfEmployees',
                'AnnualRevenue'
            );
            Rollup_Definition__c checkbox = fromChildren('COUNT', null, 'Custom_Name__c');
            Rollup_Definition__c text = fromChildren('MAX', 'Name', 'Description');
            Rollup_Definition__c missing = fromChildren('COUNT', null, 'No_Such_Field__c');
            Rollup_Definition__c midToken = fromChildren('COUNT', null, 'Member_Count__c');
            midToken.Relationship_Path__c = '{Household} > ParentId';
            Rollup_Definition__c injected = fromChildren(
                'SUM',
                'Amount) FROM User --',
                'Member_Count__c'
            );
            Rollup_Definition__c otherTarget = fromChildren('COUNT', null, 'Member_Count__c');
            otherTarget.Target_Object__c = 'Contact';

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{
                    unordered,
                    checkbox,
                    text,
                    missing,
                    midToken,
                    injected,
                    otherTarget
                }
            );

            Assert.areEqual(6, plan.refused.size(), 'Every broken one, each on its own');
            Assert.isTrue(
                plan.definitions.isEmpty(),
                'Another entity\'s definition is not this pass'
            );
        }
    }

    @IsTest
    static void alternativesAndTokensBecomeOneQueryEach() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c credits = new Rollup_Definition__c(
                Name = 'Household reports',
                Source_Object__c = 'Contact',
                Relationship_Path__c = 'ReportsToId > {Household} | AccountId',
                Aggregate__c = 'COUNT',
                Target_Object__c = 'Account',
                Target_Field__c = 'Member_Count__c',
                Active__c = true
            );

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{ credits }
            );

            Assert.areEqual(2, plan.queries.size(), 'One query per alternative');
            Assert.areEqual(RollupPath.TOKEN_HOUSEHOLD, plan.queries[0].token, 'Resolved by token');
            Assert.areEqual(
                'ReportsToId',
                plan.queries[0].keyExpression,
                'Read off the source row'
            );
            Assert.areEqual(
                new List<String>{ 'ReportsToId' },
                plan.queries[1].earlierKeys,
                'The second alternative counts only where the first is blank'
            );
            Assert.areEqual(
                'Gift__r.Donor_Contact__c',
                RollupPlanner.keyExpressionFor(new List<String>{ 'Gift__c', 'Donor_Contact__c' }),
                'Two hops are read through the relationship'
            );
        }
    }

    /**
     * A run plans for whoever saved the record that set it off, and the totals are read only for
     * everyone but an administrator. The planner asks whether the engine can write the target,
     * not whether this person may edit it (R-R10, "Writable at run time"): before, every
     * definition was refused on a staff member's save and the totals waited for the nightly run.
     */
    @IsTest
    static void aTargetTheSavingUserMayNotEditIsStillPlanned() {
        User staff;
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            staff = TestDataFactory.createUser('Plannerstaff', new List<String>{ 'BarnCRM_Staff' });
        }

        System.runAs(staff) {
            Assert.isFalse(
                Schema.SObjectType.Account.fields.Emptied_By_Deletion__c.isUpdateable(),
                'Precondition: BarnCRM Staff may read this date and not edit it'
            );

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{
                    fromChildren('MAX', 'Anniversary__c', 'Emptied_By_Deletion__c')
                }
            );

            Assert.isTrue(plan.refused.isEmpty(), 'Not refused for the saving user\'s access');
            Assert.areEqual(1, plan.definitions.size(), 'The definition is planned');
        }
    }

    /** What no permission can make editable is still refused, an administrator's run included. */
    @IsTest
    static void formulaAutoNumberAndSystemTargetsAreStillRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.isFalse(
                RollupPlanner.engineCanWrite(
                    Field_Utilization_Snapshot__c.Fill_Rate__c.getDescribe()
                ),
                'A formula is calculated by the platform'
            );
            Assert.isFalse(
                RollupPlanner.engineCanWrite(Rollup_Queue__c.Name.getDescribe()),
                'An auto number is set by the platform'
            );
            Assert.isFalse(
                RollupPlanner.engineCanWrite(Account.LastModifiedDate.getDescribe()),
                'A system attribute is set by the platform'
            );
            Assert.isTrue(
                RollupPlanner.engineCanWrite(Account.Member_Count__c.getDescribe()),
                'An ordinary number attribute is written'
            );

            Rollup_Definition__c formula = new Rollup_Definition__c(
                Name = 'Fill rate',
                Source_Object__c = 'Field_Utilization_Snapshot__c',
                Relationship_Path__c = 'Id',
                Aggregate__c = 'MAX',
                Source_Field__c = 'Fill_Rate__c',
                Target_Object__c = 'Field_Utilization_Snapshot__c',
                Target_Field__c = 'Fill_Rate__c',
                Active__c = true
            );
            RollupPlanner.Plan formulaPlan = RollupPlanner.plan(
                Field_Utilization_Snapshot__c.SObjectType,
                new List<Rollup_Definition__c>{ formula }
            );
            RollupPlanner.Plan systemPlan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{
                    fromChildren('MAX', 'Anniversary__c', 'LastModifiedDate')
                }
            );

            Assert.areEqual(1, formulaPlan.refused.size(), 'A formula target is refused');
            Assert.isTrue(formulaPlan.definitions.isEmpty(), 'And not planned');
            Assert.areEqual(1, systemPlan.refused.size(), 'A system target is refused');
            Assert.isTrue(systemPlan.definitions.isEmpty(), 'And not planned');
        }
    }

    private static Rollup_Definition__c ordered(
        String aggregate,
        String sourceField,
        String targetField,
        String direction
    ) {
        Rollup_Definition__c definition = fromChildren(aggregate, sourceField, targetField);
        definition.Order_By_Field__c = 'NumberOfEmployees';
        definition.Order_Direction__c = direction;
        return definition;
    }

    /** ADR-0136: a limited sum reads rows per parent; First stays the lowest whatever the direction. */
    @IsTest
    static void aRowLimitKeepsTheFirstRowsOfEachParentAndFirstIgnoresTheDirection() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Account parent = new Account(Name = 'Parent');
            insert parent;
            List<Account> children = new List<Account>{ new Account(Name = 'Kid blank') };
            for (Integer size : new List<Integer>{ 10, 50, 30, 40 }) {
                children.add(new Account(Name = 'Kid ' + size, NumberOfEmployees = size));
            }
            for (Account child : children) {
                child.ParentId = parent.Id;
            }
            insert children;
            Rollup_Definition__c largestTwo = ordered(
                'SUM',
                'NumberOfEmployees',
                'NumberOfEmployees',
                'Descending'
            );
            largestTwo.Row_Limit__c = 2;

            RollupPlanner.Plan plan = RollupPlanner.plan(
                Account.SObjectType,
                new List<Rollup_Definition__c>{
                    largestTwo,
                    ordered('TEXT_LIST', 'Name', 'Description', 'Descending'),
                    ordered('FIRST', 'Name', 'Site', 'Descending')
                }
            );
            RollupAggregator.Answer answer = RollupAggregator.calculate(
                plan,
                new Set<Id>{ parent.Id }
            );

            Assert.areEqual(2, plan.queries.size(), 'The limited sum shares the list rows');
            Assert.areEqual(RollupPlanner.KIND_LISTED, plan.queries[0].kind, 'Read as rows');
            Assert.isTrue(
                (Decimal) answer.tallies.get(0).get(parent.Id).result('SUM', null) == 90,
                'The two largest'
            );
            Assert.areEqual(
                'Kid 50, Kid 40, Kid 30, Kid 10, Kid blank',
                answer.tallies.get(1).get(parent.Id).result('TEXT_LIST', ', '),
                'Largest first, a blank order last'
            );
            Assert.areEqual(
                'Kid 10',
                answer.tallies.get(2).get(parent.Id).result('FIRST', null),
                'First is still the lowest'
            );
        }
    }

    @IsTest
    static void aRowLimitNeedsAnOrderACalculationThatTakesItAndOneOrMore() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.isNull(RollupPlanner.rowLimitProblem('COUNT', null, null), 'No limit, no check');
            Assert.areEqual(
                Label.Core_Rollups_ErrorRowLimitInvalid,
                RollupPlanner.rowLimitProblem('SUM', 0, 'Name'),
                'At least 1'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorRowLimitAggregate,
                RollupPlanner.rowLimitProblem('COUNT', 3, 'Name'),
                'A count takes no limit'
            );
            Assert.areEqual(
                Label.Core_Rollups_ErrorRowLimitNeedsOrder,
                RollupPlanner.rowLimitProblem('TEXT_LIST', 3, null),
                'A limit needs an order'
            );
            Rollup_Definition__c unordered = fromChildren(
                'SUM',
                'NumberOfEmployees',
                'AnnualRevenue'
            );
            unordered.Row_Limit__c = 2;
            Assert.areEqual(
                1,
                RollupPlanner.plan(Account.SObjectType, new List<Rollup_Definition__c>{ unordered })
                    .refused.size(),
                'The planner refuses it too'
            );
        }
    }
}
