/**
 * The calculator of BarnCRM's own rollup engine, piece by piece (rollup proposal S5). The whole
 * pass is tested end to end by `RollupEngineTest`.
 */
// runs-as: deploying user (pure logic: tallies values in memory, no DML or SOQL)
@IsTest(testFor='ApexClass:RollupAggregator')
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
        Assert.isTrue((Decimal) empty.result('SUM', null) == 0, 'A sum of nothing is zero');
        Assert.isTrue((Decimal) empty.result('COUNT', null) == 0, 'A count of nothing is zero');
        Assert.isNull(empty.result('AVG', null), 'An average of nothing is blank');
        Assert.isNull(empty.result('MAX', null), 'A maximum of nothing is blank');

        RollupAggregator.Tally three = new RollupAggregator.Tally();
        three.total = 100;
        three.counted = 3;
        Assert.isTrue(
            ((Decimal) three.result('AVG', null)).setScale(2) == 33.33,
            'Divided, not truncated'
        );
    }

    /** Five amounts, read in no particular order, each its own row (ADR-0136). */
    private static RollupAggregator.Tally limited(Integer rowLimit, Boolean descending) {
        RollupAggregator.Tally tally = new RollupAggregator.Tally();
        tally.rowLimit = rowLimit;
        List<Integer> amounts = new List<Integer>{ 10, 50, 30, 40, 20 };
        for (Integer i = 0; i < amounts.size(); i++) {
            RollupAggregator.Listed entry = new RollupAggregator.Listed(
                amounts[i],
                'row' + i,
                String.valueOf(amounts[i])
            );
            entry.raw = amounts[i];
            entry.descending = descending;
            tally.add(entry, false);
        }
        return tally;
    }

    @IsTest
    static void aRowLimitCountsOnlyTheFirstRowsInItsDirection() {
        RollupAggregator.Tally largestOne = limited(1, true);
        Assert.isTrue(largestOne.listed.size() <= 2, 'Trimmed while it reads, never past twice');
        Assert.isTrue((Decimal) largestOne.result('SUM', null) == 50, 'The largest');
        Assert.isTrue((Decimal) limited(2, true).result('SUM', null) == 90, 'The two largest');
        Assert.isTrue((Decimal) limited(2, true).result('AVG', null) == 45, 'Their average');
        Assert.areEqual(30, limited(3, true).result('MIN', null), 'Smallest of the largest 3');
        Assert.areEqual(20, limited(2, false).result('MAX', null), 'Largest of the smallest 2');
        Assert.areEqual('10, 20', limited(2, false).result('TEXT_LIST', ', '), 'First two');
    }

    @IsTest
    static void aDescendingListPutsBlanksLastAndAFirstValueOnce() {
        RollupAggregator.Tally everyValue = new RollupAggregator.Tally();
        RollupAggregator.Tally firstTwo = new RollupAggregator.Tally();
        firstTwo.rowLimit = 2;
        List<Object> orders = new List<Object>{ 1, 3, 2, null };
        List<String> values = new List<String>{ 'b', 'a', 'a', 'c' };
        for (Integer i = 0; i < orders.size(); i++) {
            RollupAggregator.Listed entry = new RollupAggregator.Listed(
                orders[i],
                'row' + i,
                values[i]
            );
            entry.descending = true;
            everyValue.add(entry, false);
            firstTwo.add(entry, true);
        }
        Assert.areEqual(
            'a, a, b, c',
            everyValue.result('TEXT_LIST', ', '),
            'Highest first, a blank order last'
        );
        Assert.areEqual(
            'a; b',
            firstTwo.result('TEXT_LIST_DISTINCT', '; '),
            'The first two different values'
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
