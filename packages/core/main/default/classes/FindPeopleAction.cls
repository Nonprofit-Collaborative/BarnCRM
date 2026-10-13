/**
 * The Find People action (Q-14): finds people by name or email address and says which
 * household each belongs to, for a Flow or for a customer's own AI agent (Agentforce, or a
 * Hosted MCP server). BarnCRM ships no AI; the decision is ADR-0104 (agent-ready Core
 * actions) and the setup is in docs/admin-guide/using-barncrm-actions-with-ai.md.
 *
 * It adds no rule of its own. It reads contacts with the running user's own access, maps a
 * person the org stores as an account to that account the way every Core screen does
 * (PersonReference), and asks HouseholdService which household each person is in, so the
 * answer is the same in both membership modes.
 *
 * `global` because only a global invocable method is offered to a Flow or an agent in a
 * subscriber org. Every variable here is permanent once the package is managed: a new
 * optional variable may be added, none removed or renamed. Each label and description is
 * read by an administrator in Flow Builder and by an agent choosing what to call, so each
 * says exactly what the value is, in under 255 characters.
 *
 * Bulk: every request in one call is answered from one contact query (two where the org
 * stores people as accounts), whatever the number of requests.
 */
global with sharing class FindPeopleAction {
    private static final Integer DEFAULT_RESULTS = 10;
    private static final Integer MAX_RESULTS = 25;
    private static final Integer MAX_ROWS = 2000;

    /** One search. */
    global class Request {
        @InvocableVariable(
            label='Search Text'
            description='Required. Part of a person\'s name (at least two characters, for example Garcia or Maria Gar), or a whole email address. An email address is matched exactly, ignoring case.'
            required=true
        )
        global String searchText;

        @InvocableVariable(
            label='Maximum Results'
            description='Optional. The most people to return, from 1 to 25. 10 when left empty.'
        )
        global Integer maxResults;
    }

    /** The answer to one search, in the same position as the search. */
    global class Result {
        @InvocableVariable(
            label='Matches'
            description='The people found, sorted by name. Empty when nobody the running user can see matches.'
        )
        global List<PersonMatch> matches = new List<PersonMatch>();

        @InvocableVariable(
            label='Error Message'
            description='Empty when the search ran. Otherwise why it could not run, in plain words to show the user.'
        )
        global String errorMessage;
    }

    /** One person found. */
    global class PersonMatch {
        @InvocableVariable(
            label='Person Id'
            description='The person\'s record id: the contact, or the account where the org stores the person as an account. Pass it to Get Household Summary or to other actions.'
        )
        global String personId;

        @InvocableVariable(label='Name' description='The person\'s full name.')
        global String name;

        @InvocableVariable(
            label='Email'
            description='The person\'s email address, when they have one and the running user can see it.'
        )
        global String email;

        @InvocableVariable(
            label='Household Id'
            description='The record id of the household the person belongs to. Empty when they are in none, or the running user cannot see it.'
        )
        global String householdId;

        @InvocableVariable(
            label='Household Name'
            description='The name of that household, for example The Garcia Family.'
        )
        global String householdName;
    }

    /**
     * Answers each search, in the order sent. A search that cannot run is answered with an
     * error message rather than failing the others.
     *
     * @param requests one per search
     * @return one result per request, in the same order
     */
    @InvocableMethod(
        label='Find People'
        description='Finds people by part of their name or by their exact email address, and gives each one\'s household. Only people the running user can see are returned. Never creates or changes anything.'
        category='BarnCRM'
    )
    global static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<String> terms = new List<String>();
        for (Request request : requests == null ? new List<Request>() : requests) {
            Result result = new Result();
            String term = request == null ||
                request.searchText == null
                ? ''
                : request.searchText.trim();
            if (term.length() < 2) {
                result.errorMessage = Label.Core_AgentActions_SearchTooShort;
                term = null;
            }
            terms.add(term);
            results.add(result);
        }
        try {
            answer(requests, terms, results);
        } catch (QueryException denied) {
            setErrorForAll(results, Label.Core_AgentActions_NoAccess);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_AgentActions_ErrorContext);
            setErrorForAll(results, Label.Core_AgentActions_Unexpected);
        }
        return results;
    }

    private static void answer(List<Request> requests, List<String> terms, List<Result> results) {
        List<String> nameTerms = new List<String>();
        List<String> emails = new List<String>();
        for (String term : terms) {
            if (term == null) {
                continue;
            }
            if (isEmail(term)) {
                emails.add(term.toLowerCase());
            } else {
                nameTerms.add('%' + term + '%');
            }
        }
        if (nameTerms.isEmpty() && emails.isEmpty()) {
            return;
        }
        List<Contact> found = findContacts(nameTerms, emails);
        Map<Id, Id> personIdByContact = personIdsOf(found);
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(
            new Set<Id>(personIdByContact.values())
        );
        Map<Id, String> householdNames = visibleHouseholdNames(
            new Set<Id>(householdByPerson.values())
        );
        for (Integer i = 0; i < terms.size(); i++) {
            if (terms[i] == null) {
                continue;
            }
            Integer cap = capOf(requests[i]);
            Set<Id> seen = new Set<Id>();
            for (Contact record : found) {
                if (results[i].matches.size() >= cap) {
                    break;
                }
                Id personId = personIdByContact.get(record.Id);
                if (!matches(record, terms[i]) || !seen.add(personId)) {
                    continue;
                }
                results[i]
                    .matches.add(toMatch(record, personId, householdByPerson, householdNames));
            }
        }
    }

    /**
     * Every contact matching any of the searches, read once, in user mode: a contact the
     * running user cannot see is never found, and a user who cannot read contacts at all is
     * refused by the platform rather than answered with nothing.
     */
    private static List<Contact> findContacts(List<String> nameTerms, List<String> emails) {
        // One bind per name pattern: every value reaches the query as a bind, never as text.
        Map<String, Object> binds = new Map<String, Object>{
            'emails' => emails,
            'maxRows' => MAX_ROWS
        };
        List<String> conditions = new List<String>();
        for (Integer i = 0; i < nameTerms.size(); i++) {
            conditions.add('Name LIKE :name' + i);
            binds.put('name' + i, nameTerms[i]);
        }
        if (!emails.isEmpty()) {
            conditions.add('Email IN :emails');
        }
        String query =
            'SELECT Id, Name, Email, AccountId FROM Contact WHERE ' +
            String.join(conditions, ' OR ') +
            ' ORDER BY Name, Id LIMIT :maxRows';
        return Database.queryWithBinds(query, binds, AccessLevel.USER_MODE);
    }

    /**
     * The id each found contact is known by. A person the org stores as an account is known
     * by that account (PersonReference); every other person by their contact. Such an
     * account is told apart from an organization the way PersonRecordSelector does it, by
     * its surname, which exists on the account object only in an org shaped that way, so
     * the query is text and runs only there.
     */
    private static Map<Id, Id> personIdsOf(List<Contact> contacts) {
        Map<Id, Id> result = new Map<Id, Id>();
        Set<Id> accountIds = new Set<Id>();
        for (Contact record : contacts) {
            result.put(record.Id, record.Id);
            if (record.AccountId != null) {
                accountIds.add(record.AccountId);
            }
        }
        if (accountIds.isEmpty() || !HouseholdService.isPersonAccountOrg()) {
            return result;
        }
        Set<Id> personAccounts = new Set<Id>();
        for (
            SObject account : Database.queryWithBinds(
                'SELECT Id FROM Account WHERE Id IN :accountIds AND LastName != NULL',
                new Map<String, Object>{ 'accountIds' => accountIds },
                AccessLevel.USER_MODE
            )
        ) {
            personAccounts.add(account.Id);
        }
        for (Contact record : contacts) {
            if (personAccounts.contains(record.AccountId)) {
                result.put(record.Id, record.AccountId);
            }
        }
        return result;
    }

    /** The names of these households, only those the running user can see. */
    private static Map<Id, String> visibleHouseholdNames(Set<Id> householdIds) {
        Map<Id, String> result = new Map<Id, String>();
        householdIds.remove(null);
        if (householdIds.isEmpty()) {
            return result;
        }
        for (Account household : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :householdIds
            WITH USER_MODE
            LIMIT 2000
        ]) {
            result.put(household.Id, household.Name);
        }
        return result;
    }

    private static PersonMatch toMatch(
        Contact record,
        Id personId,
        Map<Id, Id> householdByPerson,
        Map<Id, String> householdNames
    ) {
        PersonMatch match = new PersonMatch();
        match.personId = personId;
        match.name = record.Name;
        match.email = record.Email;
        Id householdId = householdByPerson.get(personId);
        if (householdId != null && householdNames.containsKey(householdId)) {
            match.householdId = householdId;
            match.householdName = householdNames.get(householdId);
        }
        return match;
    }

    /** The same test the query made, applied to one search. */
    private static Boolean matches(Contact record, String term) {
        if (isEmail(term)) {
            return record.Email != null && record.Email.equalsIgnoreCase(term);
        }
        return record.Name != null && record.Name.containsIgnoreCase(term);
    }

    private static Boolean isEmail(String term) {
        return term.contains('@');
    }

    private static Integer capOf(Request request) {
        Integer asked = request == null ? null : request.maxResults;
        if (asked == null || asked < 1) {
            return DEFAULT_RESULTS;
        }
        return Math.min(asked, MAX_RESULTS);
    }

    private static void setErrorForAll(List<Result> results, String message) {
        for (Result result : results) {
            if (result.errorMessage == null) {
                result.matches.clear();
                result.errorMessage = message;
            }
        }
    }
}
