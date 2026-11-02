/**
 * Funders test data: a funder organization on whatever record type this org uses for
 * organizations (ADR-0141), and grants to it. Nothing is inserted here but the funder.
 */
@IsTest
public class GrantTestData {
    /** The admin set a Funders test runs with. */
    public static final String ADMIN = 'Funders_Admin';

    /** An inserted funder organization. */
    public static Account funder(String name) {
        Account organization = (Account) TestDataFactory.pastDuplicateRules(
            AccountKindsTestData.organization(name)
        );
        insert organization;
        return organization;
    }

    /** A grant to the funder at the stage, not inserted. */
    public static Grant__c grant(String name, Id funderId, String stage) {
        return new Grant__c(Name = name, Funder__c = funderId, Stage__c = stage);
    }

    /** An open requirement of the grant due on the date, not inserted. */
    public static Grant_Requirement__c requirement(String name, Id grantId, Date due) {
        return new Grant_Requirement__c(
            Name = name,
            Grant__c = grantId,
            Type__c = 'Narrative Report',
            Status__c = GrantRequirementService.STATUS_NOT_STARTED,
            Due_Date__c = due
        );
    }
}
