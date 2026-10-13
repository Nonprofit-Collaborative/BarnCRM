/**
 * The server side of two small household screens: the Household panel on a person's record,
 * and the Make primary and Add member actions on the household's members panel.
 *
 * Everything here is something a person asked for by clicking, so every read and every
 * write runs with that person's own access (ADR-0021). A household this user cannot see is
 * not shown, a primary contact this user cannot set is refused with a message they can read
 * rather than a raw platform error, and a person this user cannot create or join stays that
 * way for the same reason.
 */
public with sharing class HouseholdOfPersonController {
    private static final String CONTACT_SEARCH_WITHOUT_PERSON_ACCOUNTS = 'SELECT Id, Name FROM Contact WHERE Name LIKE :likeTerm AND IsPersonAccount = false ORDER BY Name LIMIT 10'; // detection-only: used only after isPersonAccountOrg found person accounts, so each such person is offered once, as the account

    /**
     * One household as the panel on a person's record shows it.
     */
    public class HouseholdView {
        @AuraEnabled
        public Id householdId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Integer memberCount;
        @AuraEnabled
        public String formalGreeting;
    }

    /**
     * One person the Add existing person search offers, in the flexible way of belonging.
     */
    public class PersonResult {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
    }

    /**
     * The households this person currently belongs to, in the order they would be listed.
     * Empty when they are in none, which the panel says in plain words.
     *
     * In the simple way of belonging it is the account the contact points at, when that
     * account is a household. In the flexible way it is every household with a current
     * membership record naming the person, which can be more than one.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdView> getHouseholdsForPerson(Id personId) {
        try {
            if (personId == null) {
                return new List<HouseholdView>();
            }
            Set<Id> householdIds = HouseholdService.isJunctionMode()
                ? HouseholdService.householdIdsForPeople(new Set<Id>{ personId })
                : householdIdFromContact(personId);
            return toViews(householdsAsUser(householdIds));
        } catch (Exception e) {
            throw asUserError(Label.Core_HouseholdPanel_OfPersonLoadFailed);
        }
    }

    /**
     * Makes this person the household's primary contact in the flexible way of belonging:
     * their membership record is marked primary and every other current membership of the
     * household is unmarked. The simple way needs no Apex at all, because the screen writes
     * the household's own primary contact field through the platform.
     */
    @AuraEnabled
    public static void makePrimary(Id householdId, Id personId) {
        try {
            if (householdId == null || personId == null) {
                throw new HouseholdException(Label.Core_HouseholdPanel_NotAMember);
            }
            List<Household_Member__c> changed = new List<Household_Member__c>();
            Boolean found = false;
            for (Household_Member__c membership : currentMembershipsAsUser(householdId)) {
                Boolean isPerson =
                    membership.Contact__c == personId ||
                    membership.Account__c == personId;
                found = found || isPerson;
                if (membership.Is_Primary__c != isPerson) {
                    changed.add(
                        new Household_Member__c(Id = membership.Id, Is_Primary__c = isPerson)
                    );
                }
            }
            if (!found) {
                throw new HouseholdException(Label.Core_HouseholdPanel_NotAMember);
            }
            if (!changed.isEmpty()) {
                Database.update(changed, AccessLevel.USER_MODE);
            }
        } catch (HouseholdException e) {
            throw asUserError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership, householdId);
            throw asUserError(Label.Core_HouseholdPanel_MakePrimaryFailed);
        }
    }

    /**
     * People the Add member search on the members panel offers, in the flexible way of
     * belonging: contacts, and where the org stores some people as accounts, those too. Read
     * in user mode, so a person this user cannot see is never offered.
     *
     * Two or more characters are asked for before a query runs, the same floor
     * SettingsController.search uses, so a single keystroke never fires a query.
     */
    @AuraEnabled(cacheable=true)
    public static List<PersonResult> searchPeople(String searchTerm) {
        List<PersonResult> result = new List<PersonResult>();
        String trimmed = searchTerm == null ? '' : searchTerm.trim();
        if (trimmed.length() < 2) {
            return result;
        }
        try {
            String likeTerm = '%' + trimmed + '%';
            if (HouseholdService.isPersonAccountOrg()) {
                result.addAll(searchContactsWithoutPersonAccounts(likeTerm));
                result.addAll(searchPersonAccounts(likeTerm));
            } else {
                result.addAll(searchContacts(likeTerm));
            }
            return result;
        } catch (Exception e) {
            throw asUserError(Label.Core_HouseholdPanel_AddSearchFailed);
        }
    }

    /**
     * Joins a person who already exists to this household, in the flexible way of belonging.
     * HouseholdService.addMembers does the join and enforces the rules (R-M5): who this is
     * refuses cleanly when the household is not a household, or when the person cannot join
     * this way.
     */
    @AuraEnabled
    public static void addExistingPerson(Id householdId, Id personId) {
        try {
            if (householdId == null || personId == null) {
                throw new HouseholdException(Label.Core_HouseholdPanel_AddMemberMissingPerson);
            }
            HouseholdService.addMembers(
                new Map<Id, Set<Id>>{ householdId => new Set<Id>{ personId } }
            );
        } catch (HouseholdException e) {
            throw asUserError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership, householdId);
            throw asUserError(Label.Core_HouseholdPanel_AddMemberFailed);
        }
    }

    /**
     * Creates a new contact and joins them to this household, in the flexible way of
     * belonging. The contact is created with this user's own access (ADR-0021 does not cover
     * an ordinary Contact save, only package-owned data), so the save succeeds exactly when
     * the user could have created the contact by hand. The join that follows is the same one
     * addExistingPerson uses.
     */
    @AuraEnabled
    public static void addNewPerson(
        Id householdId,
        String salutation,
        String firstName,
        String lastName
    ) {
        try {
            if (householdId == null || String.isBlank(lastName)) {
                throw new HouseholdException(Label.Core_HouseholdPanel_AddMemberMissingName);
            }
            Contact person = new Contact(
                Salutation = salutation,
                FirstName = firstName,
                LastName = lastName
            );
            Database.insert(person, AccessLevel.USER_MODE);
            HouseholdService.addMembers(
                new Map<Id, Set<Id>>{ householdId => new Set<Id>{ person.Id } }
            );
        } catch (HouseholdException e) {
            throw asUserError(e.getMessage());
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership, householdId);
            throw asUserError(Label.Core_HouseholdPanel_AddMemberFailed);
        }
    }

    // ------------------------------------------------------------------ helpers

    /**
     * The household a contact points at, when it is one. A person stored as an account has
     * no such pointer in the simple way of belonging, so the answer for them is empty.
     */
    private static Set<Id> householdIdFromContact(Id personId) {
        Set<Id> result = new Set<Id>();
        if (personId.getSObjectType() != Contact.SObjectType) {
            return result;
        }
        Id householdRecordTypeId = HouseholdService.householdRecordTypeId();
        for (Contact record : [
            SELECT AccountId, Account.RecordTypeId
            FROM Contact
            WHERE Id = :personId AND AccountId != NULL
            WITH USER_MODE
            LIMIT 1
        ]) {
            if (record.Account.RecordTypeId == householdRecordTypeId) {
                result.add(record.AccountId);
            }
        }
        return result;
    }

    private static List<Account> householdsAsUser(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new List<Account>();
        }
        return [
            SELECT Id, Name, Member_Count__c, Household_Formal_Greeting__c
            FROM Account
            WHERE Id IN :householdIds
            WITH USER_MODE
            ORDER BY Name
            LIMIT 200
        ];
    }

    private static List<Household_Member__c> currentMembershipsAsUser(Id householdId) {
        Date today = Date.today();
        return [
            SELECT Id, Contact__c, Account__c, Is_Primary__c
            FROM Household_Member__c
            WHERE Household__c = :householdId AND (End_Date__c = NULL OR End_Date__c > :today)
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    private static List<PersonResult> searchContacts(String likeTerm) {
        List<PersonResult> result = new List<PersonResult>();
        for (Contact record : [
            SELECT Id, Name
            FROM Contact
            WHERE Name LIKE :likeTerm
            WITH USER_MODE
            ORDER BY Name
            LIMIT 10
        ]) {
            result.add(toPersonResult(record.Id, record.Name));
        }
        return result;
    }

    /**
     * Contacts that are people in their own right, in an org that also stores people as
     * accounts. The contact the platform keeps behind each such account is left out, because
     * that person is offered as the account (PEOPLE-7) and joins by the account side.
     */
    private static List<PersonResult> searchContactsWithoutPersonAccounts(String likeTerm) {
        List<PersonResult> result = new List<PersonResult>();
        Map<String, Object> binds = new Map<String, Object>{ 'likeTerm' => likeTerm };
        for (
            SObject record : Database.queryWithBinds(
                CONTACT_SEARCH_WITHOUT_PERSON_ACCOUNTS,
                binds,
                AccessLevel.USER_MODE
            )
        ) {
            result.add(toPersonResult(record.Id, (String) record.get('Name')));
        }
        return result;
    }

    /**
     * People this org stores as accounts, matched by name. The field that tells such an
     * account apart from an organization exists on the account object only in an org shaped
     * that way, exactly as PersonRecordSelector reads it, so the query is built as text and
     * never names that field at compile time.
     */
    private static List<PersonResult> searchPersonAccounts(String likeTerm) {
        List<PersonResult> result = new List<PersonResult>();
        if (!Schema.SObjectType.Account.isAccessible()) {
            return result;
        }
        String query =
            'SELECT Id, Name FROM Account WHERE Name LIKE :likeTerm AND LastName != NULL ' +
            'ORDER BY Name LIMIT 10';
        Map<String, Object> binds = new Map<String, Object>{ 'likeTerm' => likeTerm };
        for (SObject record : Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)) {
            result.add(toPersonResult(record.Id, (String) record.get('Name')));
        }
        return result;
    }

    private static PersonResult toPersonResult(Id personId, String name) {
        PersonResult result = new PersonResult();
        result.id = personId;
        result.name = name;
        return result;
    }

    private static List<HouseholdView> toViews(List<Account> households) {
        List<HouseholdView> result = new List<HouseholdView>();
        for (Account household : households) {
            HouseholdView view = new HouseholdView();
            view.householdId = household.Id;
            view.name = household.Name;
            view.memberCount = household.Member_Count__c == null
                ? 0
                : household.Member_Count__c.intValue();
            view.formalGreeting = household.Household_Formal_Greeting__c;
            result.add(view);
        }
        return result;
    }

    private static AuraHandledException asUserError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
