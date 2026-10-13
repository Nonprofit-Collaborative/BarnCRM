/**
 * The Get Household Summary action (Q-14): a household's name, greetings, primary contact,
 * mailing address and members, for a Flow or for a customer's own AI agent. BarnCRM ships
 * no AI (ADR-0104, agent-ready Core actions).
 *
 * It adds no rule of its own. A person is resolved to their household by
 * HouseholdService.getHouseholdIdsFor and the members are read by
 * HouseholdService.getMembersAsUser, the read the household members panel uses, so the
 * answer is the same in both membership modes. Everything is read with the running user's
 * own access (ADR-0021): a household they cannot see is not found, and a member field they
 * cannot read is left empty.
 *
 * `global` because only a global invocable method is offered to a Flow or an agent in a
 * subscriber org; every variable is permanent once the package is managed.
 *
 * Bulk: one household query and one members read for every request in the call.
 */
global with sharing class GetHouseholdSummaryAction {
    /** One household asked about. */
    global class Request {
        @InvocableVariable(
            label='Household or Person Id'
            description='Required. The record id of a household, or of a person (for example a Person Id from Find People), in which case the household that person belongs to is summarized.'
            required=true
        )
        global String recordId;
    }

    /** The summary of one household, in the same position as the request. */
    global class Result {
        @InvocableVariable(label='Household Id' description='The household\'s record id.')
        global String householdId;

        @InvocableVariable(
            label='Household Name'
            description='The household\'s name, for example The Garcia Family.'
        )
        global String name;

        @InvocableVariable(
            label='Formal Greeting'
            description='How a letter to the household is addressed, for example Ms. Maria Garcia and Mr. Wei Lee.'
        )
        global String formalGreeting;

        @InvocableVariable(
            label='Informal Greeting'
            description='How the household is greeted informally, for example Maria and Wei.'
        )
        global String informalGreeting;

        @InvocableVariable(
            label='Member Count'
            description='How many people currently belong to the household.'
        )
        global Integer memberCount;

        @InvocableVariable(
            label='Primary Contact Name'
            description='The name of the household\'s primary contact, the person mail and calls go to first. Empty when none is set.'
        )
        global String primaryContactName;

        @InvocableVariable(
            label='Mailing Address'
            description='The household\'s current mailing address on one line: street, city, state, postal code and country. Empty when none is recorded.'
        )
        global String mailingAddress;

        @InvocableVariable(
            label='Members'
            description='The people who currently belong to the household, the primary member first.'
        )
        global List<Member> members = new List<Member>();

        @InvocableVariable(
            label='Error Message'
            description='Empty when the household was found. Otherwise why not, in plain words to show the user.'
        )
        global String errorMessage;
    }

    /** One person in the household. */
    global class Member {
        @InvocableVariable(label='Person Id' description='The person\'s record id.')
        global String personId;

        @InvocableVariable(label='Name' description='The person\'s full name.')
        global String name;

        @InvocableVariable(
            label='Role'
            description='The person\'s role in the household, for example Head, Spouse or Partner, or Child. Empty when none is set.'
        )
        global String role;

        @InvocableVariable(
            label='Is Primary'
            description='True for the household\'s primary member.'
        )
        global Boolean isPrimary;

        @InvocableVariable(
            label='Is Deceased'
            description='True when the person has died. Do not suggest contacting them.'
        )
        global Boolean isDeceased;
    }

    /**
     * Summarizes each household asked about, in the order sent. One that cannot be found is
     * answered with an error message rather than failing the others.
     *
     * @param requests one per household or person
     * @return one result per request, in the same order
     */
    @InvocableMethod(
        label='Get Household Summary'
        description='Summarizes a household: its name, greetings, primary contact, mailing address and members with their roles. Give it a household id or a person id. Read only: never changes anything.'
        category='BarnCRM'
    )
    global static List<Result> summarize(List<Request> requests) {
        List<Result> results = new List<Result>();
        List<Id> householdIds = new List<Id>();
        Set<Id> personIds = new Set<Id>();
        for (Request request : requests == null ? new List<Request>() : requests) {
            Id recordId = idOf(request);
            results.add(new Result());
            householdIds.add(recordId);
            if (recordId != null && recordId.getSObjectType() == Contact.SObjectType) {
                personIds.add(recordId);
            }
        }
        try {
            answer(householdIds, personIds, results);
        } catch (QueryException denied) {
            setErrorForAll(results, Label.Core_AgentActions_NoAccess);
        } catch (Exception failed) {
            ErrorLogger.log(failed, Label.Core_AgentActions_ErrorContext);
            setErrorForAll(results, Label.Core_AgentActions_Unexpected);
        }
        return results;
    }

    private static void answer(List<Id> recordIds, Set<Id> personIds, List<Result> results) {
        // An account id may be a household or a person stored as an account: whichever it
        // is not a household of is resolved as a person below.
        Map<Id, Account> households = householdsAsUser(new Set<Id>(recordIds));
        for (Id recordId : recordIds) {
            if (
                recordId != null &&
                recordId.getSObjectType() == Account.SObjectType &&
                !households.containsKey(recordId)
            ) {
                personIds.add(recordId);
            }
        }
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(personIds);
        Set<Id> moreHouseholds = new Set<Id>(householdByPerson.values());
        moreHouseholds.removeAll(households.keySet());
        moreHouseholds.remove(null);
        households.putAll(householdsAsUser(moreHouseholds));
        Map<Id, List<HouseholdService.Person>> membersByHousehold = HouseholdService.getMembersAsUser(
            households.keySet()
        );
        for (Integer i = 0; i < recordIds.size(); i++) {
            Id recordId = recordIds[i];
            Id householdId = households.containsKey(recordId)
                ? recordId
                : householdByPerson.get(recordId);
            Account household = householdId == null ? null : households.get(householdId);
            if (household == null) {
                // A contact that resolves to no household is a person in none. An account id
                // may be an organization as well as a person, so it is answered as not found.
                results[i].errorMessage = recordId != null &&
                    recordId.getSObjectType() == Contact.SObjectType
                    ? Label.Core_AgentActions_PersonHasNoHousehold
                    : Label.Core_AgentActions_HouseholdNotFound;
                continue;
            }
            fill(results[i], household, membersByHousehold.get(household.Id));
        }
    }

    /**
     * The households among these ids, read in user mode: an id that is not a household, or
     * one the running user cannot see, is simply absent.
     */
    private static Map<Id, Account> householdsAsUser(Set<Id> recordIds) {
        Set<Id> accountIds = new Set<Id>();
        for (Id recordId : recordIds) {
            if (recordId != null && recordId.getSObjectType() == Account.SObjectType) {
                accountIds.add(recordId);
            }
        }
        Id householdRecordType = HouseholdService.householdRecordTypeId();
        if (accountIds.isEmpty() || householdRecordType == null) {
            return new Map<Id, Account>();
        }
        return new Map<Id, Account>(
            [
                SELECT
                    Id,
                    Name,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c,
                    Member_Count__c,
                    Primary_Contact__c,
                    Primary_Contact__r.Name,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingPostalCode,
                    BillingCountry
                FROM Account
                WHERE Id IN :accountIds AND RecordTypeId = :householdRecordType
                WITH USER_MODE
                LIMIT 2000
            ]
        );
    }

    private static void fill(
        Result result,
        Account household,
        List<HouseholdService.Person> people
    ) {
        result.householdId = household.Id;
        result.name = household.Name;
        result.formalGreeting = household.Household_Formal_Greeting__c;
        result.informalGreeting = household.Household_Informal_Greeting__c;
        result.memberCount = household.Member_Count__c == null
            ? 0
            : household.Member_Count__c.intValue();
        result.primaryContactName = household.Primary_Contact__r?.Name;
        result.mailingAddress = oneLine(household);
        List<Member> primaryFirst = new List<Member>();
        for (
            HouseholdService.Person person : people == null
                ? new List<HouseholdService.Person>()
                : people
        ) {
            Member member = new Member();
            member.personId = person.id;
            member.name = fullName(person);
            member.role = person.role;
            // The membership row marks the primary member in junction mode; in contact mode
            // the household's Primary Contact is the mark itself (ADR-0044).
            member.isPrimary =
                person.isPrimary == true ||
                (person.id != null &&
                person.id == household.Primary_Contact__c);
            member.isDeceased = person.isDeceased == true;
            if (member.isPrimary && !primaryFirst.isEmpty()) {
                primaryFirst.add(0, member);
            } else {
                primaryFirst.add(member);
            }
        }
        result.members = primaryFirst;
    }

    private static String oneLine(Account household) {
        List<String> parts = new List<String>();
        for (
            String part : new List<String>{
                household.BillingStreet,
                household.BillingCity,
                household.BillingState,
                household.BillingPostalCode,
                household.BillingCountry
            }
        ) {
            if (String.isNotBlank(part)) {
                parts.add(part.replaceAll('\\s*\\n\\s*', ', ').trim());
            }
        }
        return parts.isEmpty() ? null : String.join(parts, ', ');
    }

    private static String fullName(HouseholdService.Person person) {
        String first = String.isNotBlank(person.preferredName)
            ? person.preferredName
            : person.firstName;
        return ((first == null ? '' : first) +
            ' ' +
            (person.lastName == null ? '' : person.lastName))
            .trim();
    }

    private static Id idOf(Request request) {
        if (request == null || String.isBlank(request.recordId)) {
            return null;
        }
        try {
            return Id.valueOf(request.recordId.trim());
        } catch (StringException notAnId) {
            return null;
        }
    }

    private static void setErrorForAll(List<Result> results, String message) {
        for (Result result : results) {
            result.members.clear();
            result.householdId = null;
            result.name = null;
            result.errorMessage = message;
        }
    }
}
