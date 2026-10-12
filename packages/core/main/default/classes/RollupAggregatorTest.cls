/**
 * The calculator of BarnCRM's own rollup engine, piece by piece (rollup proposal S5). The whole
 * pass is tested end to end by `RollupEngineTest`.
 */
// runs-as: deploying user (pure logic: tallies values in memory, no DML or SOQL)
@IsTest
private class RollupAggregatorTest {
    @IsTest
    static void laterAlternativesCountOnlyWhereEarlierOnesAreBlank() {
        RollupPlanner.SourceQuery query = new RollupPlanner.SourceQuery();
        query.keyExpression = 'Donor_Account__c';
        query.earlierKeys.add('Household__c');
        query.whereClause = 'Amount__c > 0';

        Assert.areEqual(
            ' WHERE Donor_Account__c IN :keys AND Household__c = null AND (Amount__c > 0)',
            RollupAggregator.whereFor(query),
            'The key bound, the earlier alternative blank, and the filter'
        );
    }

    @IsTest
    static void aSumOfNothingIsZeroAndAnAverageIsExact() {
        RollupAggregator.Tally empty = new RollupAggregator.Tally();
        Assert.isTrue((Decimal) empty.result('SUM') == 0, 'A sum of nothing is zero');
        Assert.isTrue((Decimal) empty.result('COUNT') == 0, 'A count of nothing is zero');
        Assert.isNull(empty.result('AVG'), 'An average of nothing is blank');
        Assert.isNull(empty.result('MAX'), 'A maximum of nothing is blank');

        RollupAggregator.Tally three = new RollupAggregator.Tally();
        three.total = 100;
        three.counted = 3;
        Assert.isTrue(
            ((Decimal) three.result('AVG')).setScale(2) == 33.33,
            'Divided, not truncated'
        );
    }

    @IsTest
    static void valuesCompareAndReadThroughRelationships() {
        Assert.areEqual(-1, RollupAggregator.compare(1, 2.5), 'Numbers of any type');
        Assert.areEqual(
            1,
            RollupAggregator.compare(Date.newInstance(2024, 1, 2), Date.newInstance(2024, 1, 1)),
            'Dates'
        );
        Account parent = new Account(Name = 'Parent');
        Account child = new Account(Name = 'Child');
        child.putSObject('Parent', parent);
        Assert.areEqual('Parent', RollupAggregator.valueAt(child, 'Parent.Name'), 'Through');
        Assert.isNull(RollupAggregator.valueAt(new Account(), 'Parent.Name'), 'A blank parent');
    }
}
