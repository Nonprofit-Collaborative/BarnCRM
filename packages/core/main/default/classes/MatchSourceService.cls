/**
 * Match sources: related records whose values pair people or households as likely duplicates
 * (ADR-0133, `0133-related-record-matching.md`; canonical model Section 13, Match Source).
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

    /** The field on each target object naming the Individual behind a person. */
    private static final Map<Schema.SObjectType, String> INDIVIDUAL_FIELDS = new Map<Schema.SObjectType, String>{
        Contact.SObjectType => 'IndividualId',
        Account.SObjectType => 'PersonIndividualId'
    };

    private static Map<Schema.SObjectType, String> individualFieldByTarget = new Map<Schema.SObjectType, String>();

    /**
     * The field naming a person's Individual on the target object, IndividualId on Contact or
     * PersonIndividualId on Account, or null when the org does not have it (no data
     * protection, or no person accounts). Read by name (ADR-0013).
     */
    @TestVisible
    private static String individualFieldOf(Schema.SObjectType target) {
        if (!individualFieldByTarget.containsKey(target)) {
            String name = INDIVIDUAL_FIELDS.get(target);
            Boolean present =
                name != null &&
                target.getDescribe(SObjectDescribeOptions.DEFERRED)
                    .fields.getMap()
                    .containsKey(name.toLowerCase());
            individualFieldByTarget.put(target, present ? name : null);
        }
        return individualFieldByTarget.get(target);
    }

    private static Boolean isIndividual(Schema.SObjectType type) {
        return type != null &&
            type.getDescribe(SObjectDescribeOptions.DEFERRED).getName() == INDIVIDUAL;
    }

    /**
     * Whether a source's parent can be a record of this object: its lookup points there, or at
     * an Individual the target's records carry (contacts, or person accounts).
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
                (isIndividual(referenced) && individualFieldOf(target) != null)
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
        Map<Id, Id> households = householdsToTellApart(source, target, heldHere, holders);
        String reason = reasonFor(source);
        for (String key : heldHere.keySet()) {
            Set<Id> everyone = holders.get(key);
            if (everyone == null || everyone.size() > MAX_OWNERS_PER_VALUE) {
                continue;
            }
            for (Id mine : heldHere.get(key)) {
                for (Id other : everyone) {
                    if (other != mine && !sameHousehold(households, mine, other)) {
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
     * For a phone or address source over people, each person's household, so two people of
     * one household are not paired: sharing a home phone or an address is what a household
     * is. An email is personal, so an email source pairs them still, and so does any source
     * over accounts. Empty when nothing is to be told apart.
     */
    private static Map<Id, Id> householdsToTellApart(
        Source source,
        Schema.SObjectType target,
        Map<String, Set<Id>> heldHere,
        Map<String, Set<Id>> holders
    ) {
        if (source.normalization == EMAIL || target != Contact.SObjectType) {
            return new Map<Id, Id>();
        }
        Set<Id> people = new Set<Id>();
        for (String key : heldHere.keySet()) {
            people.addAll(heldHere.get(key));
            if (holders.containsKey(key)) {
                people.addAll(holders.get(key));
            }
        }
        return HouseholdService.getHouseholdIdsFor(people);
    }

    private static Boolean sameHousehold(Map<Id, Id> households, Id first, Id second) {
        Id home = households.get(first);
        return home != null && home == households.get(second);
    }

    /** The most LIKE clauses sent in one query; more go in further queries. */
    @TestVisible
    private static final Integer MAX_PATTERNS_PER_QUERY = 100;

    /**
     * Every record of the target object holding each of these keys on this source, found with
     * bounded queries and compared exactly after normalization: emails by equality in one
     * query, phones and addresses by LIKE clauses, at most 100 to a query.
     */
    public static Map<String, Set<Id>> ownersOf(
        Source source,
        Schema.SObjectType target,
        Set<String> keys
    ) {
        List<SObject> rows = new List<SObject>();
        if (source.normalization == EMAIL) {
            rows.addAll(MatchSourceSelector.rowsByValues(source, keys, null));
        } else {
            Map<String, Map<String, String>> clauses = new Map<String, Map<String, String>>();
            for (String key : keys) {
                Map<String, String> clause = likeClause(source, key);
                clauses.put(String.join(clause.values(), '|'), clause);
            }
            List<Map<String, String>> batch = new List<Map<String, String>>();
            for (Map<String, String> clause : clauses.values()) {
                batch.add(clause);
                if (batch.size() == MAX_PATTERNS_PER_QUERY) {
                    rows.addAll(MatchSourceSelector.rowsByValues(source, null, batch));
                    batch = new List<Map<String, String>>();
                }
            }
            if (!batch.isEmpty()) {
                rows.addAll(MatchSourceSelector.rowsByValues(source, null, batch));
            }
        }
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

    /** The words normalization writes in place of others; a stored street may not hold them. */
    private static final Set<String> SHORTENED = new Set<String>(STREET_WORDS.values());

    /**
     * The LIKE clause that reads every row which could hold this key, by field. A phone: its
     * digits in order in the value field. An address: its postal code in the postal field and,
     * to keep a common postal code from reading thousands of rows, the street's first word
     * that normalization leaves as written (usually the house number) in the value field. Such
     * a word is a run of letters and digits of the stored street, so no row that matches is
     * missed; a word normalization may have shortened ("st" for "Street") is never used.
     */
    @TestVisible
    private static Map<String, String> likeClause(Source source, String key) {
        if (source.normalization == PHONE) {
            return new Map<String, String>{ source.valueField => spread(key) };
        }
        Map<String, String> clause = new Map<String, String>{
            source.postalField => spread(key.substringAfterLast('|')).removeStart('%')
        };
        for (String word : key.substringBeforeLast('|').split(' ')) {
            if (String.isNotBlank(word) && !SHORTENED.contains(word)) {
                clause.put(source.valueField, '%' + word + '%');
                break;
            }
        }
        return clause;
    }

    /** The records whose source rows are looked up: the records, and their Individuals. */
    private static Set<Id> parentIdsOf(Schema.SObjectType target, Set<Id> records) {
        Set<Id> parents = new Set<Id>(records);
        String individualField = individualFieldOf(target);
        if (individualField != null) {
            for (
                SObject holder : MatchSourceSelector.holdersOfIndividuals(
                    target,
                    individualField,
                    records,
                    null
                )
            ) {
                parents.add((Id) holder.get(individualField));
            }
        }
        return parents;
    }

    /**
     * Normalized key to the target records that hold it, out of source rows. A parent of the
     * target object is itself; an Individual is every record of the target carrying it
     * (contacts by IndividualId, person accounts by PersonIndividualId); anything else is
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
        Map<Id, Set<Id>> holdersByIndividual = new Map<Id, Set<Id>>();
        String individualField = individualFieldOf(target);
        if (individualField != null && !individuals.isEmpty()) {
            for (
                SObject holder : MatchSourceSelector.holdersOfIndividuals(
                    target,
                    individualField,
                    null,
                    individuals
                )
            ) {
                Id individual = (Id) holder.get(individualField);
                if (!holdersByIndividual.containsKey(individual)) {
                    holdersByIndividual.put(individual, new Set<Id>());
                }
                holdersByIndividual.get(individual).add(holder.Id);
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
                : holdersByIndividual.get(parent);
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
     * exists and is text a query can filter on, the parent field is a lookup to a Contact, an
     * Account or an Individual (the only parents a source resolves), and an address source
     * names a postal code field that exists and is filterable text too. The lookups filter on
     * the value and postal fields, so a field a query cannot filter would fail every run.
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
        requireText(
            requireField(fields, (String) values.get('Value_Field__c'), described.getLabel()),
            described.getLabel()
        );
        Schema.SObjectField parent = requireField(
            fields,
            (String) values.get('Parent_Field__c'),
            described.getLabel()
        );
        if (!isPersonOrHouseholdLookup(parent)) {
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
            requireText(requireField(fields, postal, described.getLabel()), described.getLabel());
        }
    }

    /** The parents a source can resolve to a person or a household. */
    private static final Set<String> PARENT_OBJECTS = new Set<String>{
        'Contact',
        'Account',
        'Individual'
    };

    private static Boolean isPersonOrHouseholdLookup(Schema.SObjectField token) {
        Schema.DescribeFieldResult described = token.getDescribe();
        if (described.getType() != Schema.DisplayType.REFERENCE) {
            return false;
        }
        for (Schema.SObjectType referenced : described.getReferenceTo()) {
            if (
                PARENT_OBJECTS.contains(
                    referenced.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                )
            ) {
                return true;
            }
        }
        return false;
    }

    /** Field types holding text a value can be read from and filtered on. */
    private static final Set<Schema.DisplayType> TEXT_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.STRING,
        Schema.DisplayType.EMAIL,
        Schema.DisplayType.PHONE,
        Schema.DisplayType.TEXTAREA,
        Schema.DisplayType.URL
    };

    private static void requireText(Schema.SObjectField token, String objectLabel) {
        Schema.DescribeFieldResult described = token.getDescribe();
        if (!TEXT_TYPES.contains(described.getType()) || !described.isFilterable()) {
            throw new CustomMetadataManagerService.CustomMetadataManagerException(
                String.format(
                    Label.Core_MatchSource_NotFilterableText,
                    new List<Object>{ described.getLabel(), objectLabel }
                )
            );
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
