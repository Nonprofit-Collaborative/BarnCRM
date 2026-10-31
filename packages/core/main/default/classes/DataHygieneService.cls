/**
 * The checks in the Data Quality section of Org Optimizer (C-28, admin guide data-hygiene.md, canonical model R-SQ6,
 * ADR-0079 `0079-data-hygiene-checks-are-find-queries-built-at-request-time.md`).
 *
 * Each check is a Find query document (R-SQ1) built here when it is counted or opened: names
 * come from schema tokens, so a namespace added later is carried, and the household record type
 * is matched by developer name. Nothing is stored in the package, so a check cannot be edited
 * or left stale. The count is SELECT COUNT() over the same document, its filter rendered with
 * every value bound by RollupFilterParser and run in user mode, so the number is what Find
 * lists for the same person (ADR-0047). One check is counted another way: people with no
 * household in junction mode are counted with HouseholdOrphanSelector, as Health Check counts
 * them (ADR-0048), people kept as person accounts included. Its document, which Find opens,
 * lists the contacts only, using Find's "has no related records" condition (C-36).
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
    public static final String DEFAULT_ADDRESSES_UNDELIVERABLE = 'default_addresses_undeliverable';
    public static final String PEOPLE_UNREACHABLE = 'people_unreachable';
    public static final String DECEASED_STILL_EMAILED = 'deceased_still_emailed';
    public static final String PEOPLE_NOT_UPDATED = 'people_not_updated';

    /** Years without a change before a person counts as not updated, when nothing is set. */
    public static final Integer DEFAULT_STALE_YEARS = 5;
    public static final Integer MIN_STALE_YEARS = 1;
    public static final Integer MAX_STALE_YEARS = 20;

    /** The checks, in the order the page lists them. */
    public static final List<String> CHECK_KEYS = new List<String>{
        PEOPLE_WITHOUT_HOUSEHOLD,
        HOUSEHOLDS_WITHOUT_MEMBERS,
        MEMBERSHIPS_WITHOUT_PERSON,
        ADDRESSES_WITHOUT_OWNER,
        DEFAULT_ADDRESSES_INCOMPLETE,
        DEFAULT_ADDRESSES_FAILED,
        DEFAULT_ADDRESSES_UNDELIVERABLE,
        PEOPLE_UNREACHABLE,
        DECEASED_STILL_EMAILED,
        PEOPLE_NOT_UPDATED
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
            if (key == PEOPLE_WITHOUT_HOUSEHOLD && HouseholdService.isJunctionMode()) {
                result.count = countJunctionPeopleWithoutHousehold();
                result.note = System.Label.Core_DataHygiene_PeopleAccountsNotListed;
            } else {
                result.count = count(document);
            }
            result.canOpenInFind = true;
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
            // Usually the user-mode refusal of a field or object, but a timeout on a large
            // count reads the same way, so it is logged for whoever looks into it.
            ErrorLogger.log(noAccess, 'Data Quality check ' + key);
            result.errorMessage = System.Label.Core_DataHygiene_NoAccess;
        } catch (Exception unexpected) {
            ErrorLogger.log(unexpected, 'Data Quality check ' + key);
            result.errorMessage = System.Label.Core_DataHygiene_CheckFailed;
        }
        return result;
    }

    /**
     * The check's query document as JSON, built for this org now.
     */
    public static String queryDocument(String key) {
        Map<String, Object> document;
        if (key == PEOPLE_WITHOUT_HOUSEHOLD) {
            document = HouseholdService.isJunctionMode()
                ? contactsWithoutMembership()
                : contactsWithoutAccount();
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
        } else if (key == DEFAULT_ADDRESSES_UNDELIVERABLE) {
            document = defaultAddressesUndeliverable();
        } else if (key == PEOPLE_UNREACHABLE) {
            document = peopleUnreachable();
        } else if (key == DECEASED_STILL_EMAILED) {
            document = deceasedStillEmailed();
        } else if (key == PEOPLE_NOT_UPDATED) {
            document = peopleNotUpdated();
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

    /** The name prefix "Open in Find" used before the tool was named Data Quality (D-140). */
    @TestVisible
    private static final String LEGACY_QUERY_PREFIX = 'Data hygiene: ';

    /**
     * Renames each saved query "Data hygiene: <check>" to "Data Quality: <check>", so "Open in
     * Find" keeps updating it after the rename (D-140). Run by CorePostInstall on every install,
     * upgrade and source deploy; running it again finds nothing to rename. When the owner already
     * has a "Data Quality: <check>" query, that newer one is kept and the old one is left as it is.
     * Names compare without case, as SOQL does. Returns how many were renamed.
     */
    public static Integer renameLegacySavedQueries() {
        String prefix = System.Label.Core_DataHygiene_SavedQueryName.substringBefore('{0}');
        String pattern = LEGACY_QUERY_PREFIX + '%';
        List<Saved_Query__c> legacy = [
            SELECT Id, Name, OwnerId
            FROM Saved_Query__c
            WHERE Name LIKE :pattern
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
            LIMIT 10000
        ];
        if (legacy.isEmpty()) {
            return 0;
        }
        Set<String> targets = new Set<String>();
        Set<Id> owners = new Set<Id>();
        for (Saved_Query__c query : legacy) {
            targets.add(prefix + query.Name.substring(LEGACY_QUERY_PREFIX.length()));
            owners.add(query.OwnerId);
        }
        Set<String> taken = new Set<String>();
        for (Saved_Query__c existing : [
            SELECT Name, OwnerId
            FROM Saved_Query__c
            WHERE Name IN :targets AND OwnerId IN :owners
            WITH SYSTEM_MODE
        ]) {
            taken.add(existing.OwnerId + '|' + existing.Name.toLowerCase());
        }
        List<Saved_Query__c> renamed = new List<Saved_Query__c>();
        for (Saved_Query__c query : legacy) {
            String name = prefix + query.Name.substring(LEGACY_QUERY_PREFIX.length());
            // add() is false when the owner already has that name, or an earlier old query
            // of theirs just took it.
            if (taken.add(query.OwnerId + '|' + name.toLowerCase())) {
                renamed.add(new Saved_Query__c(Id = query.Id, Name = name));
            }
        }
        Database.update(renamed, AccessLevel.SYSTEM_MODE);
        return renamed.size();
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

    /**
     * Junction mode: a contact with no current membership row (no end date, or one still to
     * come), leaving out one whose account is a household or a person account, as
     * HouseholdOrphanSelector counts them. Today's date is written into the document.
     */
    private static Map<String, Object> contactsWithoutMembership() {
        String accountType = parent(Contact.AccountId, 'RecordTypeId');
        List<Object> conditions = new List<Object>{
            condition(1, name(Contact.AccountId), 'is null', null)
        };
        List<String> notExcluded = new List<String>();
        Set<Id> excluded = new Set<Id>(OrgShapeDetector.personRecordTypeIds());
        Id householdType = HouseholdService.householdRecordTypeId();
        if (householdType != null) {
            excluded.add(householdType);
        }
        for (Id recordType : excluded) {
            conditions.add(condition(conditions.size() + 1, accountType, 'not equals', recordType));
            notExcluded.add(String.valueOf(conditions.size()));
        }
        Map<String, Object> result = document(
            Contact.SObjectType,
            new List<String>{ 'Name', name(Contact.CreatedDate) },
            conditions,
            notExcluded.isEmpty() ? null : '1 OR (' + String.join(notExcluded, ' AND ') + ')'
        );
        Map<String, Object> current = new Map<String, Object>{
            'version' => 1,
            'conditions' => new List<Object>{
                condition(1, name(Household_Member__c.End_Date__c), 'is null', null),
                condition(
                    2,
                    name(Household_Member__c.End_Date__c),
                    'greater than',
                    String.valueOf(Date.today())
                )
            },
            'logic' => '1 OR 2'
        };
        result.put(
            'related',
            new List<Object>{
                new Map<String, Object>{
                    'object' => Household_Member__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .getName(),
                    'field' => name(Household_Member__c.Contact__c),
                    'has' => false,
                    'filter' => current
                }
            }
        );
        return result;
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

    /**
     * A primary address a person marked Undeliverable (R-AD10): a household, organization or
     * person whose mail is coming back.
     */
    private static Map<String, Object> defaultAddressesUndeliverable() {
        return document(
            Address__c.SObjectType,
            addressColumns(),
            new List<Object>{
                condition(1, name(Address__c.Is_Default__c), 'equals', true),
                condition(
                    2,
                    name(Address__c.Status__c),
                    'equals',
                    AddressService.STATUS_UNDELIVERABLE
                )
            },
            null
        );
    }

    /**
     * A living person with no email, no phone and no mailing city or postal code: nobody can
     * reach them. The mailing fields are where the default address is written (R-AD3).
     */
    private static Map<String, Object> peopleUnreachable() {
        return document(
            Contact.SObjectType,
            new List<String>{ 'Name', name(Contact.CreatedDate) },
            new List<Object>{
                condition(1, name(Contact.Deceased__c), 'equals', false),
                condition(2, name(Contact.Email), 'is null', null),
                condition(3, name(Contact.Phone), 'is null', null),
                condition(4, name(Contact.MobilePhone), 'is null', null),
                condition(5, name(Contact.MailingCity), 'is null', null),
                condition(6, name(Contact.MailingPostalCode), 'is null', null)
            },
            null
        );
    }

    /** A person marked deceased who has an email and has not been opted out of email. */
    private static Map<String, Object> deceasedStillEmailed() {
        return document(
            Contact.SObjectType,
            new List<String>{ 'Name', name(Contact.Email), name(Contact.CreatedDate) },
            new List<Object>{
                condition(1, name(Contact.Deceased__c), 'equals', true),
                condition(2, name(Contact.Email), 'is not null', null),
                condition(3, name(Contact.HasOptedOutOfEmail), 'equals', false)
            },
            null
        );
    }

    /**
     * A person nobody has changed for the years set in BarnCRM Settings: a candidate for
     * review or archiving. The cut-off is written into the document when it is built.
     */
    private static Map<String, Object> peopleNotUpdated() {
        Datetime cutoff = Datetime.now().addYears(-staleYears());
        return document(
            Contact.SObjectType,
            new List<String>{ 'Name', name(Contact.LastModifiedDate), name(Contact.CreatedDate) },
            new List<Object>{
                condition(
                    1,
                    name(Contact.LastModifiedDate),
                    'less than',
                    cutoff.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
                )
            },
            null
        );
    }

    /**
     * Years without a change before a person counts as not updated, from BarnCRM Settings.
     * Empty reads as the default; a value out of range reads as the nearest end (D-40).
     */
    public static Integer staleYears() {
        Object configured = SettingsService.hasKey('Stale_Record_Years__c')
            ? SettingsService.getValue('Stale_Record_Years__c')
            : null;
        if (configured == null) {
            return DEFAULT_STALE_YEARS;
        }
        try {
            Integer years = Decimal.valueOf(String.valueOf(configured)).intValue();
            return Math.max(MIN_STALE_YEARS, Math.min(years, MAX_STALE_YEARS));
        } catch (Exception ignored) {
            return DEFAULT_STALE_YEARS;
        }
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
        return HouseholdOrphanSelector.countPeopleWithoutMembership(
            HouseholdService.householdRecordTypeId(),
            COUNT_CAP + 1
        );
    }

    private static String title(String key) {
        Map<String, String> titles = new Map<String, String>{
            PEOPLE_WITHOUT_HOUSEHOLD => System.Label.Core_DataHygiene_PeopleTitle,
            HOUSEHOLDS_WITHOUT_MEMBERS => System.Label.Core_DataHygiene_HouseholdsTitle,
            MEMBERSHIPS_WITHOUT_PERSON => System.Label.Core_DataHygiene_MembershipsTitle,
            ADDRESSES_WITHOUT_OWNER => System.Label.Core_DataHygiene_OwnerlessTitle,
            DEFAULT_ADDRESSES_INCOMPLETE => System.Label.Core_DataHygiene_IncompleteTitle,
            DEFAULT_ADDRESSES_FAILED => System.Label.Core_DataHygiene_FailedTitle,
            DEFAULT_ADDRESSES_UNDELIVERABLE => System.Label.Core_DataHygiene_UndeliverableTitle,
            PEOPLE_UNREACHABLE => System.Label.Core_DataHygiene_UnreachableTitle,
            DECEASED_STILL_EMAILED => System.Label.Core_DataHygiene_DeceasedTitle,
            PEOPLE_NOT_UPDATED => String.format(
                System.Label.Core_DataHygiene_NotUpdatedTitle,
                new List<Object>{ staleYears() }
            )
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
                DEFAULT_ADDRESSES_FAILED => System.Label.Core_DataHygiene_FailedDetail,
                DEFAULT_ADDRESSES_UNDELIVERABLE => System.Label.Core_DataHygiene_UndeliverableDetail,
                PEOPLE_UNREACHABLE => System.Label.Core_DataHygiene_UnreachableDetail,
                DECEASED_STILL_EMAILED => System.Label.Core_DataHygiene_DeceasedDetail,
                PEOPLE_NOT_UPDATED => System.Label.Core_DataHygiene_NotUpdatedDetail
            }
            .get(key);
    }
}
