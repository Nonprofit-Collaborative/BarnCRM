/**
 * What the Cohort Members panel on a cohort calls (P-11, canonical model 29ZA4, R-CO3).
 *
 * Lists the cohort's members (the enrollments that name it) and the program's open enrollments
 * in no cohort, and adds many people in one action: a person with an open enrollment in the
 * program is moved into the cohort, one without is enrolled in it at stage Enrolled. Each person
 * succeeds or fails alone. All reads and writes are in user mode and go through the enrollment
 * rules like any other save. Returns plain wrappers (plan Section 9.9); anything unexpected is
 * recorded in the Error Log before it is reported (plan Section 7.2).
 */
public with sharing class CohortController {
    private static final String CONTEXT = 'Cohort members panel';
    /** The most people listed, and the most added in one action. */
    public static final Integer MAX_SHOWN = 200;
    /** As ProgramRosterController: offered to the record picker only in a person account org. */
    private static final String PERSON_ACCOUNT_FILTER_FIELD = 'IsPersonAccount'; // detection-only: a record picker filter field, sent only after isPersonAccountOrg found person accounts

    public class Member {
        @AuraEnabled
        public Id enrollmentId;
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public String stage;
        @AuraEnabled
        public Date startDate;
    }

    public class Failure {
        @AuraEnabled
        public String personName;
        @AuraEnabled
        public String message;
    }

    /** The panel's whole state. */
    public class Members {
        @AuraEnabled
        public Id cohortId;
        @AuraEnabled
        public String cohortName;
        @AuraEnabled
        public Id programId;
        @AuraEnabled
        public String programName;
        @AuraEnabled
        public List<Member> members = new List<Member>();
        @AuraEnabled
        public List<Member> candidates = new List<Member>();
        @AuraEnabled
        public Boolean moreThanShown = false;
        @AuraEnabled
        public Boolean canEdit = false;
        @AuraEnabled
        public Boolean canEnroll = false;
        @AuraEnabled
        public Boolean hasPersonAccounts = false;
        @AuraEnabled
        public String personFilterField;
        @AuraEnabled
        public Integer maxPerAction = MAX_SHOWN;
        /** After an add: how many were added, and who could not be. */
        @AuraEnabled
        public Integer added = 0;
        @AuraEnabled
        public List<Failure> failures = new List<Failure>();
    }

    /** Not cacheable: membership changes with every add and remove. */
    @AuraEnabled
    public static Members getMembers(Id cohortId) {
        try {
            return membersOf(checkedCohort(cohortId));
        } catch (Exception failure) {
            throw report(failure, cohortId);
        }
    }

    /**
     * Adds these open enrollments of the program and these people to the cohort, each alone
     * (R-CO3), then returns the panel with how many were added and who failed and why.
     */
    @AuraEnabled
    public static Members addMembers(Id cohortId, List<Id> enrollmentIds, List<Id> personIds) {
        List<Id> enrollments = enrollmentIds == null ? new List<Id>() : enrollmentIds;
        List<Id> people = personIds == null ? new List<Id>() : personIds;
        if (enrollments.isEmpty() && people.isEmpty()) {
            throw UserErrors.message(Label.Programs_Cohort_NobodyChosen);
        }
        if (enrollments.size() + people.size() > MAX_SHOWN) {
            throw UserErrors.message(
                String.format(Label.Programs_Cohort_TooMany, new List<Object>{ MAX_SHOWN })
            );
        }
        try {
            Cohort__c cohort = checkedCohort(cohortId);
            CohortService.Outcome outcome = CohortService.addMembers(
                cohort,
                new Set<Id>(enrollments),
                new Set<Id>(people)
            );
            Members result = membersOf(cohort);
            result.added = outcome.added;
            for (CohortService.Refusal refusal : outcome.refusals) {
                Failure failure = new Failure();
                failure.personName = refusal.personName;
                failure.message = refusal.message;
                result.failures.add(failure);
            }
            return result;
        } catch (Exception failure) {
            throw report(failure, cohortId);
        }
    }

    /** The name of a person just picked, for the list of people to add. */
    @AuraEnabled(cacheable=true)
    public static String getPersonName(Id personId) {
        if (personId == null) {
            return null;
        }
        return CohortSelector.selectPersonNames(new Set<Id>{ personId }).get(personId);
    }

    /** Takes one enrollment out of the cohort; the enrollment is kept. */
    @AuraEnabled
    public static Members removeMember(Id cohortId, Id enrollmentId) {
        if (enrollmentId == null) {
            throw UserErrors.message(Label.Programs_Cohort_ActionFailed);
        }
        try {
            Cohort__c cohort = checkedCohort(cohortId);
            CohortService.removeMember(cohort.Id, enrollmentId);
            return membersOf(cohort);
        } catch (Exception failure) {
            throw report(failure, cohortId);
        }
    }

    // ------------------------------------------------------------------------------ helpers

    private static Cohort__c checkedCohort(Id cohortId) {
        Cohort__c cohort = cohortId == null ? null : CohortSelector.selectCohort(cohortId);
        if (cohort == null) {
            throw UserErrors.message(Label.Programs_Cohort_NotFound);
        }
        return cohort;
    }

    private static Members membersOf(Cohort__c cohort) {
        Members result = new Members();
        result.cohortId = cohort.Id;
        result.cohortName = cohort.Name;
        result.programId = cohort.Program__c;
        result.programName = cohort.Program__r == null ? null : cohort.Program__r.Name;
        Set<String> stages = new Set<String>(EnrollmentService.STAGES);
        List<Enrollment__c> found = CohortSelector.selectMembers(cohort.Id, stages, MAX_SHOWN + 1);
        result.moreThanShown = found.size() > MAX_SHOWN;
        for (Integer i = 0; i < found.size() && i < MAX_SHOWN; i++) {
            result.members.add(memberFor(found[i]));
        }
        for (
            Enrollment__c open : CohortSelector.selectWithoutCohort(cohort.Program__c, MAX_SHOWN)
        ) {
            result.candidates.add(memberFor(open));
        }
        Schema.DescribeSObjectResult describe = Enrollment__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        );
        result.canEdit =
            describe.isUpdateable() &&
            Schema.SObjectType.Enrollment__c.fields.Cohort__c.isUpdateable();
        result.canEnroll = result.canEdit && describe.isCreateable();
        result.hasPersonAccounts = HouseholdService.isPersonAccountOrg();
        result.personFilterField = result.hasPersonAccounts ? PERSON_ACCOUNT_FILTER_FIELD : null;
        return result;
    }

    private static Member memberFor(Enrollment__c enrollment) {
        Member member = new Member();
        member.enrollmentId = enrollment.Id;
        member.stage = enrollment.Stage__c;
        member.startDate = enrollment.Start_Date__c;
        member.personName = CohortService.personNameOf(enrollment);
        return member;
    }

    /** A refusal is passed on in its own words; anything else is logged first. */
    private static AuraHandledException report(Exception failure, Id recordId) {
        if (failure instanceof AuraHandledException) {
            return (AuraHandledException) failure;
        }
        if (failure instanceof DmlException) {
            return UserErrors.message(((DmlException) failure).getDmlMessage(0));
        }
        ErrorLogger.log(failure, CONTEXT, recordId);
        return UserErrors.message(Label.Programs_Cohort_ActionFailed);
    }
}
