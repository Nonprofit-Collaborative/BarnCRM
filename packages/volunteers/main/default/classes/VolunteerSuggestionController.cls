/**
 * What Suggested Volunteers on a shift calls (V-11, canonical model Section 29L, R-VU7). It
 * gathers the facts and nothing else: who is free to be suggested and what is known of each
 * (skills, interests, available days, hours, onboarding). The ranking is the framework-free
 * module `rankSuggestions`, so the weights are documented in one place and the logic can move
 * (plan 9.9). Read only and in user mode; booking goes through the Sign-ups panel's own
 * `VolunteerShiftSignupsController.addSignup`, so every sign-up rule applies.
 *
 * People are Contacts: a person held only as a person account is not suggested.
 */
public with sharing class VolunteerSuggestionController {
    private static final String CONTEXT = 'Suggested volunteers';
    /** The most active volunteers considered, most hours first: a bound on the read. */
    public static final Integer MAX_CANDIDATES = 500;

    private static final List<String> WEEKDAYS = new List<String>{
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
    };
    /** A Monday, from which the weekday of any later date is counted. */
    private static final Date A_MONDAY = Date.newInstance(1900, 1, 1);

    /** One person who could be booked, with the facts the ranking weighs. */
    public class Candidate {
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public List<String> availableDays = new List<String>();
        @AuraEnabled
        public List<Id> skillIds = new List<Id>();
        @AuraEnabled
        public List<Id> interestIds = new List<Id>();
        @AuraEnabled
        public Decimal hoursOnJob = 0;
        @AuraEnabled
        public Decimal hoursTotal = 0;
        /** `cleared` (every step current), `open` (a step not current) or `none` (no steps seen). */
        @AuraEnabled
        public String onboarding = 'none';
    }

    /** The shift's side of the ranking and the people to rank. */
    public class Suggestions {
        /** False when the user cannot book, or the shift is not Open: the card shows nothing. */
        @AuraEnabled
        public Boolean canBook = false;
        @AuraEnabled
        public String weekday;
        @AuraEnabled
        public List<Id> requiredSkillIds = new List<Id>();
        @AuraEnabled
        public List<Candidate> candidates = new List<Candidate>();
        @AuraEnabled
        public Boolean moreThanConsidered = false;
    }

    /** Not cacheable: it changes with every sign-up. */
    @AuraEnabled
    public static Suggestions getSuggestions(Id shiftId) {
        Suggestions result = new Suggestions();
        if (shiftId == null) {
            return result;
        }
        try {
            Volunteer_Shift__c shift = VolunteerSuggestionSelector.selectShift(shiftId);
            if (
                shift == null ||
                shift.Status__c != 'Open' ||
                shift.Start_Time__c == null ||
                !Schema.SObjectType.Volunteer_Signup__c.isCreateable()
            ) {
                return result;
            }
            result.canBook = true;
            result.weekday = weekdayOf(shift.Start_Time__c);
            Set<Id> required = VolunteerSuggestionSelector.requiredSkillIds(shift.Volunteer_Job__c);
            result.requiredSkillIds = new List<Id>(required);

            List<Contact> people = VolunteerSuggestionSelector.selectCandidates(
                shiftId,
                MAX_CANDIDATES + 1
            );
            result.moreThanConsidered = people.size() > MAX_CANDIDATES;
            while (people.size() > MAX_CANDIDATES) {
                people.remove(people.size() - 1);
            }
            addFacts(result, people, shift, required);
            return result;
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, shiftId);
            AuraHandledException refused = new AuraHandledException(
                Label.Volunteers_Suggestions_LoadFailed
            );
            refused.setMessage(Label.Volunteers_Suggestions_LoadFailed);
            throw refused;
        }
    }

    // ------------------------------------------------------------------------------ helpers

    private static void addFacts(
        Suggestions result,
        List<Contact> people,
        Volunteer_Shift__c shift,
        Set<Id> required
    ) {
        if (people.isEmpty()) {
            return;
        }
        Map<Id, Candidate> byId = new Map<Id, Candidate>();
        for (Contact person : people) {
            Candidate candidate = new Candidate();
            candidate.personId = person.Id;
            candidate.name = person.Name;
            candidate.hoursTotal = person.Volunteer_Hours_Total__c == null
                ? 0
                : person.Volunteer_Hours_Total__c;
            if (String.isNotBlank(person.Availability_Days__c)) {
                candidate.availableDays = person.Availability_Days__c.split(';');
            }
            byId.put(person.Id, candidate);
            result.candidates.add(candidate);
        }
        Set<Id> ids = byId.keySet();

        if (!required.isEmpty()) {
            for (
                Volunteer_Skill__c row : VolunteerSuggestionSelector.selectSkillRows(ids, required)
            ) {
                Candidate candidate = byId.get(row.Contact__c);
                if (row.Type__c == 'Interest') {
                    candidate.interestIds.add(row.Skill__c);
                } else {
                    candidate.skillIds.add(row.Skill__c);
                }
            }
        }
        Map<Id, Decimal> onJob = VolunteerSuggestionSelector.approvedHoursOnJob(
            ids,
            shift.Volunteer_Job__c
        );
        for (Id personId : onJob.keySet()) {
            byId.get(personId).hoursOnJob = onJob.get(personId);
        }
        addOnboarding(byId, VolunteerSuggestionSelector.selectRequirements(ids));
    }

    /** A person with any latest-of-its-Type step not current is `open`; all current is `cleared`. */
    private static void addOnboarding(
        Map<Id, Candidate> byId,
        List<Volunteer_Requirement__c> steps
    ) {
        Set<String> seen = new Set<String>();
        for (Volunteer_Requirement__c step : steps) {
            if (!seen.add(step.Contact__c + '|' + step.Type__c)) {
                continue;
            }
            Candidate candidate = byId.get(step.Contact__c);
            if (candidate == null || candidate.onboarding == 'open') {
                continue;
            }
            candidate.onboarding = step.Is_Current__c == true ? 'cleared' : 'open';
        }
    }

    /** The shift's weekday in the org's time zone, named as the Availability Days picklist is. */
    @TestVisible
    private static String weekdayOf(Datetime start) {
        Date day = ShiftScheduleService.orgDate(start);
        return WEEKDAYS[Math.mod(A_MONDAY.daysBetween(day), 7)];
    }
}
