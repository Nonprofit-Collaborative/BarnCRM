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

    // ------------------------------------------------------------------ matching

    /**
     * A value held by more people or households than this is not used: an office switchboard
     * or a shared mailbox says nothing about whether two of them are the same.
     */
    @TestVisible
    private static final Integer MAX_OWNERS_PER_VALUE = 10;

    private static final String INDIVIDUAL = 'Individual';
    private static final String INDIVIDUAL_FIELD = 'IndividualId';

    private static Boolean contactCarriesIndividual;

    /** Whether Contact has IndividualId in this org, read by name (ADR-0013). */
    private static Boolean contactCarriesIndividual() {
        if (contactCarriesIndividual == null) {
            contactCarriesIndividual = Schema.SObjectType.Contact.fields.getMap()
                .containsKey(INDIVIDUAL_FIELD.toLowerCase());
        }
        return contactCarriesIndividual;
    }

    private static Boolean isIndividual(Schema.SObjectType type) {
        return type != null &&
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() == INDIVIDUAL;
    }

    /**
     * Whether a source's parent can be a record of this object: its lookup points there, or,
     * for people, at an Individual the contacts carry.
     */
    @TestVisible
    private static Boolean appliesTo(Source source, Schema.SObjectType target) {
        for (
            Schema.SObjectType referenced : source.objectType.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                )
                .fields.getMap()
                .get(source.parentField)
                .getDescribe()
                .getReferenceTo()
        ) {
            if (
                referenced == target ||
                (target == Contact.SObjectType &&
                isIndividual(referenced) &&
                contactCarriesIndividual())
            ) {
                return true;
            }
        }
        return false;
    }

    /** What the review list says about a pair a source found. */
    public static String reasonFor(Source source) {
        String format = source.normalization == EMAIL
            ? Label.Core_Duplicates_ReasonEmail
            : source.normalization == PHONE
                  ? Label.Core_Duplicates_ReasonPhone
                  : Label.Core_Duplicates_ReasonAddress;
        return String.format(format, new List<Object>{ source.label });
    }

    /**
     * The pairs the active sources find among these records, which must all be of one object
     * (people or accounts): each record paired with every other record of that object that
     * holds the same normalized value on the same source. Each pair carries the source's
     * reason and no rule. A pair may appear twice; DuplicateService.pairsToRecord folds it.
     */
    public static List<DuplicateService.Pair> pairsFor(List<Id> recordIds) {
        List<DuplicateService.Pair> result = new List<DuplicateService.Pair>();
        if (recordIds == null || recordIds.isEmpty()) {
            return result;
        }
        Schema.SObjectType target = recordIds[0].getSObjectType();
        Set<Id> records = new Set<Id>(recordIds);
        for (Source source : usableSources()) {
            if (!appliesTo(source, target)) {
                continue;
            }
            try {
                result.addAll(pairsOn(source, target, records));
            } catch (Exception caught) {
                // One source that cannot be read is logged and counted; the rest still run.
                DuplicateService.failureCount++;
                ErrorLogger.log(caught, CONTEXT + source.developerName);
            }
        }
        return result;
    }

    private static final String CONTEXT = 'Duplicate scan: matching through source ';
    private static final String IMPORT_CONTEXT = 'Import: matching through source ';

    /** The import attributes of a person that hold a value of each kind, as Contact names. */
    private static final List<String> EMAIL_ATTRIBUTES = new List<String>{ 'Email' };
    private static final List<String> PHONE_ATTRIBUTES = new List<String>{
        'Phone',
        'MobilePhone',
        'HomePhone',
        'OtherPhone'
    };
    private static final Map<String, String> ADDRESS_ATTRIBUTES = new Map<String, String>{
        'MailingStreet' => 'MailingPostalCode',
        'OtherStreet' => 'OtherPostalCode'
    };

    /**
     * For each incoming person of an import, the existing records of the target object (Contact,
     * or Account for person accounts) that hold one of its values on an active source (R-IT16):
     * its email, its phones, its mailing and other addresses, normalized as the source says. A
     * value held by more than ten records is not used. Values are keyed by Contact attribute
     * name. One lookup per source for the whole list. A source that cannot be read is logged and
     * skipped.
     */
    public static List<Set<Id>> holdersOfPeople(
        Schema.SObjectType target,
        List<Map<String, String>> people
    ) {
        List<Set<Id>> result = new List<Set<Id>>();
        Map<String, List<Set<String>>> keysByKind = new Map<String, List<Set<String>>>{
            EMAIL => new List<Set<String>>(),
            PHONE => new List<Set<String>>(),
            ADDRESS => new List<Set<String>>()
        };
        for (Map<String, String> values : people) {
            result.add(new Set<Id>());
            Map<String, String> given = values == null ? new Map<String, String>() : values;
            keysByKind.get(EMAIL).add(keysOf(EMAIL, given, EMAIL_ATTRIBUTES));
            keysByKind.get(PHONE).add(keysOf(PHONE, given, PHONE_ATTRIBUTES));
            Set<String> addresses = new Set<String>();
            for (String street : ADDRESS_ATTRIBUTES.keySet()) {
                String found = address(
                    given.get(street),
                    given.get(ADDRESS_ATTRIBUTES.get(street))
                );
                if (found != null) {
                    addresses.add(found);
                }
            }
            keysByKind.get(ADDRESS).add(addresses);
        }
        for (Source source : usableSources()) {
            if (!appliesTo(source, target)) {
                continue;
            }
            List<Set<String>> perPerson = keysByKind.get(source.normalization);
            Set<String> all = new Set<String>();
            for (Set<String> keys : perPerson) {
                all.addAll(keys);
            }
            if (all.isEmpty()) {
                continue;
            }
            try {
                Map<String, Set<Id>> holders = ownersOf(source, target, all);
                for (Integer index = 0; index < perPerson.size(); index++) {
                    for (String key : perPerson[index]) {
                        Set<Id> found = holders.get(key);
                        if (found != null && found.size() <= MAX_OWNERS_PER_VALUE) {
                            result[index].addAll(found);
                        }
                    }
                }
            } catch (Exception caught) {
                ErrorLogger.log(caught, IMPORT_CONTEXT + source.developerName);
            }
        }
        return result;
    }

    private static Set<String> keysOf(
        String normalization,
        Map<String, String> values,
        List<String> attributes
    ) {
        Set<String> keys = new Set<String>();
        for (String attribute : attributes) {
            String found = key(normalization, values.get(attribute), null);
            if (found != null) {
                keys.add(found);
            }
        }
        return keys;
    }

    private static List<DuplicateService.Pair> pairsOn(
        Source source,
        Schema.SObjectType target,
        Set<Id> records
    ) {
        List<DuplicateService.Pair> result = new List<DuplicateService.Pair>();
        Map<String, Set<Id>> heldHere = owners(
            source,
            target,
            MatchSourceSelector.rowsByParents(source, parentIdsOf(target, records)),
            records
        );
        if (heldHere.isEmpty()) {
            return result;
        }
        Map<String, Set<Id>> holders = ownersOf(source, target, heldHere.keySet());
        String reason = reasonFor(source);
        for (String key : heldHere.keySet()) {
            Set<Id> everyone = holders.get(key);
            if (everyone == null || everyone.size() > MAX_OWNERS_PER_VALUE) {
                continue;
            }
            for (Id mine : heldHere.get(key)) {
                for (Id other : everyone) {
                    if (other != mine) {
                        DuplicateService.Pair pair = new DuplicateService.Pair(mine, other, null);
                        pair.reason = reason;
                        result.add(pair);
                    }
                }
            }
        }
        return result;
    }

    /**
     * Every record of the target object holding each of these keys on this source, found
     * with one bounded query and compared exactly after normalization.
     */
    public static Map<String, Set<Id>> ownersOf(
        Source source,
        Schema.SObjectType target,
        Set<String> keys
    ) {
        Set<String> equalTo = new Set<String>();
        Set<String> patterns = new Set<String>();
        String likeField = null;
        for (String key : keys) {
            if (source.normalization == EMAIL) {
                equalTo.add(key);
            } else if (source.normalization == PHONE) {
                likeField = source.valueField;
                patterns.add(spread(key));
            } else {
                likeField = source.postalField;
                patterns.add(spread(key.substringAfterLast('|')).removeStart('%'));
            }
        }
        List<SObject> rows = MatchSourceSelector.rowsByValues(
            source,
            equalTo,
            likeField,
            new List<String>(patterns)
        );
        Map<String, Set<Id>> found = owners(source, target, rows, null);
        Map<String, Set<Id>> result = new Map<String, Set<Id>>();
        for (String key : keys) {
            if (found.containsKey(key)) {
                result.put(key, found.get(key));
            }
        }
        return result;
    }

    /**
     * A LIKE pattern matching the characters in order with anything between them, so (555)
     * 123-4567 and +1 555.123.4567 are both read for 5551234567. Letters and digits only.
     */
    @TestVisible
    private static String spread(String value) {
        List<String> characters = value.replaceAll('[^A-Za-z0-9]', '').split('');
        return '%' + String.join(characters, '%') + '%';
    }

    /** The records whose source rows are looked up: the records, and their Individuals. */
    private static Set<Id> parentIdsOf(Schema.SObjectType target, Set<Id> records) {
        Set<Id> parents = new Set<Id>(records);
        if (target == Contact.SObjectType && contactCarriesIndividual()) {
            for (Contact person : MatchSourceSelector.contactsWithIndividuals(records, null)) {
                parents.add((Id) person.get(INDIVIDUAL_FIELD));
            }
        }
        return parents;
    }

    /**
     * Normalized key to the target records that hold it, out of source rows. A parent of the
     * target object is itself; an Individual is every contact carrying it; anything else is
     * skipped. With `onlyThese`, other records are left out.
     */
    private static Map<String, Set<Id>> owners(
        Source source,
        Schema.SObjectType target,
        List<SObject> rows,
        Set<Id> onlyThese
    ) {
        Set<Id> individuals = new Set<Id>();
        for (SObject row : rows) {
            Id parent = (Id) row.get(source.parentField);
            if (parent != null && isIndividual(parent.getSObjectType())) {
                individuals.add(parent);
            }
        }
        Map<Id, Set<Id>> contactsByIndividual = new Map<Id, Set<Id>>();
        if (target == Contact.SObjectType && !individuals.isEmpty() && contactCarriesIndividual()) {
            for (Contact person : MatchSourceSelector.contactsWithIndividuals(null, individuals)) {
                Id individual = (Id) person.get(INDIVIDUAL_FIELD);
                if (!contactsByIndividual.containsKey(individual)) {
                    contactsByIndividual.put(individual, new Set<Id>());
                }
                contactsByIndividual.get(individual).add(person.Id);
            }
        }
        Map<String, Set<Id>> result = new Map<String, Set<Id>>();
        for (SObject row : rows) {
            Id parent = (Id) row.get(source.parentField);
            String key = key(
                source.normalization,
                text(row.get(source.valueField)),
                source.postalField == null ? null : text(row.get(source.postalField))
            );
            if (parent == null || key == null) {
                continue;
            }
            Set<Id> holders = parent.getSObjectType() == target
                ? new Set<Id>{ parent }
                : contactsByIndividual.get(parent);
            if (holders == null) {
                continue;
            }
            for (Id holder : holders) {
                if (onlyThese == null || onlyThese.contains(holder)) {
                    if (!result.containsKey(key)) {
                        result.put(key, new Set<Id>());
                    }
                    result.get(key).add(holder);
                }
            }
        }
        return result;
    }

    private static String text(Object value) {
        return value == null ? null : String.valueOf(value);
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
