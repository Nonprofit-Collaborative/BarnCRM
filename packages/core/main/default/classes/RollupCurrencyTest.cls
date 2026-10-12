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

    /**
     * Two children's revenue summed onto their parent. Without multi-currency the total is the
     * amounts as entered; with it, the children are entered in the corporate currency and the
     * parent's total is in the parent's own currency.
     */
    @IsTest
    static void aTotalIsInTheTargetRecordsCurrency() {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        Account parent = new Account(Name = 'Parent', RecordTypeId = organizationType);
        String corporate;
        String parentCurrency;
        Decimal parentRate = 1;
        if (UserInfo.isMultiCurrencyOrganization()) {
            for (SObject rate : Database.query(RollupCurrency.RATES + ' WHERE IsActive = TRUE')) {
                if ((Boolean) rate.get('IsCorporate')) {
                    corporate = (String) rate.get('IsoCode');
                } else if (parentCurrency == null) {
                    parentCurrency = (String) rate.get('IsoCode');
                    parentRate = (Decimal) rate.get('ConversionRate');
                }
            }
            if (parentCurrency != null) {
                parent.put(RollupCurrency.ISO_FIELD, parentCurrency);
            }
        }
        insert parent;
        List<Account> children = new List<Account>{
            new Account(
                Name = 'A',
                RecordTypeId = organizationType,
                ParentId = parent.Id,
                AnnualRevenue = 100
            ),
            new Account(
                Name = 'B',
                RecordTypeId = organizationType,
                ParentId = parent.Id,
                AnnualRevenue = 50
            )
        };
        for (Account child : children) {
            if (corporate != null) {
                child.put(RollupCurrency.ISO_FIELD, corporate);
            }
        }
        insert children;
        Rollup_Definition__c total = new Rollup_Definition__c(
            Name = 'Revenue',
            Source_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'SUM',
            Source_Field__c = 'AnnualRevenue',
            Target_Object__c = 'Account',
            Target_Field__c = 'AnnualRevenue',
            Active__c = true
        );

        RollupEngine.recalculate(new Set<Id>{ parent.Id }, new List<Rollup_Definition__c>{ total });

        Decimal expected = UserInfo.isMultiCurrencyOrganization() && parentCurrency != null
            ? (150 * parentRate)
                  .setScale(
                      Account.AnnualRevenue.getDescribe().getScale(),
                      System.RoundingMode.HALF_UP
                  )
            : 150;
        Assert.areEqual(
            expected,
            [SELECT AnnualRevenue FROM Account WHERE Id = :parent.Id].AnnualRevenue,
            'In the parent\'s currency, or as entered in a single-currency org'
        );
    }
}
