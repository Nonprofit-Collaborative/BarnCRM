/**
 * The checks on the Data Hygiene tab (C-28, admin guide data-hygiene.md, canonical model R-SQ6,
 * ADR-0079 `0079-data-hygiene-checks-are-find-queries-built-at-request-time.md`).
 *
 * Each check is a Find query document (R-SQ1) built here when it is counted or opened: names
 * come from schema tokens, so a namespace added later is carried, and the household record type
 * is matched by developer name. Nothing is stored in the package, so a check cannot be edited
 * or left stale. The count is SELECT COUNT() over the same document, its filter rendered with
 * every value bound by RollupFilterParser and run in user mode, so the number is what Find
 * lists for the same person (ADR-0047). One check Find cannot express, people with no
 * household in junction mode (a child condition), is counted with HouseholdOrphanSelector, as
 * Health Check counts it (ADR-0048), and has no document.
 *
 * Detection only: nothing here writes.
 */
public with sharing class DataHygieneService {
    /** Counts stop here, the most rows Find shows at once, and say "more than". */
    public static final Integer COUNT_CAP = QueryCompiler.MAX_ROWS;

    public static final String PEOPLE_WITHOUT_HOUSEHOLD = 'people_without_household';
    public static final String HOUSEHOLDS_WITHOUT_MEMBERS = 'households_without_members';
    public static final String MEMBERSHIPS_WITHOUT_PERSON = 'memberships_without_person';
    public static final String ADDRESSES_WITHOUT_OWNER = 'addresses_without_owner';
    public static final String DEFAULT_ADDRESSES_INCOMPLETE = 'default_addresses_incomplete';
    public static final String DEFAULT_ADDRESSES_FAILED = 'default_addresses_failed_verification';

    /** The checks, in the order the page lists them. */
    public static final List<String> CHECK_KEYS = new List<String>{
        PEOPLE_WITHOUT_HOUSEHOLD,
        HOUSEHOLDS_WITHOUT_MEMBERS,
        MEMBERSHIPS_WITHOUT_PERSON,
        ADDRESSES_WITHOUT_OWNER,
        DEFAULT_ADDRESSES_INCOMPLETE,
        DEFAULT_ADDRESSES_FAILED
    };

    private static final Integer ROWS_SHOWN = QueryCompiler.DEFAULT_ROWS;
    private static final String CAP_BIND = 'hygieneCap';

    /** Raised for a check key the page does not know, or a check Find cannot open. */
    public class DataHygieneException extends Exception {
    }

    /** One check as the page shows it. */
    public class CheckResult {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String title;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Integer count;
        @AuraEnabled
        public String countLabel;
        @AuraEnabled
        public Boolean canOpenInFind = false;
        @AuraEnabled
        public String note;
        @AuraEnabled
        public String errorMessage;
    }

    /** Every check, each counted on its own, so one that cannot run never stops the rest. */
    public static List<CheckResult> runAll() {
        List<CheckResult> results = new List<CheckResult>();
        for (String key : CHECK_KEYS) {
            results.add(run(key));
        }
        return results;
    }

    /** One check, counted as the running user. A refusal is shown on the check, not thrown. */
    public static CheckResult run(String key) {
        CheckResult result = new CheckResult();
        result.key = key;
        result.title = title(key);
        result.description = description(key);
        try {
            String document = queryDocument(key);
            if (document == null) {
                result.count = countJunctionPeopleWithoutHousehold();
                result.note = System.Label.Core_DataHygiene_NotInFindYet;
            } else {
                result.count = count(document);
                result.canOpenInFind = true;
            }
            // A household that is also a Nonprofit Cloud household keeps its members there, so
            // it reads as empty here, and deleting it would delete its native group (ADR-0036).
            if (
                key == HOUSEHOLDS_WITHOUT_MEMBERS &&
                OrgShapeDetector.detect().hasNativeHouseholdGroups == true
            ) {
                result.note = System.Label.Core_DataHygiene_NativeHouseholdsListed;
            }
            result.countLabel = countLabel(result.count);
        } catch (QueryCompiler.QueryCompilerException refused) {
            result.errorMessage = refused.getMessage();
        } catch (RollupFilterParser.RollupFilterException refused) {
            result.errorMessage = refused.getMessage();
        } catch (QueryFieldCatalog.QueryFieldCatalogException refused) {
            result.errorMessage = refused.getMessage();
        } catch (System.QueryException noAccess) {
            result.errorMessage = System.Label.Core_DataHygiene_NoAccess;
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, 'Data hygiene check ' + key);
            result.errorMessage = System.Label.Core_DataHygiene_CheckFailed;
        }
        return result;
    }

    /**
     * The check's query document as JSON, built for this org now, or null for the one check
     * Find cannot list (people with no household in junction mode).
     */
    public static String queryDocument(String key) {
        Map<String, Object> document;
        if (key == PEOPLE_WITHOUT_HOUSEHOLD) {
            document = HouseholdService.isJunctionMode() ? null : contactsWithoutAccount();
        } else if (key == HOUSEHOLDS_WITHOUT_MEMBERS) {
            document = householdsWithoutMembers();
        } else if (key == MEMBERSHIPS_WITHOUT_PERSON) {
            document = membershipsWithoutPerson();
        } else if (key == ADDRESSES_WITHOUT_OWNER) {
            document = addressesWithoutOwner();
        } else if (key == DEFAULT_ADDRESSES_INCOMPLETE) {
            document = defaultAddressesIncomplete();
        } else if (key == DEFAULT_ADDRESSES_FAILED) {
            document = defaultAddressesFailed();
        } else {
            throw new DataHygieneException(System.Label.Core_DataHygiene_UnknownCheck);
        }
        return document == null ? null : JSON.serialize(document);
    }

    /** The name "Open in Find" saves the check's query under. */
    public static String savedQueryName(String key) {
        return String.format(
                System.Label.Core_DataHygiene_SavedQueryName,
                new List<Object>{ title(key) }
            )
            .left(80);
    }

    /**
     * Counts a document as the running user, up to COUNT_CAP + 1. The document is compiled the
     * way Find compiles it first, so a column or sort the user cannot see is refused here too.
     */
    public static Integer count(String document) {
        QueryCompiler.Compiled compiled = QueryCompiler.compile(document);
        QueryCompiler.QueryDocument parsed = QueryCompiler.parse(document);
        FilterValueBinder bound = RollupFilterParser.toBoundClause(
            parsed.filter,
            compiled.objectName
        );
        Map<String, Object> binds = new Map<String, Object>(bound.binds);
        binds.put(CAP_BIND, COUNT_CAP + 1);
        String soql =
            'SELECT COUNT() FROM ' +
            compiled.objectName +
            (String.isBlank(bound.clause) ? '' : ' WHERE ' + bound.clause) +
            ' LIMIT :' +
            CAP_BIND;
        return Database.countQueryWithBinds(soql, binds, AccessLevel.USER_MODE);
    }

    /** "1,234", or "More than 2,000" past the cap. */
    public static String countLabel(Integer count) {
        return count > COUNT_CAP
            ? String.format(
                  System.Label.Core_DataHygiene_MoreThan,
                  new List<Object>{ COUNT_CAP.format() }
              )
            : count.format();
    }

    // ------------------------------------------------------------------ the documents

    /** Contact mode: a person with no account is in no household (R-C1). */
    private static Map<String, Object> contactsWithoutAccount() {
        return document(
            Contact.SObjectType,
            new List<String>{ 'Name', name(Contact.CreatedDate) },
            new List<Object>{ condition(1, name(Contact.AccountId), 'is null', null) },
            null
        );
    }

    /** A household whose Member Count is zero or empty (R-H11). */
    private static Map<String, Object> householdsWithoutMembers() {
        String memberCount = name(Account.Member_Count__c);
        return document(
            Account.SObjectType,
            new List<String>{ 'Name', memberCount, name(Account.CreatedDate) },
            new List<Object>{
                condition(
                    1,
                    parent(Account.RecordTypeId, 'DeveloperName'),
                    'equals',
                    HouseholdService.RECORD_TYPE_HOUSEHOLD
                ),
                condition(2, memberCount, 'is null', null),
                condition(3, memberCount, 'equals', 0)
            },
            '1 AND (2 OR 3)'
        );
    }

    /** A membership row naming nobody, left by a deletion with automation off (R-M4). */
    private static Map<String, Object> membershipsWithoutPerson() {
        return document(
            Household_Member__c.SObjectType,
            new List<String>{
                'Name',
                parent(Household_Member__c.Household__c, 'Name'),
                name(Household_Member__c.Start_Date__c),
                name(Household_Member__c.End_Date__c)
            },
            new List<Object>{
                condition(1, name(Household_Member__c.Contact__c), 'is null', null),
                condition(2, name(Household_Member__c.Account__c), 'is null', null)
            },
            null
        );
    }

    /** An address whose owner was deleted (R-AD1). */
    private static Map<String, Object> addressesWithoutOwner() {
        return document(
            Address__c.SObjectType,
            new List<String>{
                'Name',
                name(Address__c.Type__c),
                name(Address__c.Street__c),
                name(Address__c.City__c),
                name(Address__c.Postal_Code__c)
            },
            new List<Object>{
                condition(1, name(Address__c.Account__c), 'is null', null),
                condition(2, name(Address__c.Contact__c), 'is null', null),
                condition(3, name(Address__c.Person_Account__c), 'is null', null)
            },
            null
        );
    }

    /** A default address (R-AD3) with no street, city or postal code. */
    private static Map<String, Object> defaultAddressesIncomplete() {
        return document(
            Address__c.SObjectType,
            addressColumns(),
            new List<Object>{
                condition(1, name(Address__c.Is_Default__c), 'equals', true),
                condition(2, name(Address__c.Street__c), 'is null', null),
                condition(3, name(Address__c.City__c), 'is null', null),
                condition(4, name(Address__c.Postal_Code__c), 'is null', null)
            },
            '1 AND (2 OR 3 OR 4)'
        );
    }

    /** A default address a verification app marked Failed (R-AD6). */
    private static Map<String, Object> defaultAddressesFailed() {
        return document(
            Address__c.SObjectType,
            addressColumns(),
            new List<Object>{
                condition(1, name(Address__c.Is_Default__c), 'equals', true),
                condition(2, name(Address__c.Verification_Status__c), 'equals', 'Failed')
            },
            null
        );
    }

    /** The address and whose it is. */
    private static List<String> addressColumns() {
        return new List<String>{
            'Name',
            parent(Address__c.Account__c, 'Name'),
            parent(Address__c.Contact__c, 'Name'),
            parent(Address__c.Person_Account__c, 'Name'),
            name(Address__c.Street__c),
            name(Address__c.City__c),
            name(Address__c.Postal_Code__c)
        };
    }

    // ------------------------------------------------------------------ helpers

    private static Map<String, Object> document(
        Schema.SObjectType objectType,
        List<String> fields,
        List<Object> conditions,
        String logic
    ) {
        Map<String, Object> filter = new Map<String, Object>{
            'version' => 1,
            'conditions' => conditions
        };
        if (logic != null) {
            filter.put('logic', logic);
        }
        return new Map<String, Object>{
            'version' => 1,
            'object' => objectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
            'fields' => fields,
            'filter' => filter,
            'orderBy' => new List<Object>{
                new Map<String, Object>{ 'field' => 'CreatedDate', 'direction' => 'ASC' }
            },
            'limit' => ROWS_SHOWN
        };
    }

    private static Map<String, Object> condition(
        Integer id,
        String field,
        String operator,
        Object value
    ) {
        Map<String, Object> written = new Map<String, Object>{
            'id' => id,
            'field' => field,
            'operator' => operator
        };
        if (value != null) {
            written.put('value', value);
        }
        return written;
    }

    private static String name(Schema.SObjectField field) {
        return field.getDescribe().getName();
    }

    /** A parent's field through the lookup's relationship name, such as `Household__r.Name`. */
    private static String parent(Schema.SObjectField lookup, String leaf) {
        return lookup.getDescribe().getRelationshipName() + '.' + leaf;
    }

    /**
     * Junction mode: contacts and person accounts with no current membership, as Health Check
     * counts them (ADR-0048), each read capped.
     */
    private static Integer countJunctionPeopleWithoutHousehold() {
        Set<Id> personTypes = personRecordTypeIds();
        Set<Id> excluded = new Set<Id>(personTypes);
        Id householdType = HouseholdService.householdRecordTypeId();
        if (householdType != null) {
            excluded.add(householdType);
        }
        Integer found = HouseholdOrphanSelector.countContactsWithoutMembership(
            excluded,
            COUNT_CAP + 1
        );
        if (!personTypes.isEmpty() && found <= COUNT_CAP) {
            found += HouseholdOrphanSelector.countPersonAccountsWithoutMembership(
                personTypes,
                COUNT_CAP + 1
            );
        }
        return found;
    }

    private static Set<Id> personRecordTypeIds() {
        OrgShapeDetector.OrgShape shape = OrgShapeDetector.detect();
        return shape == null ||
            shape.personAccountRecordTypeIds == null
            ? new Set<Id>()
            : shape.personAccountRecordTypeIds;
    }

    private static String title(String key) {
        Map<String, String> titles = new Map<String, String>{
            PEOPLE_WITHOUT_HOUSEHOLD => System.Label.Core_DataHygiene_PeopleTitle,
            HOUSEHOLDS_WITHOUT_MEMBERS => System.Label.Core_DataHygiene_HouseholdsTitle,
            MEMBERSHIPS_WITHOUT_PERSON => System.Label.Core_DataHygiene_MembershipsTitle,
            ADDRESSES_WITHOUT_OWNER => System.Label.Core_DataHygiene_OwnerlessTitle,
            DEFAULT_ADDRESSES_INCOMPLETE => System.Label.Core_DataHygiene_IncompleteTitle,
            DEFAULT_ADDRESSES_FAILED => System.Label.Core_DataHygiene_FailedTitle
        };
        if (!titles.containsKey(key)) {
            throw new DataHygieneException(System.Label.Core_DataHygiene_UnknownCheck);
        }
        return titles.get(key);
    }

    private static String description(String key) {
        if (key == PEOPLE_WITHOUT_HOUSEHOLD) {
            return HouseholdService.isJunctionMode()
                ? System.Label.Core_DataHygiene_PeopleJunctionDetail
                : System.Label.Core_DataHygiene_PeopleContactDetail;
        }
        return new Map<String, String>{
                HOUSEHOLDS_WITHOUT_MEMBERS => System.Label.Core_DataHygiene_HouseholdsDetail,
                MEMBERSHIPS_WITHOUT_PERSON => System.Label.Core_DataHygiene_MembershipsDetail,
                ADDRESSES_WITHOUT_OWNER => System.Label.Core_DataHygiene_OwnerlessDetail,
                DEFAULT_ADDRESSES_INCOMPLETE => System.Label.Core_DataHygiene_IncompleteDetail,
                DEFAULT_ADDRESSES_FAILED => System.Label.Core_DataHygiene_FailedDetail
            }
            .get(key);
    }
}
