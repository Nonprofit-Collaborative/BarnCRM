/**
 * The donors the ask reminder pass walks (canonical model Section 25O).
 *
 * Both queries run in system mode: a reminder that silently skipped a donor because the user the
 * job happens to run as cannot see the record would be a follow-up that never happened, which is
 * the one failure this feature exists to prevent. Nothing read here leaves the job.
 *
 * A donor is in scope when its Next Ask Date is inside the catch up window (R-AC4). Whether the
 * donor has already been reminded for that date compares two fields of the same record, which
 * SOQL cannot do, so the service makes that test on the rows this returns.
 */
public with sharing class AskReminderSelector {
    /** The people whose Next Ask Date has arrived and is not stale. */
    public static Database.QueryLocator contactLocator(Date earliest, Date latest) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    AccountId,
                    OwnerId,
                    Next_Ask_Date__c,
                    Ask_Reminder_For_Date__c
                FROM Contact
                WHERE Next_Ask_Date__c >= :earliest AND Next_Ask_Date__c <= :latest
                WITH SYSTEM_MODE
            ]
        );
    }

    /** The organizations and households, on the same terms as the people. */
    public static Database.QueryLocator accountLocator(Date earliest, Date latest) {
        return Database.getQueryLocator(
            [
                SELECT Id, Name, OwnerId, Next_Ask_Date__c, Ask_Reminder_For_Date__c
                FROM Account
                WHERE Next_Ask_Date__c >= :earliest AND Next_Ask_Date__c <= :latest
                WITH SYSTEM_MODE
            ]
        );
    }
}
