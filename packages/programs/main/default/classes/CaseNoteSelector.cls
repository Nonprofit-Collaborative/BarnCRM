/**
 * Reads case notes (canonical model 29Y1). Erasure (R-CN4) must find every note about a person,
 * whoever wrote it, so these reads run in system mode (ADR-0021); what is done with them runs as
 * the user.
 */
public without sharing class CaseNoteSelector {
    /** Every case note on any enrollment of this person (a contact or a person account). */
    public static List<Case_Note__c> selectAllAbout(Id personId) {
        return [
            SELECT Id
            FROM Case_Note__c
            WHERE Enrollment__r.Contact__c = :personId OR Enrollment__r.Account__c = :personId
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /** How many enrollments this person has, any stage, whoever can see them. */
    public static Integer countEnrollmentsOf(Id personId) {
        return [
            SELECT COUNT()
            FROM Enrollment__c
            WHERE Contact__c = :personId OR Account__c = :personId
            WITH SYSTEM_MODE
        ];
    }
}
