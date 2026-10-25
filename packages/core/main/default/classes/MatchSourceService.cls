/**
 * Match sources: related records whose values pair people or households as likely duplicates
 * (ADR-NEXT, `NEXT-related-record-matching.md`; canonical model Section 13, Match Source).
 *
 * A duplicate rule compares fields on the record itself, so an email kept only on a related
 * record is never compared. A source names that related object, the field holding the value,
 * the lookup to its person or household, and how the value is made comparable. This class
 * reads the sources the org can use, normalizes values, and checks a source an administrator
 * saves on the Custom metadata page.
 *
 * No object a source names is referenced at compile time: a source is resolved through
 * describe and skipped when its object or fields are not in the org (ADR-0013, ADR-0110).
 */
public with sharing class MatchSourceService {
    public static final String EMAIL = 'Email';
    public static final String PHONE = 'Phone';
    public static final String ADDRESS = 'Address';

    /** A phone number with fewer digits than this says too little to compare. */
    private static final Integer MIN_PHONE_DIGITS = 7;

    /** Street words shortened so the common ways of writing a street compare equal. */
    private static final Map<String, String> STREET_WORDS = new Map<String, String>{
        'street' => 'st',
        'avenue' => 'ave',
        'av' => 'ave',
        'road' => 'rd',
        'drive' => 'dr',
        'boulevard' => 'blvd',
        'lane' => 'ln',
        'court' => 'ct',
        'place' => 'pl',
        'terrace' => 'ter',
        'circle' => 'cir',
        'highway' => 'hwy',
        'parkway' => 'pkwy',
        'square' => 'sq',
        'apartment' => 'apt',
        'suite' => 'ste',
        'north' => 'n',
        'south' => 's',
        'east' => 'e',
        'west' => 'w',
        'northeast' => 'ne',
        'northwest' => 'nw',
        'southeast' => 'se',
        'southwest' => 'sw'
    };

    /** One usable source: its object and fields resolved in this org. */
    public class Source {
        public String developerName;
        public String label;
        public Schema.SObjectType objectType;
        public String objectName;
        public String valueField;
        public String postalField;
        public String parentField;
        public String normalization;
    }

    /**
     * The active sources this org can use: the object exists, every field it names exists, and
     * the running user can read them. A source that fails any of these is skipped, never an
     * error, which is what lets Core ship contact point sources to a Platform-only org.
     */
    public static List<Source> usableSources() {
        List<Source> result = new List<Source>();
        for (Match_Source__mdt row : MatchSourceSelector.selectActiveSources()) {
            Source source = resolve(row);
            if (source != null) {
                result.add(source);
            }
        }
        return result;
    }

    private static Source resolve(Match_Source__mdt row) {
        Schema.SObjectType type = NamespaceUtil.objectType(row.Object_Name__c);
        if (type == null || String.isBlank(row.Normalization__c)) {
            return null;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        if (!described.isAccessible()) {
            return null;
        }
        Map<String, Schema.SObjectField> fields = described.fields.getMap();
        Schema.SObjectField value = field(fields, row.Value_Field__c);
        Schema.SObjectField parent = field(fields, row.Parent_Field__c);
        Schema.SObjectField postal = field(fields, row.Postal_Code_Field__c);
        Boolean needsPostal = row.Normalization__c == ADDRESS;
        if (
            !readable(value) ||
            !readable(parent) ||
            parent.getDescribe().getType() != Schema.DisplayType.REFERENCE ||
            (needsPostal && !readable(postal))
        ) {
            return null;
        }
        Source source = new Source();
        source.developerName = row.DeveloperName;
        source.label = row.MasterLabel;
        source.objectType = type;
        source.objectName = described.getName();
        source.valueField = value.getDescribe().getName();
        source.parentField = parent.getDescribe().getName();
        source.postalField = needsPostal ? postal.getDescribe().getName() : null;
        source.normalization = row.Normalization__c;
        return source;
    }

    /** A field by the name a row gives, unprefixed or not, or null. */
    @TestVisible
    private static Schema.SObjectField field(Map<String, Schema.SObjectField> fields, String name) {
        if (String.isBlank(name)) {
            return null;
        }
        String trimmed = name.trim().toLowerCase();
        Schema.SObjectField found = fields.get(NamespaceUtil.qualify(trimmed));
        return found != null ? found : fields.get(trimmed);
    }

    private static Boolean readable(Schema.SObjectField token) {
        return token != null && token.getDescribe().isAccessible();
    }

    // ------------------------------------------------------------------ normalization

    /**
     * The comparable form of a value under a normalization, or null when the value says too
     * little to compare. `postal` is read only for Address.
     */
    public static String key(String normalization, String value, String postal) {
        if (normalization == EMAIL) {
            return email(value);
        }
        if (normalization == PHONE) {
            return phone(value);
        }
        if (normalization == ADDRESS) {
            return address(value, postal);
        }
        return null;
    }

    /** Trimmed and lower case; null unless it looks like an email. */
    public static String email(String value) {
        String trimmed = value == null ? '' : value.trim().toLowerCase();
        return trimmed.contains('@') ? trimmed : null;
    }

    /**
     * Digits only. An 11 digit number starting 1 loses the 1, so a North American number
     * written with its country code compares equal to the same number without it.
     */
    public static String phone(String value) {
        String digits = value == null ? '' : value.replaceAll('[^0-9]', '');
        if (digits.length() == 11 && digits.startsWith('1')) {
            digits = digits.substring(1);
        }
        return digits.length() < MIN_PHONE_DIGITS ? null : digits;
    }

    /** The folded street and the postal code, or null unless both are there. */
    public static String address(String street, String postal) {
        String folded = street(street);
        String code = postalCode(postal);
        return folded == null || code == null ? null : folded + '|' + code;
    }

    /** Lower case, punctuation gone, whitespace collapsed, common words shortened. */
    @TestVisible
    private static String street(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        List<String> words = new List<String>();
        for (
            String word : value.toLowerCase()
                .replaceAll('[^a-z0-9]+', ' ')
                .normalizeSpace()
                .split(' ')
        ) {
            if (String.isNotBlank(word)) {
                words.add(STREET_WORDS.containsKey(word) ? STREET_WORDS.get(word) : word);
            }
        }
        return words.isEmpty() ? null : String.join(words, ' ');
    }

    /** No whitespace, upper case; a US ZIP+4 is cut to its five digits. */
    @TestVisible
    private static String postalCode(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String code = value.deleteWhitespace().toUpperCase();
        if (Pattern.matches('[0-9]{5}-?[0-9]{4}', code)) {
            code = code.left(5);
        }
        return code;
    }

    // ------------------------------------------------------------------ saving a source

    /** Checks a source the Custom metadata page is about to save, against this org. */
    public class Validator implements CustomMetadataManagerService.RowValidator {
        public void validate(Map<String, Object> values) {
            MatchSourceService.validate(values);
        }
    }

    /**
     * Throws with a message the page shows as it is unless the object exists, the value field
     * exists, the parent field is a lookup, and an address source names a postal code field
     * that exists.
     */
    public static void validate(Map<String, Object> values) {
        String objectName = (String) values.get('Object_Name__c');
        Schema.SObjectType type = NamespaceUtil.objectType(objectName);
        if (type == null) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                String.format(Label.Core_MatchSource_NoSuchObject, new List<Object>{ objectName })
            );
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        Map<String, Schema.SObjectField> fields = described.fields.getMap();
        requireField(fields, (String) values.get('Value_Field__c'), described.getLabel());
        Schema.SObjectField parent = requireField(
            fields,
            (String) values.get('Parent_Field__c'),
            described.getLabel()
        );
        if (parent.getDescribe().getType() != Schema.DisplayType.REFERENCE) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                String.format(
                    Label.Core_MatchSource_NotALookup,
                    new List<Object>{ values.get('Parent_Field__c'), described.getLabel() }
                )
            );
        }
        if (values.get('Normalization__c') == ADDRESS) {
            String postal = (String) values.get('Postal_Code_Field__c');
            if (String.isBlank(postal)) {
                throw new CustomMetadataManagerService.CustomMetadataManagerException(
                    Label.Core_MatchSource_PostalRequired
                );
            }
            requireField(fields, postal, described.getLabel());
        }
    }

    private static Schema.SObjectField requireField(
        Map<String, Schema.SObjectField> fields,
        String name,
        String objectLabel
    ) {
        Schema.SObjectField found = field(fields, name);
        if (found == null) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                String.format(
                    Label.Core_MatchSource_NoSuchField,
                    new List<Object>{ name, objectLabel }
                )
            );
        }
        return found;
    }
}
