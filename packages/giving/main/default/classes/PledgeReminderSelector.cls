/**
 * Every read the pledge reminder feature makes (G-30, canonical model 25P and 25Q).
 *
 * All in user mode, so what a person sees on the page is what their sharing lets them see. The
 * nightly run reads as the user who scheduled it, the same as the acknowledgment send.
 */
public with sharing class PledgeReminderSelector {
    /** The most installments the page counts or a letter file carries. */
    public static final Integer QUEUE_LIMIT = 2000;

    /** The installment statuses that still owe money (R-DM2). */
    private static final Set<String> OPEN_STATUSES = new Set<String>{
        'Scheduled',
        'Overdue',
        'Partially paid'
    };

    /** Steps that fire, soonest first. */
    public static List<Pledge_Reminder_Step__c> activeSteps() {
        return [
            SELECT Id, Name, Days_From_Due__c, Channel__c, Email_Template__c, Active__c
            FROM Pledge_Reminder_Step__c
            WHERE Active__c = TRUE
            WITH USER_MODE
            ORDER BY Days_From_Due__c ASC, Name ASC
            LIMIT 200
        ];
    }

    /** Every step, active or not, for the page. */
    public static List<Pledge_Reminder_Step__c> allSteps() {
        return [
            SELECT Id, Name, Days_From_Due__c, Channel__c, Email_Template__c, Active__c
            FROM Pledge_Reminder_Step__c
            WITH USER_MODE
            ORDER BY Days_From_Due__c ASC, Name ASC
            LIMIT 200
        ];
    }

    /** The email templates this org has, by label and developer name. */
    public static List<EmailTemplate> activeTemplates() {
        return AcknowledgmentSelector.activeTemplates();
    }

    /**
     * The installments still owed, on an Active pledge, due between the two dates, with what a
     * reminder needs to address the donor. A pledge that is Paused, Completed or Cancelled is
     * never reminded about.
     */
    public static Database.QueryLocator openInstallmentsLocator(Date fromDate, Date toDate) {
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Name,
                    Sequence__c,
                    Due_Date__c,
                    Expected_Amount__c,
                    Paid_Amount__c,
                    Status__c,
                    Commitment__c,
                    Commitment__r.Name,
                    Commitment__r.Donor_Contact__c,
                    Commitment__r.Donor_Account__c,
                    Commitment__r.Donor_Account__r.Primary_Contact__c
                FROM Installment__c
                WHERE
                    Status__c IN :OPEN_STATUSES
                    AND Commitment__r.Status__c = 'Active'
                    AND Due_Date__c >= :fromDate
                    AND Due_Date__c <= :toDate
                WITH USER_MODE
                ORDER BY Due_Date__c ASC, Id ASC
            ]
        );
    }

    /** The same installments as a list, capped, for the page's "due next run" counts. */
    public static List<Installment__c> openInstallments(
        Date fromDate,
        Date toDate,
        Integer maximum
    ) {
        List<Installment__c> found = new List<Installment__c>();
        for (Installment__c installment : [
            SELECT
                Id,
                Name,
                Sequence__c,
                Due_Date__c,
                Expected_Amount__c,
                Paid_Amount__c,
                Status__c,
                Commitment__c,
                Commitment__r.Name,
                Commitment__r.Donor_Contact__c,
                Commitment__r.Donor_Account__c,
                Commitment__r.Donor_Account__r.Primary_Contact__c
            FROM Installment__c
            WHERE
                Status__c IN :OPEN_STATUSES
                AND Commitment__r.Status__c = 'Active'
                AND Due_Date__c >= :fromDate
                AND Due_Date__c <= :toDate
            WITH USER_MODE
            ORDER BY Due_Date__c ASC, Id ASC
            LIMIT :maximum
        ]) {
            found.add(installment);
        }
        return found;
    }

    /** The contacts a message can be addressed to, by contact id. */
    public static Map<Id, Contact> contactsById(Set<Id> contactIds) {
        return AcknowledgmentSelector.contactsById(contactIds);
    }

    /**
     * Which of these contacts cannot be emailed: Email Opt Out set, no email address, or an
     * address that bounced. Ids only, read in system mode for the reason
     * `AcknowledgmentSelector.optedOutOfEmail` gives: the answer only moves a reminder to the
     * letter channel and never reaches the person running the job.
     */
    public static Set<Id> cannotBeEmailed(Set<Id> contactIds) {
        Set<Id> blocked = new Set<Id>();
        if (contactIds == null || contactIds.isEmpty()) {
            return blocked;
        }
        for (Contact person : [
            SELECT Id
            FROM Contact
            WHERE
                Id IN :contactIds
                AND (HasOptedOutOfEmail = TRUE
                OR Email = NULL
                OR IsEmailBounced = TRUE)
            WITH SYSTEM_MODE
        ]) {
            blocked.add(person.Id);
        }
        return blocked;
    }

    /** Letters waiting for a file: queued, with no file yet, oldest first. */
    public static List<Pledge_Reminder__c> lettersWithoutFile(Integer maximum) {
        return [
            SELECT
                Id,
                Step_Name__c,
                Days_Overdue__c,
                Installment__r.Due_Date__c,
                Installment__r.Expected_Amount__c,
                Installment__r.Paid_Amount__c,
                Installment__r.Sequence__c,
                Commitment__r.Name,
                Commitment__r.Donor_Contact__r.Name,
                Commitment__r.Donor_Contact__r.FirstName,
                Commitment__r.Donor_Contact__r.MailingStreet,
                Commitment__r.Donor_Contact__r.MailingCity,
                Commitment__r.Donor_Contact__r.MailingState,
                Commitment__r.Donor_Contact__r.MailingPostalCode,
                Commitment__r.Donor_Contact__r.MailingCountry,
                Commitment__r.Donor_Account__r.Name,
                Commitment__r.Donor_Account__r.Household_Informal_Greeting__c,
                Commitment__r.Donor_Account__r.BillingStreet,
                Commitment__r.Donor_Account__r.BillingCity,
                Commitment__r.Donor_Account__r.BillingState,
                Commitment__r.Donor_Account__r.BillingPostalCode,
                Commitment__r.Donor_Account__r.BillingCountry
            FROM Pledge_Reminder__c
            WHERE
                Channel__c = 'Letter'
                AND Status__c = 'Queued'
                AND Letter_File_Document_Id__c = NULL
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT :maximum
        ];
    }

    /** Letters in a file that a person has not yet said were posted. */
    public static List<Pledge_Reminder__c> lettersAwaitingConfirmation() {
        return [
            SELECT Id, Status__c, Letter_File_Document_Id__c
            FROM Pledge_Reminder__c
            WHERE
                Channel__c = 'Letter'
                AND Status__c = 'Queued'
                AND Letter_File_Document_Id__c != NULL
            WITH USER_MODE
            ORDER BY CreatedDate ASC, Id ASC
            LIMIT 10000
        ];
    }

    /** The newest reminders, for the log on the page. */
    public static List<Pledge_Reminder__c> recent(Integer howMany) {
        return [
            SELECT
                Id,
                Name,
                Step_Name__c,
                Channel__c,
                Status__c,
                Sent_On__c,
                Failure_Reason__c,
                Letter_File_Document_Id__c,
                Installment__c,
                Installment__r.Name,
                Commitment__c,
                Commitment__r.Name
            FROM Pledge_Reminder__c
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :howMany
        ];
    }
}
