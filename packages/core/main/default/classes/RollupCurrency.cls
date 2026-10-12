/**
 * Currency for rollup totals (ADR-0083, `0083-rollup-totals-in-the-target-record-currency.md`).
 *
 * In a single-currency org nothing here changes a value: amounts are added as entered, which is
 * what BarnCRM totals have always done.
 *
 * In a multi-currency org an aggregate query answers SUM, AVG, MIN and MAX of a currency attribute
 * in the corporate currency, whatever currency each row was entered in, and the result cannot be
 * converted in the query. So the engine works in the corporate currency throughout (FIRST and LAST
 * rows are brought to it by `toCorporate`) and converts once, at the end, into the target record's
 * own currency when the target attribute is a currency attribute (`fromCorporate`). The rates are
 * the org's static conversion rates; dated exchange rates are not applied.
 *
 * `CurrencyType` and `CurrencyIsoCode` exist only in a multi-currency org, so both are named as
 * text and read dynamically, never compiled against.
 */
public without sharing class RollupCurrency {
    public static final String ISO_FIELD = 'CurrencyIsoCode';

    /** Read only after `isMultiCurrency` says the org has the object. */
    @TestVisible
    private static final String RATES = 'SELECT IsoCode, ConversionRate, IsCorporate FROM CurrencyType'; // detection-only: run only in a multi-currency org

    /** Set by a test to exercise the conversion arithmetic in a single-currency org. */
    @TestVisible
    private static Boolean multiCurrencyOverride;

    @TestVisible
    private static Map<String, Decimal> rateByIso;

    public static Boolean isMultiCurrency() {
        return multiCurrencyOverride != null
            ? multiCurrencyOverride
            : UserInfo.isMultiCurrencyOrganization();
    }

    /** True when the attribute at the end of this path, from this entity, holds money. */
    public static Boolean isCurrencyPath(String sourceObject, String path) {
        Schema.SObjectType current = SettingsService.typeByName(sourceObject);
        List<String> parts = String.isBlank(path) ? new List<String>() : path.split('\\.');
        for (Integer i = 0; i < parts.size() && current != null; i++) {
            Map<String, Schema.SObjectField> fields = current.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap();
            if (i == parts.size() - 1) {
                Schema.SObjectField field = fields.get(parts[i].toLowerCase());
                return field != null &&
                    field.getDescribe().getType() == Schema.DisplayType.CURRENCY;
            }
            current = parentTypeOf(fields.values(), parts[i]);
        }
        return false;
    }

    private static Schema.SObjectType parentTypeOf(
        List<Schema.SObjectField> fields,
        String relationshipName
    ) {
        for (Schema.SObjectField field : fields) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (
                relationshipName.equalsIgnoreCase(describe.getRelationshipName()) &&
                !describe.getReferenceTo().isEmpty()
            ) {
                return describe.getReferenceTo()[0];
            }
        }
        return null;
    }

    /** A value entered in this currency, in the corporate currency. */
    public static Decimal toCorporate(Decimal value, String isoCode) {
        Decimal rate = rateFor(isoCode);
        return value == null || rate == null || rate == 0 ? value : value / rate;
    }

    /** A corporate currency value, in this currency. */
    public static Decimal fromCorporate(Decimal value, String isoCode) {
        Decimal rate = rateFor(isoCode);
        return value == null || rate == null ? value : value * rate;
    }

    private static Decimal rateFor(String isoCode) {
        if (String.isBlank(isoCode) || !isMultiCurrency()) {
            return null;
        }
        if (rateByIso == null) {
            rateByIso = new Map<String, Decimal>();
            for (SObject row : Database.query(RATES, AccessLevel.SYSTEM_MODE)) {
                rateByIso.put((String) row.get('IsoCode'), (Decimal) row.get('ConversionRate'));
            }
        }
        return rateByIso.get(isoCode);
    }
}
