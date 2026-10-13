/**
 * The planner of BarnCRM's own rollup engine: one pass per target entity, definitions that read
 * the same rows sharing one query, and broken definitions refused one by one (rollup proposal S5).
 */
// runs-as: deploying user (pure logic: plans rollup definitions built in memory, no DML or SOQL)
@IsTest
private class RollupPlannerTest {
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

    @IsTest
    static void eachBrokenDefinitionIsRefusedAlone() {
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
        Assert.isTrue(plan.definitions.isEmpty(), 'Another entity\'s definition is not this pass');
    }

    @IsTest
    static void alternativesAndTokensBecomeOneQueryEach() {
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
        Assert.areEqual('ReportsToId', plan.queries[0].keyExpression, 'Read off the source row');
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
