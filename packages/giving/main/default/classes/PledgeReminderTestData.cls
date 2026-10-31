/**
 * Test data for the pledge reminder tests (G-30). The stand-in sender is the acknowledgment
 * tests' own, because reminders send through the same `AcknowledgmentSender` seam.
 */
@IsTest
public class PledgeReminderTestData {
    /** The shipped template, which exists in every org the package is deployed to. */
    public static final String TEMPLATE = 'BarnCRM_Pledge_Reminder_Overdue';

    /** Turns the feature on and grants the send permission for the length of the test. */
    public static void enable() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Pledge_Reminders_Enabled__c = true;
        upsert settings;
        AcknowledgmentService.sendPermission = true;
    }

    public static Pledge_Reminder_Step__c buildStep(
        String name,
        Integer days,
        String channel,
        String template
    ) {
        return new Pledge_Reminder_Step__c(
            Name = name,
            Days_From_Due__c = days,
            Channel__c = channel,
            Email_Template__c = template,
            Active__c = true
        );
    }

    /**
     * An Active monthly pledge for a donor, starting `daysAgo` days ago, so its first
     * installment is due that long ago and the next one a month after it.
     */
    public static Commitment__c insertPledge(Id donorContactId, Integer daysAgo) {
        Date start = Date.today().addDays(-daysAgo);
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorContactId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = start,
            End_Date__c = start.addMonths(12).addDays(-1),
            Expected_Total__c = 1200,
            Installments_Planned__c = 12
        );
        insert pledge;
        return pledge;
    }

    /** The installment of a pledge due on `due`, with what a reminder reads. */
    public static Installment__c installmentDue(Id pledgeId, Date due) {
        return [
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
            WHERE Commitment__c = :pledgeId AND Due_Date__c = :due
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    /** An in-memory installment, due on a date, for a donor, never saved. */
    public static Installment__c inMemory(Date due, Id donorContactId) {
        return new Installment__c(
            Due_Date__c = due,
            Status__c = 'Scheduled',
            Expected_Amount__c = 100,
            Commitment__r = new Commitment__c(Donor_Contact__c = donorContactId)
        );
    }
}
