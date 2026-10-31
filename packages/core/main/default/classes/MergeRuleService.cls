/**
 * Which value wins when two people are merged (C-51, canonical model R-DP8, ADR-0145 advanced
 * duplicate management).
 *
 * Each person field follows its active Merge Rule row (`Merge_Rule__mdt`), and a field with no
 * row follows the Merge Rule For Other Fields setting (Not blank when unset):
 *
 * - Keep master: the survivor's value, even when blank.
 * - Not blank: the survivor's value, or the other's when the survivor's is blank.
 * - Most recent: the value of the record changed last.
 * - Oldest record: the value of the record created first.
 * - Most complete: the longer value; the survivor's on a tie.
 *
 * Under every rule but Keep master a blank never wins over a value. A rule naming
 * `MailingAddress` or `OtherAddress` takes the whole address from one record, so a street never
 * lands with another record's city. The household and the owner are never changed by a rule.
 */
public with sharing class MergeRuleService {
    public static final String KEEP_MASTER = 'Keep master';
    public static final String NOT_BLANK = 'Not blank';
    public static final String MOST_RECENT = 'Most recent';
    public static final String OLDEST = 'Oldest record';
    public static final String MOST_COMPLETE = 'Most complete';
    public static final Set<String> RULES = new Set<String>{
        KEEP_MASTER,
        NOT_BLANK,
        MOST_RECENT,
        OLDEST,
        MOST_COMPLETE
    };

    /** The addresses a rule may name, by the prefix their parts share. */
    public static final Map<String, String> ADDRESSES = new Map<String, String>{
        'mailingaddress' => 'Mailing',
        'otheraddress' => 'Other'
    };
    private static final List<String> ADDRESS_PARTS = new List<String>{
        'Street',
        'City',
        'State',
        'StateCode',
        'PostalCode',
        'Country',
        'CountryCode',
        'Latitude',
        'Longitude',
        'GeocodeAccuracy'
    };

    /** Never changed by a rule: the household and owner stay the survivor's (R-DP8). */
    private static final Set<String> NEVER = new Set<String>{
        'accountid',
        'ownerid',
        'recordtypeid',
        'masterrecordid',
        'individualid'
    };

    @TestVisible
    private static List<Merge_Rule__mdt> rowsForTest;

    /** The Merge Rule For Other Fields setting; blank or unknown reads as Not blank. */
    public static String defaultRule() {
        String configured = SettingsService.getSettings().Merge_Default_Rule__c;
        return RULES.contains(configured) ? configured : NOT_BLANK;
    }

    /** The active rules by field name in lower case; a row with an unknown rule is skipped. */
    public static Map<String, String> rulesByField() {
        Map<String, String> byField = new Map<String, String>();
        List<Merge_Rule__mdt> rows = rowsForTest != null
            ? rowsForTest
            : Merge_Rule__mdt.getAll().values();
        for (Merge_Rule__mdt row : rows) {
            if (
                row.Active__c &&
                String.isNotBlank(row.Field_Name__c) &&
                RULES.contains(row.Rule__c)
            ) {
                byField.put(row.Field_Name__c.trim().toLowerCase(), row.Rule__c);
            }
        }
        return byField;
    }

    /**
     * The person fields a merge may change for the running user: readable, editable, stored
     * (not formula or auto number), and not the household, owner or record type.
     */
    public static List<String> mergeableFields() {
        List<String> names = new List<String>();
        for (Schema.SObjectField token : Schema.SObjectType.Contact.fields.getMap().values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (
                field.isAccessible() &&
                field.isUpdateable() &&
                !field.isCalculated() &&
                !field.isAutoNumber() &&
                !NEVER.contains(field.getName().toLowerCase())
            ) {
                names.add(field.getName());
            }
        }
        names.sort();
        return names;
    }

    /**
     * The values the survivor takes from the merge: each field whose winning value differs from
     * the survivor's, mapped to that value. Both records must carry the fields, `CreatedDate`
     * and `LastModifiedDate`.
     */
    public static Map<String, Object> winningValues(
        SObject master,
        SObject other,
        List<String> fields
    ) {
        Map<String, String> rules = rulesByField();
        String fallback = defaultRule();
        Map<String, Object> result = new Map<String, Object>();
        Map<String, List<String>> addressParts = new Map<String, List<String>>();
        for (String field : fields) {
            String address = addressOf(field);
            if (address != null) {
                if (!addressParts.containsKey(address)) {
                    addressParts.put(address, new List<String>());
                }
                addressParts.get(address).add(field);
                continue;
            }
            String rule = rules.containsKey(field.toLowerCase())
                ? rules.get(field.toLowerCase())
                : fallback;
            Boolean takeOther = takesOther(
                rule,
                master.get(field),
                other.get(field),
                master,
                other
            );
            if (takeOther && !sameValue(master.get(field), other.get(field))) {
                result.put(field, other.get(field));
            }
        }
        for (String address : addressParts.keySet()) {
            List<String> parts = addressParts.get(address);
            String rule = rules.containsKey(address) ? rules.get(address) : fallback;
            if (takesOther(rule, joined(master, parts), joined(other, parts), master, other)) {
                for (String part : parts) {
                    if (!sameValue(master.get(part), other.get(part))) {
                        result.put(part, other.get(part));
                    }
                }
            }
        }
        return result;
    }

    /** Whether the other record's value wins over the survivor's under this rule. */
    @TestVisible
    private static Boolean takesOther(
        String rule,
        Object masterValue,
        Object otherValue,
        SObject master,
        SObject other
    ) {
        if (rule == KEEP_MASTER || isBlank(otherValue)) {
            return false;
        }
        if (isBlank(masterValue)) {
            return true;
        }
        if (rule == MOST_RECENT) {
            return later(
                (Datetime) other.get('LastModifiedDate'),
                (Datetime) master.get('LastModifiedDate')
            );
        }
        if (rule == OLDEST) {
            return later((Datetime) master.get('CreatedDate'), (Datetime) other.get('CreatedDate'));
        }
        if (rule == MOST_COMPLETE) {
            return String.valueOf(otherValue).length() > String.valueOf(masterValue).length();
        }
        return false;
    }

    private static Boolean later(Datetime first, Datetime second) {
        return first != null && second != null && first > second;
    }

    /** The lower case name of the address a field belongs to, or null. */
    private static String addressOf(String field) {
        for (String address : ADDRESSES.keySet()) {
            String prefix = ADDRESSES.get(address);
            for (String part : ADDRESS_PARTS) {
                if (field.equalsIgnoreCase(prefix + part)) {
                    return address;
                }
            }
        }
        return null;
    }

    /** An address's filled parts as one value, so the rules can weigh it as a whole. */
    private static String joined(SObject record, List<String> parts) {
        List<String> values = new List<String>();
        for (String part : parts) {
            Object value = record.get(part);
            if (!isBlank(value)) {
                values.add(String.valueOf(value));
            }
        }
        return String.join(values, ' ');
    }

    private static Boolean isBlank(Object value) {
        return value == null || (value instanceof String && String.isBlank((String) value));
    }

    private static Boolean sameValue(Object first, Object second) {
        if (first instanceof String && second instanceof String) {
            return ((String) first).equals((String) second);
        }
        return first == second;
    }

    // ------------------------------------------------------------------ saving a rule

    /** The custom metadata manager's check of a Merge Rule save (ADR-0085). */
    public class Validator implements CustomMetadataManagerService.RowValidator {
        public void validate(Map<String, Object> values) {
            MergeRuleService.validate(values);
        }
    }

    /**
     * Refuses a rule for a field that does not exist on people, that the merge never changes
     * (the household, owner, record type) or that cannot be edited, and an unknown rule.
     */
    public static void validate(Map<String, Object> values) {
        String fieldName = values == null ? null : (String) values.get('Field_Name__c');
        String rule = values == null ? null : (String) values.get('Rule__c');
        if (rule != null && !RULES.contains(rule)) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                Label.Core_DuplicateManagement_RuleUnknown
            );
        }
        String name = fieldName == null ? '' : fieldName.trim().toLowerCase();
        if (ADDRESSES.containsKey(name)) {
            return;
        }
        Schema.SObjectField token = Schema.SObjectType.Contact.fields.getMap().get(name);
        Schema.DescribeFieldResult field = token == null ? null : token.getDescribe();
        if (
            field == null ||
            NEVER.contains(name) ||
            !field.isUpdateable() ||
            field.isCalculated()
        ) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                String.format(
                    Label.Core_DuplicateManagement_RuleFieldInvalid,
                    new List<Object>{ fieldName }
                )
            );
        }
    }
}
