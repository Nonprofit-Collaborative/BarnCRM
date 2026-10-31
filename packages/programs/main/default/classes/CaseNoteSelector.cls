/**
 * Reads case notes (canonical model 29ZA1). Erasure (R-CN4) must find every note about a person,
 * whoever wrote it, so these reads run in system mode (ADR-0021); what is done with them runs as
 * the user.
 */
public without sharing class CaseNoteSelector {
    /**
     * Every case note on any enrollment of this person (a contact or a person account). For a
     * person account, enrollments made on its own contact count too: erasure only reaches an
     * account that is a person record (`PersonErasure`), so its contacts are that person.
     */
    public static List<Case_Note__c> selectAllAbout(Id personId) {
        Set<Id> contactIds = contactsOf(personId);
        return [
            SELECT Id
            FROM Case_Note__c
            WHERE Enrollment__r.Contact__c IN :contactIds OR Enrollment__r.Account__c = :personId
            WITH SYSTEM_MODE
            LIMIT 10000
        ];
    }

    /** How many enrollments this person has, any stage, whoever can see them. */
    public static Integer countEnrollmentsOf(Id personId) {
        Set<Id> contactIds = contactsOf(personId);
        return [
            SELECT COUNT()
            FROM Enrollment__c
            WHERE Contact__c IN :contactIds OR Account__c = :personId
            WITH SYSTEM_MODE
        ];
    }

    /**
     * The sample enrollments (a sample person in a sample program) that carry a case note,
     * whoever wrote it. System mode because notes are private to their authors: sample removal
     * must skip every such enrollment, not only those whose notes the remover can see, or the
     * note's lookup refuses the delete. Only enrollment ids leave this method.
     */
    public static Set<Id> sampleEnrollmentsWithNotes() {
        Set<Id> enrollmentIds = new Set<Id>();
        for (AggregateResult row : [
            SELECT Enrollment__c enrollment
            FROM Case_Note__c
            WHERE
                Enrollment__r.Program__r.Sample_Data__c = TRUE
                AND Enrollment__r.Contact__r.Sample_Data__c = TRUE
            WITH SYSTEM_MODE
            GROUP BY Enrollment__c
            LIMIT 2000
        ]) {
            enrollmentIds.add((Id) row.get('enrollment'));
        }
        return enrollmentIds;
    }

    /** The contact ids that are this person: itself, or a person account's own contact. */
    private static Set<Id> contactsOf(Id personId) {
        Set<Id> contactIds = new Set<Id>{ personId };
        if (personId != null && personId.getSObjectType() == Account.SObjectType) {
            for (Contact own : [
                SELECT Id
                FROM Contact
                WHERE AccountId = :personId
                WITH SYSTEM_MODE
                LIMIT 200
            ]) {
                contactIds.add(own.Id);
            }
        }
        return contactIds;
    }
}
