/**
 * The same-name hint (people-giving-24): while someone types a new person's name in Add
 * Member or the inline new person dialog, the people already in BarnCRM with that exact first
 * and last name, each with a city and household so two Ana Garcias can be told apart. The
 * dialog offers "Use this person instead?" for each, so a duplicate is never made by accident.
 *
 * Read in user mode, so a person this user cannot see is never offered. Contacts only: in an
 * org that also stores people as accounts, each such person has a contact behind the account,
 * and HouseholdService.addMembers joins that contact as its account (PEOPLE-7).
 */
public with sharing class PersonSameNameController {
    private static final Integer MAX_MATCHES = 5;

    /** One person with the same name. */
    public class Match {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String city;
        @AuraEnabled
        public String householdName;
    }

    /**
     * People named exactly firstName lastName (case does not matter), leaving out the members
     * of excludeHouseholdId (the household someone is being added to: they are already in
     * it). A blank first name matches on the last name alone. Nothing is asked for until the
     * last name has two characters, the floor the Add Member search uses.
     */
    @AuraEnabled(cacheable=true)
    public static List<Match> findSameName(
        String firstName,
        String lastName,
        Id excludeHouseholdId
    ) {
        List<Match> result = new List<Match>();
        String last = lastName == null ? '' : lastName.trim();
        String first = firstName == null ? '' : firstName.trim();
        if (last.length() < 2) {
            return result;
        }
        try {
            List<Contact> people = (List<Contact>) Database.queryWithBinds(
                'SELECT Id, Name, MailingCity, AccountId, Account.Name, Account.RecordTypeId ' +
                    'FROM Contact WHERE LastName = :last' +
                    (String.isBlank(first) ? '' : ' AND FirstName = :first') +
                    ' ORDER BY Name LIMIT 20',
                new Map<String, Object>{ 'last' => last, 'first' => first },
                AccessLevel.USER_MODE
            );
            if (people.isEmpty()) {
                return result;
            }
            Set<Id> alreadyIn = new Set<Id>();
            Map<Id, Account> householdByPerson = householdsOf(
                people,
                excludeHouseholdId,
                alreadyIn
            );
            for (Contact person : people) {
                if (alreadyIn.contains(person.Id)) {
                    continue;
                }
                Account household = householdByPerson.get(person.Id);
                Match match = new Match();
                match.id = person.Id;
                match.name = person.Name;
                match.city = person.MailingCity;
                match.householdName = household == null ? null : household.Name;
                result.add(match);
                if (result.size() == MAX_MATCHES) {
                    break;
                }
            }
            return result;
        } catch (Exception e) {
            // A hint that cannot be read is no hint: the person can still be saved. The failure
            // is logged, so a sharing or access problem is not mistaken for "no matches".
            ErrorLogger.log(e, 'PersonSameNameController');
            return new List<Match>();
        }
    }

    /**
     * Each person's current household: the account the contact points at when it is a
     * household, and in the flexible way of belonging the household of a current membership
     * row. The people who already belong to excludeHouseholdId are added to alreadyIn.
     */
    private static Map<Id, Account> householdsOf(
        List<Contact> people,
        Id excludeHouseholdId,
        Set<Id> alreadyIn
    ) {
        Map<Id, Account> result = new Map<Id, Account>();
        Id householdRecordTypeId = HouseholdService.householdRecordTypeId();
        Set<Id> personIds = new Set<Id>();
        for (Contact person : people) {
            personIds.add(person.Id);
            if (
                person.AccountId != null &&
                householdRecordTypeId != null &&
                person.Account.RecordTypeId == householdRecordTypeId
            ) {
                result.put(
                    person.Id,
                    new Account(Id = person.AccountId, Name = person.Account.Name)
                );
                if (person.AccountId == excludeHouseholdId) {
                    alreadyIn.add(person.Id);
                }
            }
        }
        if (HouseholdService.isJunctionMode()) {
            Date today = Date.today();
            for (Household_Member__c membership : [
                SELECT Contact__c, Household__c, Household__r.Name
                FROM Household_Member__c
                WHERE Contact__c IN :personIds AND (End_Date__c = NULL OR End_Date__c > :today)
                WITH USER_MODE
                ORDER BY Start_Date__c
                LIMIT 1000
            ]) {
                if (membership.Household__c == excludeHouseholdId) {
                    alreadyIn.add(membership.Contact__c);
                }
                if (!result.containsKey(membership.Contact__c)) {
                    result.put(
                        membership.Contact__c,
                        new Account(
                            Id = membership.Household__c,
                            Name = membership.Household__r.Name
                        )
                    );
                }
            }
        }
        return result;
    }
}
