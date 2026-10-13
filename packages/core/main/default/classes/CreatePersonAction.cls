/**
 * The Create Person action (Q-14): adds a new person, either to a household that already
 * exists or with a household of their own, for a Flow or for a customer's own AI agent.
 * BarnCRM ships no AI (ADR-0104, agent-ready Core actions).
 *
 * It adds no rule of its own. The person is an ordinary contact saved with the running
 * user's own access, so the org's duplicate, validation and sharing rules apply exactly as
 * when someone saves one by hand, and the contact trigger gives a person with no household
 * one of their own when the org asks for that (R-H1, R-H2). A person added to a household is
 * saved against it, the way an import that names a household saves one, so automatic
 * creation leaves them alone, and then joined by HouseholdService.addMembers, which does what
 * joining means in the org's membership mode (R-M5). Joining needs edit access to the
 * household, as moving a person does (HouseholdService.moveContact).
 *
 * `global` because only a global invocable method is offered to a Flow or an agent in a
 * subscriber org; every variable is permanent once the package is managed.
 *
 * Bulk: one insert and one join for every request in the call. A person the platform
 * refuses is answered with the reason and the others are still saved; a join that fails
 * undoes the whole call, so nobody is left in a household they were not asked into.
 */
global with sharing class CreatePersonAction {
    /** One person to add. */
    global class Request {
        @InvocableVariable(label='First Name' description='Optional. The person\'s first name.')
        global String firstName;

        @InvocableVariable(
            label='Last Name'
            description='Required. The person\'s last name.'
            required=true
        )
        global String lastName;

        @InvocableVariable(label='Email' description='Optional. The person\'s email address.')
        global String email;

        @InvocableVariable(
            label='Household Id'
            description='Optional. The record id of an existing household to add the person to, for example a Household Id from Find People. Leave empty to give the person a household of their own, when the org creates households automatically.'
        )
        global String householdId;
    }

    /** What happened to one person, in the same position as the request. */
    global class Result {
        @InvocableVariable(
            label='Person Id'
            description='The new person\'s record id. Empty when the person was not created.'
        )
        global String personId;

        @InvocableVariable(
            label='Household Id'
            description='The record id of the household the person now belongs to. Empty when they are in none.'
        )
        global String householdId;

        @InvocableVariable(
            label='Error Message'
            description='Empty when the person was created. Otherwise why not, in plain words to show the user. Nothing was created for this request.'
        )
        global String errorMessage;
    }

    /**
     * Creates each person asked for, in the order sent.
     *
     * @param requests one per person
     * @return one result per request, in the same order
     */
    @InvocableMethod(
        label='Create Person'
        description='Creates a new person, added to an existing household or given a household of their own. Use Find People first so you do not create someone who already exists. Never changes or merges existing people.'
        category='BarnCRM'
    )
    global static List<Result> create(List<Request> requests) {
        List<Request> asked = requests == null ? new List<Request>() : requests;
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < asked.size(); i++) {
            results.add(new Result());
        }
        Savepoint beforeSave = Database.setSavepoint();
        try {
            save(asked, results);
        } catch (QueryException denied) {
            undo(beforeSave, results, Label.Core_AgentActions_NoAccess);
        } catch (SecurityException denied) {
            undo(beforeSave, results, Label.Core_AgentActions_NoAccess);
        } catch (HouseholdException refused) {
            undo(beforeSave, results, refused.getMessage());
        } catch (Exception failed) {
            undo(beforeSave, results, Label.Core_AgentActions_Unexpected);
            ErrorLogger.log(failed, Label.Core_AgentActions_ErrorContext);
        }
        return results;
    }

    /** Nothing from this call is kept, and every request is told why. */
    private static void undo(Savepoint beforeSave, List<Result> results, String message) {
        Database.rollback(beforeSave);
        for (Result result : results) {
            result.personId = null;
            result.householdId = null;
            result.errorMessage = message;
        }
    }

    private static void save(List<Request> asked, List<Result> results) {
        Map<Integer, Id> householdByPosition = checkHouseholds(asked, results);
        List<Contact> people = new List<Contact>();
        List<Integer> positions = new List<Integer>();
        for (Integer i = 0; i < asked.size(); i++) {
            if (results[i].errorMessage != null) {
                continue;
            }
            Request request = asked[i];
            people.add(
                new Contact(
                    FirstName = trimmed(request.firstName),
                    LastName = trimmed(request.lastName),
                    Email = trimmed(request.email),
                    AccountId = householdByPosition.get(i)
                )
            );
            positions.add(i);
        }
        if (people.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saved = Database.insert(people, false, AccessLevel.USER_MODE);
        Map<Id, Set<Id>> joining = new Map<Id, Set<Id>>();
        Set<Id> created = new Set<Id>();
        for (Integer n = 0; n < saved.size(); n++) {
            Result result = results[positions[n]];
            if (!saved[n].isSuccess()) {
                result.errorMessage = refusal(saved[n]);
                continue;
            }
            result.personId = saved[n].getId();
            created.add(saved[n].getId());
            Id householdId = householdByPosition.get(positions[n]);
            if (householdId != null) {
                if (!joining.containsKey(householdId)) {
                    joining.put(householdId, new Set<Id>());
                }
                joining.get(householdId).add(saved[n].getId());
            }
        }
        if (!joining.isEmpty()) {
            HouseholdService.addMembers(joining);
        }
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(created);
        for (Result result : results) {
            if (result.personId != null) {
                result.householdId = householdByPerson.get(result.personId);
            }
        }
    }

    /**
     * Validates every request before anything is saved: a last name is required, and a
     * household named must be a household the running user can edit. Answers the household
     * of each valid request by its position.
     */
    private static Map<Integer, Id> checkHouseholds(List<Request> asked, List<Result> results) {
        Map<Integer, Id> householdByPosition = new Map<Integer, Id>();
        for (Integer i = 0; i < asked.size(); i++) {
            Request request = asked[i];
            if (request == null || String.isBlank(request.lastName)) {
                results[i].errorMessage = Label.Core_HouseholdPanel_AddMemberMissingName;
                continue;
            }
            if (String.isBlank(request.householdId)) {
                continue;
            }
            Id householdId = accountIdOf(request.householdId);
            if (householdId == null) {
                results[i].errorMessage = Label.Core_Households_ErrorNotAHousehold;
                continue;
            }
            householdByPosition.put(i, householdId);
        }
        if (householdByPosition.isEmpty()) {
            return householdByPosition;
        }
        Set<Id> named = new Set<Id>(householdByPosition.values());
        Set<Id> households = householdsAmong(named);
        Set<Id> editable = HouseholdSelector.getEditableIds(households);
        for (Integer i : new List<Integer>(householdByPosition.keySet())) {
            Id householdId = householdByPosition.get(i);
            if (!households.contains(householdId)) {
                results[i].errorMessage = Label.Core_Households_ErrorNotAHousehold;
            } else if (!editable.contains(householdId)) {
                results[i].errorMessage = Label.Core_AgentActions_HouseholdNoEditAccess;
            } else {
                continue;
            }
            householdByPosition.remove(i);
        }
        return householdByPosition;
    }

    /** Those of these accounts that are households the running user can see. */
    private static Set<Id> householdsAmong(Set<Id> accountIds) {
        Id householdRecordType = HouseholdService.householdRecordTypeId();
        Set<Id> result = new Set<Id>();
        if (householdRecordType == null) {
            return result;
        }
        for (Account household : [
            SELECT Id
            FROM Account
            WHERE Id IN :accountIds AND RecordTypeId = :householdRecordType
            WITH USER_MODE
            LIMIT 200
        ]) {
            result.add(household.Id);
        }
        return result;
    }

    /**
     * The platform's own reason for a refused save: it is already worded for a person (a
     * duplicate rule's alert, a validation rule's message, or the missing access).
     */
    private static String refusal(Database.SaveResult refused) {
        List<String> reasons = new List<String>();
        for (Database.Error error : refused.getErrors()) {
            reasons.add(error.getMessage());
        }
        return reasons.isEmpty() ? Label.Core_AgentActions_Unexpected : String.join(reasons, ' ');
    }

    private static Id accountIdOf(String value) {
        try {
            Id candidate = Id.valueOf(value.trim());
            return candidate.getSObjectType() == Account.SObjectType ? candidate : null;
        } catch (StringException notAnId) {
            return null;
        }
    }

    private static String trimmed(String value) {
        return String.isBlank(value) ? null : value.trim();
    }
}
