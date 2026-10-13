/**
 * Reads people that the org stores as account records rather than as contacts.
 *
 * Those name fields exist on the account object only in orgs shaped that way, so this
 * class never names them at compile time: the query is built as text and the values are
 * read with SObject.get. It is the only class in Core that does this, and it runs only
 * when HouseholdService.isPersonAccountOrg() is true.
 *
 * How a person is told apart from an organization, and what that costs: the sound test is
 * the platform's own person flag, which the CI check on standard object references
 * forbids Core to name at all, with no exemption. So this class infers it: an account
 * holds a person when the surname field both exists on the object and carries a value on
 * the record. That is right for every ordinary case, because an organization never
 * carries a surname. It is wrong in two ways worth knowing: a record read with a query
 * that did not select the surname reads as an organization, and an org that puts a value
 * in that field on a business account would be misread. Both are visible only inside this
 * class. If the check ever grows an exemption for a describe-only read of the person flag,
 * that is the one line to change.
 *
 * There are two kinds of read here, and they are not interchangeable, exactly as in
 * HouseholdSelector. The upkeep read (getPersons) feeds the member count, the household
 * name and the two greetings and runs in system mode under ADR-0021. The display read
 * (getPersonsForDisplay) is what a screen shows: object access is checked and every field
 * the running user cannot read is stripped before a person is built.
 */
