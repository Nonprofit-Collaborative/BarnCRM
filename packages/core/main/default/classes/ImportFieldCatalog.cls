/**
 * The org's own fields a column can be mapped to on a person or an organization, besides the
 * wizard's fixed list (R-IT11, ADR-NEXT `NEXT-import-record-id-matching-and-match-only.md`).
 *
 * Read from describe, for the running user: a field is offered when the user may read it and
 * create or edit it, it holds a value a spreadsheet cell can carry, and it is nobody else's to
 * write (a formula, roll-up or auto number, a system field, or a field the package keeps for
 * itself). The import writes any of them through the same describe checks as every other
 * attribute, so this list only decides what the picker offers.
 */
public with sharing class ImportFieldCatalog {
    /** The kinds of field a cell's text converts to (see ImportRowProcessor.convert). */
    private static final Set<Schema.DisplayType> TYPES_OFFERED = new Set<Schema.DisplayType>{
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.COMBOBOX,
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.DATE,
        Schema.DisplayType.DATETIME,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.ENCRYPTEDSTRING,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.MULTIPICKLIST,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.STRING,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.URL
    };

    /** System fields an administrator does not load from a file. */
    private static final Set<String> SYSTEM_FIELDS = new Set<String>{
        'cleanstatus',
        'emailbounceddate',
        'emailbouncedreason',
        'jigsaw'
    };

    /**
     * The package's own bookkeeping fields, by local name: written by the import itself, the
     * sample data, or the household automation (R-IB3, R-M5), never by a column.
     */
    private static final Set<String> PACKAGE_FIELDS = new Set<String>{
        'created_by_import_batch__c',
        'sample_data__c',
        'sample_data_key__c',
        'custom_name__c',
        'member_count__c',
        'household_formal_greeting__c',
        'household_informal_greeting__c',
        'household_role__c'
    };

    /**
     * The package's fields on Account that describe a person or a household, not an
     * organization, by local name.
     */
    private static final Set<String> NOT_ORGANIZATION_FIELDS = new Set<String>{
        'alternate_email__c',
        'anniversary__c',
        'deceased__c',
        'exclude_from_greetings__c',
        'exclude_from_household_name__c',
        'personal_email__c',
        'preferred_email__c',
        'preferred_name__c',
        'work_email__c',
        'firstname',
        'lastname',
        'middlename',
        'suffix',
        'salutation',
        'ispersonaccount'
    };

    /** A person's fields, in contact terms whatever the person mode (R-IT3). */
    public static List<ImportMapping.Target> personFields() {
        return offered(Contact.SObjectType, new Set<String>());
    }

    /** An organization's fields: the account's own, not its person account fields. */
    public static List<ImportMapping.Target> organizationFields() {
        Set<String> skipped = new Set<String>(NOT_ORGANIZATION_FIELDS);
        Map<String, Schema.SObjectField> contactFields = Contact.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
        for (
            Schema.SObjectField field : Account.SObjectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap()
                .values()
        ) {
            String name = field.getDescribe().getLocalName().toLowerCase();
            // PersonEmail, PersonMailingCity and the __pc fields are a person account's.
            if (
                name.endsWith('__pc') ||
                (name.startsWith('person') && contactFields.containsKey(name.substring(6)))
            ) {
                skipped.add(name);
            }
        }
        return offered(Account.SObjectType, skipped);
    }

    private static List<ImportMapping.Target> offered(
        Schema.SObjectType type,
        Set<String> skipped
    ) {
        List<FieldOption> options = new List<FieldOption>();
        for (
            Schema.SObjectField field : type.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields.getMap()
                .values()
        ) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            String localName = describe.getLocalName().toLowerCase();
            if (
                isOffered(describe) &&
                !skipped.contains(localName) &&
                !SYSTEM_FIELDS.contains(localName) &&
                !PACKAGE_FIELDS.contains(localName)
            ) {
                options.add(new FieldOption(describe));
            }
        }
        options.sort();
        List<ImportMapping.Target> result = new List<ImportMapping.Target>();
        for (FieldOption option : options) {
            result.add(new ImportMapping.Target(option.name, option.label));
        }
        return result;
    }

    /** Whether the user may load a cell into this field at all. */
    private static Boolean isOffered(Schema.DescribeFieldResult describe) {
        return describe.isAccessible() &&
            (describe.isCreateable() || describe.isUpdateable()) &&
            !describe.isCalculated() &&
            !describe.isAutoNumber() &&
            !describe.isDeprecatedAndHidden() &&
            TYPES_OFFERED.contains(describe.getType());
    }

    /** A field as the picker lists it, in label order. */
    private class FieldOption implements Comparable {
        String name;
        String label;

        FieldOption(Schema.DescribeFieldResult describe) {
            name = describe.getName();
            label = describe.getLabel();
        }

        public Integer compareTo(Object other) {
            return label.compareTo(((FieldOption) other).label);
        }
    }
}
