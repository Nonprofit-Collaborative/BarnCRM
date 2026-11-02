/**
 * Reads the Nonprofit Success Pack's household Accounts, by describe only (X-05, canonical model
 * R-HA1, ADR-NEXT `NEXT-npsp-household-adoption-in-core.md`).
 *
 * Core never depends on NPSP: every NPSP name is built here at run time, so none appears in
 * source (scripts/ci/check-namespace.sh), a field the describe does not find is read as blank,
 * and in an org without NPSP `available()` is false and nothing is queried. Fields are read
 * only when the running user may read them, so the user mode queries never fail on access.
 *
 * This is the seam the tests replace (`instance`): no test org has NPSP, so the tests subclass
 * it to name ordinary Accounts as NPSP households and to hand back NPSP values.
 */
public with sharing virtual class NpspHouseholdSource {
    private static final String SEPARATOR = '__';
    private static final String CONTACTS_AND_ORGS = 'npe01';
    private static final String HOUSEHOLDS = 'npo02';

    /** NPSP's "this account is a household" marker and its value (R-HA1). */
    @TestVisible
    private static final String ACCOUNT_TYPE_FIELD = npspField(
        CONTACTS_AND_ORGS,
        'SYSTEM_AccountType'
    );
    @TestVisible
    private static final String HOUSEHOLD_ACCOUNT_TYPE = 'Household Account';
    /** NPSP's household record type. */
    @TestVisible
    private static final String HOUSEHOLD_RECORD_TYPE = 'HH_Account';

    @TestVisible
    private static final String FORMAL_GREETING_FIELD = npspField(HOUSEHOLDS, 'Formal_Greeting');
    @TestVisible
    private static final String INFORMAL_GREETING_FIELD = npspField(
        HOUSEHOLDS,
        'Informal_Greeting'
    );
    @TestVisible
    private static final String PRIMARY_CONTACT_FIELD = npspField(
        CONTACTS_AND_ORGS,
        'One2OneContact'
    );
    @TestVisible
    private static final String CUSTOM_NAMING_FIELD = npspField(HOUSEHOLDS, 'SYSTEM_CUSTOM_NAMING');

    /** Test seam: the source in use. */
    @TestVisible
    private static NpspHouseholdSource instance;

    public static NpspHouseholdSource get() {
        if (instance == null) {
            instance = new NpspHouseholdSource();
        }
        return instance;
    }

    /** One NPSP household as adoption needs it. Values NPSP does not have are null. */
    public class Household {
        public Id accountId;
        public String name;
        public Id recordTypeId;
        public String formalGreeting;
        public String informalGreeting;
        public Id primaryContactId;
        /** True when NPSP recorded that staff typed the name or a greeting by hand. */
        public Boolean customNaming = false;
    }

    /** True when the org has either NPSP household marker, so there can be something to adopt. */
    public virtual Boolean available() {
        return accountField(ACCOUNT_TYPE_FIELD) != null || npspRecordTypeId() != null;
    }

    /**
     * The WHERE clause that selects NPSP households not yet BarnCRM households, with its binds
     * in `binds()`. Blank when `available()` is false.
     */
    public virtual String condition() {
        List<String> markers = new List<String>();
        if (accountField(ACCOUNT_TYPE_FIELD) != null) {
            markers.add(ACCOUNT_TYPE_FIELD + ' = :npspAccountType');
        }
        if (npspRecordTypeId() != null) {
            markers.add('RecordTypeId = :npspRecordType');
        }
        if (markers.isEmpty()) {
            return '';
        }
        return '(' + String.join(markers, ' OR ') + ') AND RecordTypeId != :barnHousehold';
    }

    /** The binds `condition()` names, and no others. */
    public virtual Map<String, Object> binds() {
        Map<String, Object> result = new Map<String, Object>{
            'barnHousehold' => HouseholdService.householdRecordTypeId()
        };
        if (accountField(ACCOUNT_TYPE_FIELD) != null) {
            result.put('npspAccountType', HOUSEHOLD_ACCOUNT_TYPE);
        }
        if (npspRecordTypeId() != null) {
            result.put('npspRecordType', npspRecordTypeId());
        }
        return result;
    }

    /** The NPSP values of these Accounts, read as the running user. */
    public virtual List<Household> read(Set<Id> accountIds) {
        List<Household> result = new List<Household>();
        if (accountIds == null || accountIds.isEmpty()) {
            return result;
        }
        List<String> fields = new List<String>{ 'Id', 'Name', 'RecordTypeId' };
        for (
            String name : new List<String>{
                FORMAL_GREETING_FIELD,
                INFORMAL_GREETING_FIELD,
                PRIMARY_CONTACT_FIELD,
                CUSTOM_NAMING_FIELD
            }
        ) {
            if (accountField(name) != null) {
                fields.add(name);
            }
        }
        String query =
            'SELECT ' +
            String.join(fields, ', ') +
            ' FROM Account WHERE Id IN :accountIds ORDER BY Id';
        for (
            SObject row : Database.queryWithBinds(
                query,
                new Map<String, Object>{ 'accountIds' => accountIds },
                AccessLevel.USER_MODE
            )
        ) {
            Household household = new Household();
            household.accountId = row.Id;
            household.name = (String) row.get('Name');
            household.recordTypeId = (Id) row.get('RecordTypeId');
            household.formalGreeting = text(row, FORMAL_GREETING_FIELD);
            household.informalGreeting = text(row, INFORMAL_GREETING_FIELD);
            String primary = text(row, PRIMARY_CONTACT_FIELD);
            household.primaryContactId = String.isBlank(primary) ? null : Id.valueOf(primary);
            household.customNaming = String.isNotBlank(text(row, CUSTOM_NAMING_FIELD));
            result.add(household);
        }
        return result;
    }

    private static String text(SObject row, String field) {
        if (!row.getPopulatedFieldsAsMap().containsKey(field)) {
            return null;
        }
        Object value = row.get(field);
        return value == null ? null : String.valueOf(value);
    }

    /** NPSP's household record type, when the org has it. */
    private static Id npspRecordTypeId() {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(HOUSEHOLD_RECORD_TYPE);
        return info == null ? null : info.getRecordTypeId();
    }

    /** The Account field of that name when it exists and the running user may read it. */
    private static Schema.SObjectField accountField(String name) {
        Schema.SObjectField field = Schema.SObjectType.Account.fields.getMap().get(name);
        if (field == null || !field.getDescribe().isAccessible()) {
            return null;
        }
        return field;
    }

    private static String npspField(String prefix, String name) {
        return prefix + SEPARATOR + name + SEPARATOR + 'c';
    }
}
