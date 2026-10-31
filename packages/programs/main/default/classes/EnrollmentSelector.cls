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
}
