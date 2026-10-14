/**
 * Which objects and fields a bulk update may write, which fields may be copied into which, and
 * how a value to set is typed (C-35, canonical model R-BU4, ADR-0077 bulk update).
 *
 * Everything is asked of the running user's describe: a target is a field of the query's own
 * object that the user may edit, of a type a value can be written to, and not one the package
 * keeps. What the package keeps, and which objects are its bookkeeping or Setup's, is the one
 * list in `DataProtectedFields` that a one-object import (C-33) uses too, worked out when asked
 * from the Rollup Definitions, so a rollup added later is protected without a code change.
 * Core names no object of another module (ADR-0059): a module names its protected objects
 * through `DataProtectionExtensions`, and its own lock triggers refuse a locked record's save.
 *
 * This decides what may be offered and checked. Every write is still in user mode.
 */
public with sharing class BulkUpdateFields {
    /** Raised for anything the person can fix; the message is for them. */
    public class BulkUpdateException extends Exception {
    }

    private static final Set<Schema.DisplayType> TEXT_TARGETS = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA
    };
    private static final Set<Schema.DisplayType> TEXT_SOURCES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.COMBOBOX
    };
    private static final Set<Schema.DisplayType> NUMBERS = new Set<Schema.DisplayType>{
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT
    };
    /** The words a step result may be for a ticked and an unticked checkbox. */
    private static final Set<String> CHECKED_WORDS = new Set<String>{ 'true', 'yes', '1' };
    private static final Set<String> UNCHECKED_WORDS = new Set<String>{ 'false', 'no', '0' };
    /** Types a bulk update can write a value of. The undo puts each of them back typed. */
    private static final Set<Schema.DisplayType> WRITABLE = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.URL,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME,
        Schema.DisplayType.REFERENCE
    };

    /** One field a bulk update may write, as the page offers it. */
    public class Target {
        @AuraEnabled
        public String apiName;
        @AuraEnabled
        public String label;
        /** The describe type in lower case, as QueryFieldCatalog gives it. */
        @AuraEnabled
        public String dataType;
        /** True when the field may be cleared. */
        @AuraEnabled
        public Boolean nillable;
        /** The parent object of a lookup with exactly one parent type; empty otherwise. */
        @AuraEnabled
        public String referenceTo;
        @AuraEnabled
        public List<QueryFieldCatalog.PicklistOption> picklistValues;
    }

    /** The object, or a refusal naming it when no bulk update may write its records. */
    public static Schema.SObjectType writableObject(String objectName) {
        Schema.DescribeSObjectResult described;
        try {
            described = QueryFieldCatalog.describeObject(objectName);
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            throw new BulkUpdateException(refused.getMessage());
        }
        String reason = objectReason(described);
        if (reason != null) {
            throw new BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorObject,
                    new List<Object>{ described.getLabelPlural(), reason }
                )
            );
        }
        return described.getSObjectType();
    }

    /** Every field of the object a bulk update may write, sorted by label. */
    public static List<Target> targets(String objectName) {
        Schema.SObjectType type = writableObject(objectName);
        Map<String, Target> byLabel = new Map<String, Target>();
        for (Schema.SObjectField token : fieldMap(type).values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (fieldReason(type, field) != null) {
                continue;
            }
            Target target = new Target();
            target.apiName = field.getName();
            target.label = field.getLabel();
            target.dataType = String.valueOf(field.getType()).toLowerCase();
            target.nillable = field.isNillable();
            List<Schema.SObjectType> parents = field.getReferenceTo();
            target.referenceTo = parents.size() == 1
                ? parents[0].getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                : null;
            target.picklistValues = new List<QueryFieldCatalog.PicklistOption>();
            for (Schema.PicklistEntry entry : field.getPicklistValues()) {
                if (entry.isActive()) {
                    QueryFieldCatalog.PicklistOption option = new QueryFieldCatalog.PicklistOption();
                    option.label = entry.getLabel();
                    option.value = entry.getValue();
                    target.picklistValues.add(option);
                }
            }
            byLabel.put(target.label.toLowerCase() + '\u0000' + target.apiName, target);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        List<Target> result = new List<Target>();
        for (String key : keys) {
            result.add(byLabel.get(key));
        }
        return result;
    }

    /** The fields the person may read that can be copied into this target, sorted by label. */
    public static List<QueryFieldCatalog.PicklistOption> copySources(
        String objectName,
        String targetName
    ) {
        Schema.SObjectType type = writableObject(objectName);
        Schema.DescribeFieldResult target = writableField(type, targetName);
        Map<String, QueryFieldCatalog.PicklistOption> byLabel = new Map<String, QueryFieldCatalog.PicklistOption>();
        for (Schema.SObjectField token : fieldMap(type).values()) {
            Schema.DescribeFieldResult source = token.getDescribe();
            if (
                source.getName() == target.getName() ||
                !source.isAccessible() ||
                !compatible(target, source)
            ) {
                continue;
            }
            QueryFieldCatalog.PicklistOption option = new QueryFieldCatalog.PicklistOption();
            option.label = source.getLabel();
            option.value = source.getName();
            byLabel.put(option.label.toLowerCase() + '\u0000' + option.value, option);
        }
        List<String> keys = new List<String>(byLabel.keySet());
        keys.sort();
        List<QueryFieldCatalog.PicklistOption> result = new List<QueryFieldCatalog.PicklistOption>();
        for (String key : keys) {
            result.add(byLabel.get(key));
        }
        return result;
    }

    /** A field of the object itself the person may read, found in describe, or a refusal. */
    public static Schema.DescribeFieldResult ownField(Schema.SObjectType type, Object rawName) {
        String name = rawName == null ? '' : String.valueOf(rawName).trim();
        Schema.SObjectField token = String.isBlank(name) || name.contains('.')
            ? null
            : fieldMap(type).get(name.toLowerCase());
        if (token == null || !token.getDescribe().isAccessible()) {
            throw new BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorUnknownField,
                    new List<Object>{ name.abbreviate(80) }
                )
            );
        }
        return token.getDescribe();
    }

    /** A field the person may bulk update, or a refusal naming it and saying why. */
    public static Schema.DescribeFieldResult writableField(
        Schema.SObjectType type,
        Object rawName
    ) {
        Schema.DescribeFieldResult field = ownField(type, rawName);
        String reason = fieldReason(type, field);
        if (reason != null) {
            throw new BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorField,
                    new List<Object>{ field.getLabel(), reason }
                )
            );
        }
        return field;
    }

    /** Whether `source` may be copied into `target` (R-BU4). */
    public static Boolean compatible(
        Schema.DescribeFieldResult target,
        Schema.DescribeFieldResult source
    ) {
        Schema.DisplayType to = target.getType();
        Schema.DisplayType given = source.getType();
        if (!WRITABLE.contains(to)) {
            return false;
        }
        if (to == Schema.DisplayType.REFERENCE) {
            if (given != Schema.DisplayType.REFERENCE) {
                return false;
            }
            Set<Schema.SObjectType> reachable = new Set<Schema.SObjectType>(
                target.getReferenceTo()
            );
            for (Schema.SObjectType parent : source.getReferenceTo()) {
                if (reachable.contains(parent)) {
                    return true;
                }
            }
            return false;
        }
        if (TEXT_TARGETS.contains(to)) {
            return TEXT_SOURCES.contains(given);
        }
        if (NUMBERS.contains(to)) {
            return NUMBERS.contains(given);
        }
        return to == given;
    }

    /** A value to set, as the field's own type, or a refusal naming the field. */
    public static Object typed(Schema.DescribeFieldResult field, Object raw) {
        BulkUpdateException refused = new BulkUpdateException(
            String.format(
                System.Label.Core_BulkUpdate_ErrorBadValue,
                new List<Object>{ field.getLabel() }
            )
        );
        if (raw == null || String.isBlank(String.valueOf(raw))) {
            throw refused;
        }
        String text = String.valueOf(raw).trim();
        try {
            switch on field.getType() {
                when BOOLEAN {
                    if (text.equalsIgnoreCase('true') || text.equalsIgnoreCase('false')) {
                        return Boolean.valueOf(text);
                    }
                    throw refused;
                }
                when INTEGER {
                    Decimal value = Decimal.valueOf(text);
                    if (value.stripTrailingZeros().scale() > 0) {
                        throw refused;
                    }
                    return value.intValue();
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(text);
                }
                when DATE {
                    Date parsed = Date.valueOf(text);
                    if (String.valueOf(parsed) != text) {
                        throw refused;
                    }
                    return parsed;
                }
                when DATETIME {
                    return (Datetime) JSON.deserialize('"' + text + '"', Datetime.class);
                }
                when REFERENCE {
                    Id value = Id.valueOf(text);
                    if (!field.getReferenceTo().contains(value.getSObjectType())) {
                        throw refused;
                    }
                    return value;
                }
                when PICKLIST, MULTIPICKLIST {
                    checkPicklist(field, text, refused);
                    return text;
                }
                when else {
                    String original = String.valueOf(raw);
                    if (field.getLength() > 0 && original.length() > field.getLength()) {
                        throw refused;
                    }
                    return original;
                }
            }
        } catch (BulkUpdateException known) {
            throw known;
        } catch (Exception unreadable) {
            throw refused;
        }
    }

    /**
     * A stored value as the text a transform step reads, in the form `fromText` reads back, so
     * a step that changes nothing gives the same value back: a date as `yyyy-MM-dd`, a date and
     * time as `yyyy-MM-dd HH:mm:ss` in the person's own time zone (which `Datetime.valueOf`
     * reads), and a number without exponent. Decided by the field's type, never by
     * `instanceof`, because in Apex a Date is also an instance of Datetime. Null stays null.
     */
    public static String toText(Schema.DescribeFieldResult field, Object value) {
        if (value == null) {
            return null;
        }
        Schema.DisplayType kind = field == null ? null : field.getType();
        if (kind == Schema.DisplayType.DATE) {
            Date day = (Date) value;
            return String.valueOf(day);
        }
        if (kind == Schema.DisplayType.DATETIME) {
            return ((Datetime) value).format('yyyy-MM-dd HH:mm:ss');
        }
        if (NUMBERS.contains(kind) && value instanceof Decimal) {
            return ((Decimal) value).toPlainString();
        }
        return String.valueOf(value);
    }

    /** Whether a target may be changed with transform steps: any writable type but a lookup (R-BU7). */
    public static Boolean canTransform(Schema.DescribeFieldResult field) {
        return WRITABLE.contains(field.getType()) &&
            field.getType() != Schema.DisplayType.REFERENCE;
    }

    /**
     * The text a transform produced, as the field's own type, read as an import reads a cell
     * (R-BU7): blank clears the field (a checkbox reads it as false), a checkbox takes true, yes
     * or 1 and false, no or 0, a number keeps only its digits, point and minus sign. Unlike an
     * import, a result the field cannot take is never shortened or guessed: it is refused,
     * naming the field and the value, so the record is journaled as Failed rather than saved
     * wrong. That includes a checkbox result that is none of those words.
     */
    public static Object fromText(Schema.DescribeFieldResult field, String text) {
        Schema.DisplayType kind = field.getType();
        if (kind == Schema.DisplayType.BOOLEAN) {
            String flag = text == null ? '' : text.trim().toLowerCase();
            if (CHECKED_WORDS.contains(flag)) {
                return true;
            }
            if (String.isBlank(flag) || UNCHECKED_WORDS.contains(flag)) {
                return false;
            }
            throw new BulkUpdateException(
                String.format(
                    System.Label.Core_BulkUpdate_ErrorStepResult,
                    new List<Object>{ field.getLabel(), text.abbreviate(80) }
                )
            );
        }
        if (String.isBlank(text)) {
            if (!field.isNillable()) {
                throw new BulkUpdateException(
                    String.format(
                        System.Label.Core_BulkUpdate_ErrorRequired,
                        new List<Object>{ field.getLabel() }
                    )
                );
            }
            return null;
        }
        BulkUpdateException refused = new BulkUpdateException(
            String.format(
                System.Label.Core_BulkUpdate_ErrorStepResult,
                new List<Object>{ field.getLabel(), text.abbreviate(80) }
            )
        );
        try {
            switch on kind {
                when INTEGER {
                    // The point is kept, so "1,250.00" is 1250 and "12.5" is refused, not 125.
                    Decimal whole = Decimal.valueOf(text.replaceAll('[^0-9\\.\\-]', ''));
                    if (whole.stripTrailingZeros().scale() > 0) {
                        throw refused;
                    }
                    return whole.intValue();
                }
                when DOUBLE, CURRENCY, PERCENT {
                    return Decimal.valueOf(text.replaceAll('[^0-9\\.\\-]', ''));
                }
                when DATE {
                    Date parsed = Date.valueOf(text.trim());
                    if (String.valueOf(parsed) != text.trim()) {
                        throw refused;
                    }
                    return parsed;
                }
                when DATETIME {
                    return Datetime.valueOf(text.trim());
                }
                when PICKLIST, MULTIPICKLIST {
                    checkPicklist(field, text, refused);
                    return text;
                }
                when else {
                    if (field.getLength() > 0 && text.length() > field.getLength()) {
                        throw refused;
                    }
                    return text;
                }
            }
        } catch (BulkUpdateException known) {
            throw known;
        } catch (Exception unreadable) {
            throw refused;
        }
    }

    /** Why no record of this object may be bulk updated, or null when its records may be. */
    @TestVisible
    private static String objectReason(Schema.DescribeSObjectResult described) {
        if (DataProtectedFields.isBookkeeping(described.getSObjectType())) {
            return System.Label.Core_BulkUpdate_ReasonBookkeeping;
        }
        if (described.isCustomSetting()) {
            return System.Label.Core_BulkUpdate_ReasonBookkeeping;
        }
        if (DataProtectedFields.isSetup(described.getSObjectType())) {
            return System.Label.Core_BulkUpdate_ReasonSetup;
        }
        if (!described.isUpdateable()) {
            return System.Label.Core_BulkUpdate_ReasonNoObjectAccess;
        }
        return null;
    }

    /** Why this field may not be bulk updated, or null when it may. */
    @TestVisible
    private static String fieldReason(Schema.SObjectType type, Schema.DescribeFieldResult field) {
        if (DataProtectedFields.isKeptByThePackage(type, field)) {
            return System.Label.Core_BulkUpdate_ReasonKept;
        }
        if (!field.isUpdateable() || !field.isAccessible()) {
            return System.Label.Core_BulkUpdate_ReasonNoFieldAccess;
        }
        if (!WRITABLE.contains(field.getType())) {
            return System.Label.Core_BulkUpdate_ReasonType;
        }
        return null;
    }

    private static Map<String, Schema.SObjectField> fieldMap(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap();
    }

    /** A restricted picklist takes only its active values; an open one takes any text. */
    private static void checkPicklist(
        Schema.DescribeFieldResult field,
        String text,
        BulkUpdateException refused
    ) {
        if (!field.isRestrictedPicklist()) {
            return;
        }
        Set<String> active = new Set<String>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (entry.isActive()) {
                active.add(entry.getValue());
            }
        }
        List<String> chosen = field.getType() == Schema.DisplayType.MULTIPICKLIST
            ? text.split(';')
            : new List<String>{ text };
        for (String value : chosen) {
            if (!active.contains(value)) {
                throw refused;
            }
        }
    }
}
