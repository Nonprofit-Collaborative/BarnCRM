/**
 * The system mode writes the rollup engine makes to package-owned data.
 *
 * DOCUMENTED EXCEPTION to the user mode DML rule (plan Section 4.13), on the same ground ADR-0021
 * records for settings and ADR-0015 records for the vendored engine's own writes. Three things are
 * written here and none of them is a user's data:
 *
 * 1. Rollup Definition records materialized from the package's own shipped defaults, which happens
 *    on install, where no permission set is assigned yet and a user mode insert fails for everyone.
 * 2. `Last_Calculated__c` on a definition, and the `Rollups_Last_Calculated__c` freshness stamp on
 *    a target record. A total that was calculated is a fact about the package's own run, not an
 *    edit the running user made, and a nightly batch runs as whoever scheduled it.
 * 3. The totals BarnCRM's own engine calculated (`writeTotals`), with the freshness stamp in the
 *    same save. A total is the package's arithmetic over records, not an edit by whoever saved
 *    the gift that changed it.
 *
 * Nothing an administrator types is written here: the values are datetimes this package computed
 * and values copied out of its own metadata. Permission is enforced before this class is reached,
 * by `RollupController`, for every path an administrator can start.
 */
public without sharing class RollupWriter {
    /** Inserts definitions materialized from the shipped defaults. */
    public static void insertDefinitions(List<Rollup_Definition__c> definitions) {
        if (definitions == null || definitions.isEmpty()) {
            return;
        }
        Database.insert(definitions, AccessLevel.SYSTEM_MODE);
    }

    /** Stamps `Last_Calculated__c` on the definitions a run has just completed. */
    public static void stampDefinitions(Map<Id, Datetime> completedAtById) {
        if (completedAtById == null || completedAtById.isEmpty()) {
            return;
        }
        List<Rollup_Definition__c> toStamp = new List<Rollup_Definition__c>();
        for (Id definitionId : completedAtById.keySet()) {
            toStamp.add(
                new Rollup_Definition__c(
                    Id = definitionId,
                    Last_Calculated__c = completedAtById.get(definitionId)
                )
            );
        }
        Database.update(toStamp, AccessLevel.SYSTEM_MODE);
    }

    /** What one write of totals did: the records saved, and the ones the platform refused. */
    public class TotalsWrite {
        public Set<Id> written = new Set<Id>();
        public Map<Id, String> failed = new Map<Id, String>();
    }

    /**
     * Writes recalculated totals, only where a value changed (rollup proposal, "Changed-only
     * writes"), each record once, with `Rollups_Last_Calculated__c` stamped in the same save
     * (bug 4). A record whose totals are all unchanged is not saved, so a second full run writes
     * nothing. Records are saved in Id order, and one locked or invalid record fails alone.
     *
     * @param targetType the entity written
     * @param stored the records as they are now, holding every attribute in `computed`
     * @param computed the new values, by record, then by attribute
     * @param stampAt the freshness stamp for the records saved
     */
    public static TotalsWrite writeTotals(
        Schema.SObjectType targetType,
        Map<Id, SObject> stored,
        Map<Id, Map<Schema.SObjectField, Object>> computed,
        Datetime stampAt
    ) {
        TotalsWrite result = new TotalsWrite();
        if (targetType == null || computed == null || computed.isEmpty()) {
            return result;
        }
        Schema.SObjectField stamp = freshnessField(targetType);
        List<Id> targetIds = new List<Id>(computed.keySet());
        targetIds.sort();
        List<SObject> toSave = new List<SObject>();
        Map<Schema.SObjectField, Map<String, String>> picklists = new Map<Schema.SObjectField, Map<String, String>>();
        Map<String, Id> refused = new Map<String, Id>();
        for (Id targetId : targetIds) {
            SObject current = stored.get(targetId);
            if (current == null) {
                continue;
            }
            SObject changed = targetType.newSObject(targetId);
            Boolean anyChange = false;
            Map<Schema.SObjectField, Object> values = computed.get(targetId);
            for (Schema.SObjectField field : values.keySet()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                Object value = coerce(describe, values.get(field));
                if (value != null && describe.getType() == Schema.DisplayType.PICKLIST) {
                    String text = (String) value;
                    value = picklistValueFor(picklists, field, text);
                    if (value == null) {
                        // R-R15: left out and logged, so the record's other totals still save.
                        String message = String.format(
                            System.Label.Core_Rollups_PicklistValueRefused,
                            new List<Object>{ text, describe.getLabel() }
                        );
                        if (!refused.containsKey(message)) {
                            refused.put(message, targetId);
                        }
                        continue;
                    }
                }
                if (!sameValue(current.get(field), value)) {
                    changed.put(field, value);
                    anyChange = true;
                }
            }
            if (anyChange) {
                if (stamp != null) {
                    changed.put(stamp, stampAt);
                }
                toSave.add(changed);
            }
        }
        if (!refused.isEmpty()) {
            ErrorLogger.logMessages(
                new List<String>(refused.keySet()),
                refused.values(),
                'RollupWriter',
                ErrorLogger.SEVERITY_WARNING
            );
        }
        if (toSave.isEmpty()) {
            return result;
        }
        List<Database.SaveResult> saved = Database.update(toSave, false, AccessLevel.SYSTEM_MODE);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                result.written.add(toSave[i].Id);
            } else {
                result.failed.put(toSave[i].Id, saved[i].getErrors()[0].getMessage());
            }
        }
        return result;
    }

    /**
     * The freshness attribute on this entity, or null when it has none or it is calculated.
     * Not the running user's access: the save is in system mode, and the Rollup Queue runs as
     * the Automated Process user, whose access says nothing. Import undo reads the stamp to
     * tell a rollup's save from an edit (R-IB9), so it must never be skipped silently.
     */
    public static Schema.SObjectField freshnessField(Schema.SObjectType targetType) {
        Schema.SObjectField stamp = targetType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .get(RollupService.FRESHNESS_FIELD);
        return stamp != null && !stamp.getDescribe().isCalculated() ? stamp : null;
    }

    /**
     * A value in the form the attribute stores, so that comparing it with what is stored means
     * something: numbers rounded to the attribute's decimal places as the platform rounds them on
     * save (an average of 33.333 is stored as 33.33 and must not count as a change every night),
     * dates and datetimes converted to the attribute's type, text cut at the attribute's length,
     * a picklist value as text (checked against the picklist by `writeTotals`), and a checkbox
     * true or false.
     */
    @TestVisible
    private static Object coerce(Schema.DescribeFieldResult describe, Object value) {
        if (value == null) {
            return null;
        }
        Schema.DisplayType type = describe.getType();
        if (type == Schema.DisplayType.BOOLEAN) {
            return value instanceof Boolean && (Boolean) value;
        }
        if (type == Schema.DisplayType.PICKLIST) {
            return RollupAggregator.toText(value);
        }
        if (type == Schema.DisplayType.STRING || type == Schema.DisplayType.TEXTAREA) {
            // Cut at the attribute's length (R-R15), so the save never fails on a long list and
            // the same text is compared, and so not written again, on the next run.
            String text = RollupAggregator.toText(value);
            return text.length() > describe.getLength() ? text.left(describe.getLength()) : text;
        }
        if (type == Schema.DisplayType.DATE) {
            // A Date is also `instanceof Datetime` in Apex, so test for Date first: calling
            // `.date()` on one reads it as midnight GMT and gives the day before west of GMT.
            if (value instanceof Date) {
                return value;
            }
            return value instanceof Datetime ? ((Datetime) value).date() : value;
        }
        if (type == Schema.DisplayType.DATETIME) {
            return value instanceof Date
                ? Datetime.newInstance((Date) value, Time.newInstance(0, 0, 0, 0))
                : value;
        }
        Decimal amount = RollupAggregator.toDecimal(value)
            .setScale(describe.getScale(), System.RoundingMode.HALF_UP);
        if (type == Schema.DisplayType.INTEGER) {
            return amount.intValue();
        }
        return type == Schema.DisplayType.LONG ? (Object) amount.longValue() : (Object) amount;
    }

    /**
     * The picklist's own active value for this text, matched without regard to letter case, or
     * null when the picklist has no such value (R-R15). Each picklist is described once a write.
     */
    private static String picklistValueFor(
        Map<Schema.SObjectField, Map<String, String>> picklists,
        Schema.SObjectField field,
        String text
    ) {
        if (!picklists.containsKey(field)) {
            Map<String, String> byLowerCase = new Map<String, String>();
            for (Schema.PicklistEntry entry : field.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    byLowerCase.put(entry.getValue().toLowerCase(), entry.getValue());
                }
            }
            picklists.put(field, byLowerCase);
        }
        return picklists.get(field).get(text.toLowerCase());
    }

    /** Equal stored and computed values; numbers compare by value, whatever their scale. */
    @TestVisible
    private static Boolean sameValue(Object stored, Object computed) {
        if (stored == null || computed == null) {
            return stored == computed;
        }
        if (isNumber(stored) && isNumber(computed)) {
            return RollupAggregator.toDecimal(stored) == RollupAggregator.toDecimal(computed);
        }
        return stored.equals(computed);
    }

    private static Boolean isNumber(Object value) {
        return value instanceof Decimal ||
            value instanceof Integer ||
            value instanceof Long ||
            value instanceof Double;
    }

    /** Saves an administrator's edit to a definition, in user mode, where it belongs. */
    public static void saveAsUser(Rollup_Definition__c definition) {
        Database.upsert(definition, AccessLevel.USER_MODE);
    }
}
