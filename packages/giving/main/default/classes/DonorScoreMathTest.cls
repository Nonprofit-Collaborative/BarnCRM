/**
 * The rules of donor scoring as plain functions (R-DT2 to R-DT4): no records, no org.
 */
// runs-as: deploying user (pure functions over numbers, no DML, SOQL or settings)
@IsTest(testFor='ApexClass:DonorScoreMath')
private class DonorScoreMathTest {
    @IsTest
    static void recencyScoresFiveForTheMostRecentAndOneBeyondTheLastCutoff() {
        List<Decimal> days = DonorScoreMath.DEFAULT_RECENCY_DAYS;
        Assert.areEqual(5, DonorScoreMath.recencyScore(0, days), 'Today is the most recent.');
        Assert.areEqual(5, DonorScoreMath.recencyScore(90, days), 'The cutoff itself is inside.');
        Assert.areEqual(4, DonorScoreMath.recencyScore(91, days), 'One day past the first cutoff.');
        Assert.areEqual(3, DonorScoreMath.recencyScore(365, days), 'A year.');
        Assert.areEqual(2, DonorScoreMath.recencyScore(730, days), 'Two years.');
        Assert.areEqual(1, DonorScoreMath.recencyScore(731, days), 'Beyond the fourth cutoff.');
    }

    @IsTest
    static void frequencyAndMonetaryScoreFiveWhenTheFirstCutoffIsReached() {
        Assert.areEqual(
            5,
            DonorScoreMath.highScore(6, DonorScoreMath.DEFAULT_FREQUENCY_GIFTS),
            '6 gifts'
        );
        Assert.areEqual(
            3,
            DonorScoreMath.highScore(2, DonorScoreMath.DEFAULT_FREQUENCY_GIFTS),
            '2 gifts'
        );
        Assert.areEqual(
            1,
            DonorScoreMath.highScore(0, DonorScoreMath.DEFAULT_FREQUENCY_GIFTS),
            'No gifts'
        );
        Assert.areEqual(
            1,
            DonorScoreMath.highScore(null, DonorScoreMath.DEFAULT_FREQUENCY_GIFTS),
            'Empty is zero'
        );
        Assert.areEqual(
            4,
            DonorScoreMath.highScore(1000, DonorScoreMath.DEFAULT_MONETARY_AMOUNTS),
            '1000'
        );
        Assert.areEqual(
            2,
            DonorScoreMath.highScore(50, DonorScoreMath.DEFAULT_MONETARY_AMOUNTS),
            '50'
        );
        Assert.areEqual(
            1,
            DonorScoreMath.highScore(49.99, DonorScoreMath.DEFAULT_MONETARY_AMOUNTS),
            'Under 50'
        );
    }

    @IsTest
    static void aBadCutoffSettingFallsBackToTheDefault() {
        List<Decimal> defaults = DonorScoreMath.DEFAULT_RECENCY_DAYS;
        Assert.areEqual(
            new List<Decimal>{ 30, 60, 120, 240 },
            DonorScoreMath.cutoffs('30, 60,120 ,240', defaults, true),
            'Spaces are fine.'
        );
        Assert.areEqual(defaults, DonorScoreMath.cutoffs(null, defaults, true), 'Blank');
        Assert.areEqual(
            defaults,
            DonorScoreMath.cutoffs('30,60,120', defaults, true),
            'Three numbers'
        );
        Assert.areEqual(
            defaults,
            DonorScoreMath.cutoffs('30,sixty,120,240', defaults, true),
            'Text'
        );
        Assert.areEqual(
            defaults,
            DonorScoreMath.cutoffs('240,120,60,30', defaults, true),
            'Wrong way'
        );
        Assert.areEqual(
            new List<Decimal>{ 10.5, 5, 2, 1 },
            DonorScoreMath.cutoffs('10.5,5,2,1', DonorScoreMath.DEFAULT_FREQUENCY_GIFTS, false),
            'Falling cutoffs may be decimals.'
        );
        Assert.areEqual(
            DonorScoreMath.DEFAULT_FREQUENCY_GIFTS,
            DonorScoreMath.cutoffs('1,2,4,6', DonorScoreMath.DEFAULT_FREQUENCY_GIFTS, false),
            'Frequency that rises is wrong.'
        );
    }

    @IsTest
    static void theSegmentIsTheFirstRuleThatFits() {
        Assert.areEqual('Champion', DonorScoreMath.segment(5, 5, 4), 'Recent, often, generous');
        Assert.areEqual('Loyal', DonorScoreMath.segment(3, 3, 1), 'Recent enough and often');
        Assert.areEqual(
            'Loyal',
            DonorScoreMath.segment(5, 3, 3),
            'Not generous enough to be a champion'
        );
        Assert.areEqual('Promising', DonorScoreMath.segment(5, 1, 1), 'Recent, not yet frequent');
        Assert.areEqual('At Risk', DonorScoreMath.segment(2, 4, 1), 'Used to give often');
        Assert.areEqual('At Risk', DonorScoreMath.segment(1, 1, 5), 'Used to give a lot');
        Assert.areEqual('Lapsed', DonorScoreMath.segment(1, 1, 1), 'Long ago, little');
        Assert.areEqual('Occasional', DonorScoreMath.segment(3, 2, 1), 'In between');
    }
}
