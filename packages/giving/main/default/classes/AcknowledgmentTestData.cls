/**
 * Test data for the acknowledgment tests (feature G-12). The stand-in sender is Core's
 * `RecordingEmailSender` (ADR-0032).
 */
@IsTest
public class AcknowledgmentTestData {
    /** Turns the feature on and grants the send permission for the length of the test. */
    public static void enable() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Acknowledgments_Enabled__c = true;
        upsert settings;
        AcknowledgmentService.sendPermission = true;
    }

    /** A rule, ready to insert. Pass nulls for the criteria this rule does not care about. */
    public static Acknowledgment_Rule__c buildRule(
        String name,
        Integer order,
        String channel,
        String template
    ) {
        return new Acknowledgment_Rule__c(
            Name = name,
            Order__c = order,
            Channel__c = channel,
            Email_Template__c = template,
            Active__c = true,
            First_Gift_Only__c = false
        );
    }

    /** A contact with an email address, in their own household. */
    public static Contact insertDonor(String firstName, String lastName, String email) {
        Account household = new Account(Name = lastName + ' Household');
        insert household;
        Contact person = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = household.Id,
            Email = email
        );
        insert person;
        return person;
    }
}
