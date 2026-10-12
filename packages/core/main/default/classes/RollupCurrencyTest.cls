/**
 * Currency in rollup totals (ADR-NEXT, `NEXT-rollup-totals-in-the-target-record-currency.md`).
 *
 * The arithmetic is tested with test rates in every org. The live test asserts what the org can
 * show: amounts as entered in a single-currency org, and conversion into the target record's
 * currency in a multi-currency one.
 */
@IsTest
private class RollupCurrencyTest {
    @IsTest
    static void amountsGoThroughTheCorporateCurrency() {
        RollupCurrency.multiCurrencyOverride = true;
        RollupCurrency.rateByIso = new Map<String, Decimal>{ 'USD' => 1, 'EUR' => 0.5 };

        Assert.isTrue(RollupCurrency.toCorporate(50, 'EUR') == 100, 'Entered in EUR, to USD');
        Assert.isTrue(RollupCurrency.fromCorporate(100, 'EUR') == 50, 'USD, to EUR');
        Assert.isTrue(RollupCurrency.fromCorporate(100, 'XXX') == 100, 'An unknown code is kept');
    }

    @IsTest
    static void aSingleCurrencyOrgConvertsNothing() {
        RollupCurrency.multiCurrencyOverride = false;
        RollupCurrency.rateByIso = new Map<String, Decimal>{ 'EUR' => 0.5 };

        Assert.isTrue(RollupCurrency.fromCorporate(100, 'EUR') == 100, 'As entered');
    }

    @IsTest
    static void currencyAttributesAreRecognizedThroughARelationship() {
        Assert.isTrue(RollupCurrency.isCurrencyPath('Account', 'AnnualRevenue'), 'Money');
        Assert.isTrue(
            RollupCurrency.isCurrencyPath('Contact', 'Account.AnnualRevenue'),
            'Money on the parent'
        );
        Assert.isFalse(RollupCurrency.isCurrencyPath('Account', 'NumberOfEmployees'), 'A count');
        Assert.isFalse(RollupCurrency.isCurrencyPath('Account', 'Nothing.Here'), 'Nothing');
    }
}
