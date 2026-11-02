/**
 * The reads cohorts and sessions make for the person using them, in user mode (P-11, canonical
 * model 29ZA5 and 29ZA6).
 */
public with sharing class CohortSelector {
    /** The cohort with its program, or null when the user cannot see it. */
    public static Cohort__c selectCohort(Id cohortId) {
        List<Cohort__c> found = [
            SELECT Id, Name, Program__c, Program__r.Name, Status__c, Start_Date__c, End_Date__c
            FROM Cohort__c
            WHERE Id = :cohortId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** The program's name, or null when the user cannot see it. */
    public static Program__c selectProgram(Id programId) {
        List<Program__c> found = [
            SELECT Id, Name
            FROM Program__c
            WHERE Id = :programId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /** The session with its service, program and cohort, or null when the user cannot see it. */
    public static Session__c selectSession(Id sessionId) {
        List<Session__c> found = [
            SELECT
                Id,
                Name,
                Service__c,
                Service__r.Name,
                Service__r.Program__c,
                Service__r.Unit_Of_Measure__c,
                Cohort__c,
                Cohort__r.Name,
                Session_Date__c,
                Start_Time__c,
                Status__c
            FROM Session__c
            WHERE Id = :sessionId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }

    /**
     * The cohort's enrollments at these stages, newest start first, at most `howMany`, with the
     * name of the person each names.
     */
    public static List<Enrollment__c> selectMembers(
        Id cohortId,
        Set<String> stages,
        Integer howMany
    ) {
        return [
            SELECT
                Id,
                Name,
                Stage__c,
                Start_Date__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name
            FROM Enrollment__c
            WHERE Cohort__c = :cohortId AND Stage__c IN :stages
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS LAST, Name
            LIMIT :howMany
        ];
    }

    /** The program's open enrollments in no cohort, at most `howMany`: who may be added. */
    public static List<Enrollment__c> selectWithoutCohort(Id programId, Integer howMany) {
        return [
            SELECT
                Id,
                Name,
                Stage__c,
                Start_Date__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name
            FROM Enrollment__c
            WHERE
                Program__c = :programId
                AND Cohort__c = NULL
                AND Stage__c IN :EnrollmentService.OPEN_STAGES
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS LAST, Name
            LIMIT :howMany
        ];
    }

    /** These enrollments, as far as the user can see them, with the person each names. */
    public static List<Enrollment__c> selectEnrollments(Set<Id> enrollmentIds) {
        return [
            SELECT
                Id,
                Program__c,
                Stage__c,
                Cohort__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name
            FROM Enrollment__c
            WHERE Id IN :enrollmentIds
            WITH USER_MODE
        ];
    }

    /** The open enrollments in this program of these people that the user can see. */
    public static List<Enrollment__c> selectOpenFor(Id programId, Set<Id> personIds) {
        return [
            SELECT Id, Contact__c, Account__c, Cohort__c
            FROM Enrollment__c
            WHERE
                Program__c = :programId
                AND Stage__c IN :EnrollmentService.OPEN_STAGES
                AND (Contact__c IN :personIds
                OR Account__c IN :personIds)
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS LAST, Name
            LIMIT 2000
        ];
    }

    /** The names of these people (contacts or accounts) that the user can see. */
    public static Map<Id, String> selectPersonNames(Set<Id> personIds) {
        Map<Id, String> names = new Map<Id, String>();
        for (Contact person : [
            SELECT Id, Name
            FROM Contact
            WHERE Id IN :personIds
            WITH USER_MODE
        ]) {
            names.put(person.Id, person.Name);
        }
        for (Account person : [
            SELECT Id, Name
            FROM Account
            WHERE Id IN :personIds
            WITH USER_MODE
        ]) {
            names.put(person.Id, person.Name);
        }
        return names;
    }

    /** The program's active services, by name. */
    public static List<Service__c> selectActiveServices(Id programId) {
        return ServiceDeliverySelector.selectActiveServices(programId);
    }

    /**
     * The deliveries of this service on this day that name this session or no session, the
     * session's own first, oldest first, at most `howMany`.
     */
    public static List<Service_Delivery__c> selectSessionDeliveries(
        Session__c session,
        Integer howMany
    ) {
        return [
            SELECT
                Id,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name,
                Enrollment__c,
                Attendance__c,
                Quantity__c,
                Session__c
            FROM Service_Delivery__c
            WHERE
                Service__c = :session.Service__c
                AND Delivery_Date__c = :session.Session_Date__c
                AND (Session__c = :session.Id
                OR Session__c = NULL)
            WITH USER_MODE
            ORDER BY Session__c NULLS LAST, CreatedDate, Name
            LIMIT :howMany
        ];
    }
}