public with sharing class PersonRecordSelector {
    // detection-only: these field names exist on the account object only where the org
    // stores people as accounts, so they are held as text and never referenced statically.
    private static final List<String> NAME_FIELDS = new List<String>{
        'FirstName',
        'LastName',
        'Salutation'
    };
    // The person attributes Core adds, present on both the contact and the account object
    // so that a person carries them whichever object holds them.
    private static final List<String> PERSON_FIELDS = new List<String>{
        'Preferred_Name__c',
        'Deceased__c',
        'Household_Role__c',
        'Exclude_From_Household_Name__c',
        'Exclude_From_Greetings__c'
    };

    // detection-only: an account holds a person rather than an organization when this
    // field both exists on the object and carries a value on the record.
    private static final String PERSON_MARKER_FIELD = 'LastName';

    // detection-only: the contact the platform keeps behind an account that holds a person
    // exists as a field only where the org stores people as accounts.
    private static final String PERSON_CONTACT_FIELD = 'PersonContactId';

    /**
     * Set only by tests, keyed by account id. It supplies the person contact that an org
     * without person accounts cannot hold, so the mirror to a household's Primary Contact can
     * be exercised on any org shape. Production code never sets it.
     */
    @TestVisible
    private static Map<Id, Id> personContactIdOverride;

    /**
     * Set only by tests. When it is true every account record is treated as a person, so
     * that the person account paths can be exercised on an org shape that has no person
     * accounts. Production code never sets it.
     */
    @TestVisible
    private static Boolean personRecordOverride;

    /**
     * Set only by tests, keyed by the account's name. It supplies the person details that
     * an org without the person name fields cannot hold, so that a test can assert the
     * household name those details produce. Production code never sets it.
     */
    @TestVisible
    private static Map<String, HouseholdService.Person> personOverridesByName;

    /**
     * True when this account record holds a person. Nothing that exists only in some orgs
     * is named at compile time: the field is looked up by name and read from the values
     * the record actually carries.
     */
    public static Boolean isPersonRecord(SObject record) {
        if (record == null) {
            return false;
        }
        if (personRecordOverride != null) {
            return personRecordOverride;
        }
        if (!Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_MARKER_FIELD)) {
            return false;
        }
        Object value = record.getPopulatedFieldsAsMap().get(PERSON_MARKER_FIELD);
        return value != null && String.isNotBlank(String.valueOf(value));
    }

    /**
     * True when the difference between these two versions of a person record is one the
     * household name or the two greetings are computed from.
     *
     * The list is exactly the one `ContactTriggerHandler.namingChanged` watches, held here
     * as text and compared off the values the records actually carry, so that a field which
     * exists only where the org stores people as accounts is never named at compile time
     * (ADR-0009). A field this org does not have is absent on both sides and so reads as
     * unchanged, which is the right answer: it cannot have changed.
     */
    public static Boolean namingChanged(SObject record, SObject previous) {
        if (record == null || previous == null) {
            return false;
        }
        Map<String, Object> current = record.getPopulatedFieldsAsMap();
        Map<String, Object> before = previous.getPopulatedFieldsAsMap();
        for (String fieldName : namingFields()) {
            if (valueChanged(current.get(fieldName), before.get(fieldName))) {
                return true;
            }
        }
        return false;
    }

    /**
     * Text is compared case-sensitively, so that correcting "Mcdonald" to "McDonald"
     * counts as a change: Apex `==` and `!=` ignore case for Strings.
     */
    private static Boolean valueChanged(Object now, Object before) {
        if (now instanceof String && before instanceof String) {
            return !((String) now).equals((String) before);
        }
        return now != before;
    }

    /**
     * Every field a household name or greeting is computed from, name fields first.
     */
    private static List<String> namingFields() {
        List<String> result = new List<String>(NAME_FIELDS);
        result.addAll(PERSON_FIELDS);
        return result;
    }

    public static List<SObject> filterPeople(List<SObject> records) {
        List<SObject> result = new List<SObject>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            if (isPersonRecord(record)) {
                result.add(record);
            }
        }
        return result;
    }

    /**
     * The people these account records hold, for household upkeep.
     *
     * An upkeep read (ADR-0021): the answer never reaches a screen. It feeds the member
     * count, the household name and the two greetings, which HouseholdWriter then saves,
     * and a household must be counted and named correctly for a user who holds no packaged
     * permission set at all. The contact half of the same upkeep reads the same way, in
     * HouseholdSelector.
     *
     * The four ADR-0021 conditions hold. The platform has already authorized the record
     * write that started the upkeep, or an administrator has asked for the recompute. The
     * only inputs are ids the package itself gathered and field names held as constants in
     * this class, so no user typed text reaches the query. Only fields the package owns are
     * read, plus the name fields a household name is built from. Everything a screen shows
     * goes through getPersonsForDisplay instead, which stays in user mode.
     *
     * The class is `with sharing`, so which records are visible is not changed by any of
     * this: only field level access on the fields the package owns is bypassed.
     */
    public static List<HouseholdService.Person> getPersons(Set<Id> personRecordIds) {
        return toPersons(queryPersonRecords(personRecordIds));
    }

    /**
     * The same people as a screen may see them: nothing at all where the running user
     * cannot read the object, and otherwise every field they cannot read stripped from the
     * records before a person is built from them (ADR-0021). Stripping rather than a user
     * mode query, so that a field this user cannot read leaves a value empty instead of
     * throwing, which is what HouseholdSelector.readableRecords does on the contact side.
     */
    public static List<HouseholdService.Person> getPersonsForDisplay(Set<Id> personRecordIds) {
        List<SObject> records = queryPersonRecords(personRecordIds);
        if (records.isEmpty() || !Schema.SObjectType.Account.isAccessible()) {
            return new List<HouseholdService.Person>();
        }
        return toPersons(Security.stripInaccessible(AccessType.READABLE, records).getRecords());
    }

    /**
     * The account records themselves. System mode, for the reason the two callers above
     * set out: the display caller strips what the running user may not read, the upkeep
     * caller needs the whole record.
     */
    private static List<SObject> queryPersonRecords(Set<Id> personRecordIds) {
        List<SObject> result = new List<SObject>();
        if (
            personRecordIds == null ||
            personRecordIds.isEmpty() ||
            !HouseholdService.isPersonAccountOrg()
        ) {
            return result;
        }
        List<String> selected = new List<String>{ 'Id', 'Name', 'CreatedDate' };
        selected.addAll(availableFields());
        String query =
            'SELECT ' +
            String.join(selected, ', ') +
            ' FROM Account WHERE Id IN :personRecordIds LIMIT 10000';
        Map<String, Object> binds = new Map<String, Object>{ 'personRecordIds' => personRecordIds };
        return Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE);
    }

    /**
     * The contact the platform keeps behind each of these person accounts, by account id. It
     * is what a household's Primary Contact names when its primary member is stored as an
     * account (R-M3), because that field is a lookup to Contact and accepts it.
     *
     * An upkeep read under ADR-0021, on the same four conditions getPersons gives: its only
     * caller is household upkeep, its only input is ids upkeep gathered, it reads one field,
     * and the answer is saved by HouseholdWriter, never shown. An account that holds no
     * person, and every account in an org that does not store people as accounts, is absent
     * from the answer rather than mapped to null.
     */
    public static Map<Id, Id> getPersonContactIds(Set<Id> personRecordIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        if (personRecordIds == null || personRecordIds.isEmpty()) {
            return result;
        }
        if (personContactIdOverride != null) {
            for (Id personId : personRecordIds) {
                if (personContactIdOverride.containsKey(personId)) {
                    result.put(personId, personContactIdOverride.get(personId));
                }
            }
            return result;
        }
        if (
            !HouseholdService.isPersonAccountOrg() ||
            !Schema.SObjectType.Account.fields.getMap().containsKey(PERSON_CONTACT_FIELD)
        ) {
            return result;
        }
        String query =
            'SELECT Id, ' +
            PERSON_CONTACT_FIELD +
            ' FROM Account WHERE Id IN :personRecordIds LIMIT 10000';
        Map<String, Object> binds = new Map<String, Object>{ 'personRecordIds' => personRecordIds };
        for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.SYSTEM_MODE)) {
            Object value = record.get(PERSON_CONTACT_FIELD);
            if (value instanceof Id) {
                result.put(record.Id, (Id) value);
            }
        }
        return result;
    }

    public static List<HouseholdService.Person> toPersons(List<SObject> records) {
        List<HouseholdService.Person> result = new List<HouseholdService.Person>();
        if (records == null) {
            return result;
        }
        for (SObject record : records) {
            result.add(toPerson(record));
        }
        return result;
    }

    public static HouseholdService.Person toPerson(SObject record) {
        HouseholdService.Person person = declared(record);
        if (person != null) {
            return person;
        }
        person = new HouseholdService.Person();
        person.id = record.Id;
        person.sourceObject = HouseholdService.SOURCE_ACCOUNT;
        // Only the values actually on the record are read, so a field this org does not
        // have, or did not select, reads as empty instead of failing.
        Map<String, Object> values = record.getPopulatedFieldsAsMap();
        person.firstName = text(values, 'FirstName');
        person.lastName = text(values, 'LastName');
        person.salutation = text(values, 'Salutation');
        person.preferredName = text(values, 'Preferred_Name__c');
        person.role = text(values, 'Household_Role__c');
        person.isDeceased = flag(values, 'Deceased__c');
        person.excludeFromName = flag(values, 'Exclude_From_Household_Name__c');
        person.excludeFromGreetings = flag(values, 'Exclude_From_Greetings__c');
        person.createdDate = values.get('CreatedDate') instanceof Datetime
            ? (Datetime) values.get('CreatedDate')
            : null;
        return person;
    }

    /**
     * The person details a test declared for this record, if any.
     */
    private static HouseholdService.Person declared(SObject record) {
        if (personOverridesByName == null || record == null) {
            return null;
        }
        Object name = record.getPopulatedFieldsAsMap().get('Name');
        if (name == null || !personOverridesByName.containsKey(String.valueOf(name))) {
            return null;
        }
        HouseholdService.Person person = personOverridesByName.get(String.valueOf(name)).copy();
        person.id = record.Id;
        person.sourceObject = HouseholdService.SOURCE_ACCOUNT;
        return person;
    }

    private static List<String> availableFields() {
        List<String> result = new List<String>();
        Map<String, Schema.SObjectField> describe = Schema.SObjectType.Account.fields.getMap();
        for (String fieldName : NAME_FIELDS) {
            if (describe.containsKey(fieldName)) {
                result.add(fieldName);
            }
        }
        for (String fieldName : PERSON_FIELDS) {
            if (describe.containsKey(fieldName)) {
                result.add(fieldName);
            }
        }
        return result;
    }

    private static String text(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value == null ? null : String.valueOf(value);
    }

    private static Boolean flag(Map<String, Object> values, String fieldName) {
        Object value = values.get(fieldName);
        return value instanceof Boolean ? (Boolean) value : false;
    }
}
