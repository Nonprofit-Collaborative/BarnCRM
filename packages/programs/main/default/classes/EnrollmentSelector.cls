/**
 * The reads the Programs module makes for the person using it, in user mode: what they may see
 * of a program and its enrollments.
 */
public with sharing class EnrollmentSelector {
    /** The names of these programs. A program the user cannot see is absent. */
    public static Map<Id, String> selectProgramNames(Set<Id> programIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (programIds == null || programIds.isEmpty()) {
            return names;
        }
        for (Program__c program : [
            SELECT Id, Name
            FROM Program__c
            WHERE Id IN :programIds
            WITH USER_MODE
        ]) {
            names.put(program.Id, program.Name);
        }
        return names;
    }

    /** The program an enrollment is in, or null when the user cannot see the enrollment. */
    public static Id selectProgramIdOf(Id enrollmentId) {
        List<Enrollment__c> found = [
            SELECT Program__c
            FROM Enrollment__c
            WHERE Id = :enrollmentId
            WITH USER_MODE
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0].Program__c;
    }

    /**
     * The enrollments naming these contacts or this account, newest start first, at most
     * `howMany`, with their program's name.
     */
    public static List<Enrollment__c> selectForPerson(
        Set<Id> contactIds,
        Id accountId,
        Integer howMany
    ) {
        return [
            SELECT Id, Program__c, Program__r.Name, Stage__c, Start_Date__c, End_Date__c
            FROM Enrollment__c
            WHERE Contact__c IN :contactIds OR (Account__c != NULL AND Account__c = :accountId)
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS FIRST, Name DESC
            LIMIT :howMany
        ];
    }

    /** The contacts of this account: for a person account, its one contact. */
    public static Set<Id> selectContactIdsOf(Id accountId) {
        return new Map<Id, Contact>(
                [SELECT Id FROM Contact WHERE AccountId = :accountId WITH USER_MODE LIMIT 2]
            )
            .keySet();
    }

    /** How many of the program's enrollments the user can see are at each stage. */
    public static Map<String, Integer> countByStage(Id programId) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AggregateResult row : [
            SELECT Stage__c stage, COUNT(Id) total
            FROM Enrollment__c
            WHERE Program__c = :programId
            WITH USER_MODE
            GROUP BY Stage__c
        ]) {
            counts.put((String) row.get('stage'), (Integer) row.get('total'));
        }
        return counts;
    }

    /**
     * The program's enrollments at these stages, newest start first, at most `howMany`, with the
     * name of the person each names.
     */
    public static List<Enrollment__c> selectRoster(
        Id programId,
        Set<String> stages,
        Integer howMany
    ) {
        if (stages == null || stages.isEmpty()) {
            return new List<Enrollment__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Stage__c,
                Start_Date__c,
                End_Date__c,
                Contact__c,
                Contact__r.Name,
                Account__c,
                Account__r.Name
            FROM Enrollment__c
            WHERE Program__c = :programId AND Stage__c IN :stages
            WITH USER_MODE
            ORDER BY Start_Date__c DESC NULLS LAST, Name
            LIMIT :howMany
        ];
    }
}
