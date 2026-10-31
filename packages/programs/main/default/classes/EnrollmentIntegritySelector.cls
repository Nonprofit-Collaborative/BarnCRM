/**
 * The read the Programs rules make about what already exists in the org, whoever is saving
 * (R-EN2). ADR-0021 (system mode for package owned data).
 *
 * `without sharing` and `WITH SYSTEM_MODE`, because the answer is a fact about the org, not
 * about what the saving user may see: once participant privacy (P-08) makes enrollments private,
 * an open enrollment another staff member entered must still stop a second one for the same
 * person in the same program. What the user learns is limited to the refusal itself, naming only
 * the program they are saving against. No field of a hidden record is shown, and nothing reaches
 * a dynamic query.
 */
public without sharing class EnrollmentIntegritySelector {
    /**
     * The open enrollments (Applied or Enrolled) in these programs that name one of these people.
     */
    public static List<Enrollment__c> selectOpenFor(
        Set<Id> programIds,
        Set<Id> contactIds,
        Set<Id> accountIds
    ) {
        if (programIds == null || programIds.isEmpty()) {
            return new List<Enrollment__c>();
        }
        Set<String> openStages = EnrollmentService.OPEN_STAGES;
        return [
            SELECT Id, Program__c, Contact__c, Account__c
            FROM Enrollment__c
            WHERE
                Program__c IN :programIds
                AND Stage__c IN :openStages
                AND (Contact__c IN :contactIds
                OR Account__c IN :accountIds)
            WITH SYSTEM_MODE
        ];
    }
}
