/**
 * Test data for the relationship and affiliation tests. Kept apart from the shared
 * TestDataFactory so that C-15 and C-16 add helpers without touching a file every other
 * feature also edits (plan Section 9.2).
 *
 * The person account paths are exercised without a person account org, and that is sound
 * rather than a shortcut. Nothing in either feature reads a person account field: the account
 * side of a person reference is a plain lookup to Account, and every rule in these two
 * features works on the id in it. So an ordinary account standing in the Person Account
 * lookup exercises exactly the code a real person account would, which is the point of
 * holding the reference as a pair in the first place (canonical model Section 4).
 *
 * The one thing this cannot prove is that a real person account org behaves the same, because
 * no org exists in this environment to prove it in. That is recorded in the feature's
 * integration notes.
 */
@IsTest
@NamespaceAccessible
public class RelationshipTestDataFactory {
    private static final String CONTACT_HANDLER = 'ContactTriggerHandler';
    private static final String ACCOUNT_HANDLER = 'AccountTriggerHandler';
    private static final String CONTACT_ADDRESS_HANDLER = 'Contact_Address_Capture';
    private static final String ACCOUNT_ADDRESS_HANDLER = 'Account_Address_Capture';

    /**
     * Stands the household and address automations down for the whole test. These features
     * never change a household or an address, so the tests are about relationships and
     * affiliations only, and setup stays cheap.
     */
    @NamespaceAccessible
    public static void quietOtherAutomations() {
        AutomationControl.bypass(CONTACT_HANDLER);
        AutomationControl.bypass(ACCOUNT_HANDLER);
        AutomationControl.bypass(CONTACT_ADDRESS_HANDLER);
        AutomationControl.bypass(ACCOUNT_ADDRESS_HANDLER);
    }

    /** People held as contacts, inserted. */
    public static List<Contact> contacts(Integer howMany, String lastName) {
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            people.add(new Contact(FirstName = 'Person' + i, LastName = lastName));
        }
        insert people;
        return people;
    }

    /**
     * People held as accounts, inserted. Ordinary accounts: see the class comment for why that
     * exercises the same code a person account would.
     */
    public static List<Account> peopleAsAccounts(Integer howMany, String lastName) {
        List<Account> people = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            people.add(new Account(Name = 'Person' + i + ' ' + lastName));
        }
        insert people;
        return people;
    }

    /** Organizations, inserted. */
    public static List<Account> organizations(Integer howMany, String prefix) {
        List<Account> orgs = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            orgs.add(
                new Account(Name = prefix + ' ' + i, RecordTypeId = organizationRecordTypeId())
            );
        }
        insert orgs;
        return orgs;
    }

    /** A relationship between two people held as contacts, not yet inserted. */
    public static Relationship__c between(Contact person, Contact other, String type) {
        return new Relationship__c(
            Contact__c = person.Id,
            Related_Contact__c = other.Id,
            Type__c = type,
            Status__c = 'Current',
            Is_Reciprocal_Managed__c = true
        );
    }

    /** A relationship between two people held as accounts, not yet inserted. */
    public static Relationship__c between(Account person, Account other, String type) {
        return new Relationship__c(
            Person_Account__c = person.Id,
            Related_Person_Account__c = other.Id,
            Type__c = type,
            Status__c = 'Current',
            Is_Reciprocal_Managed__c = true
        );
    }

    /** A relationship from a person held as a contact to one held as an account. */
    public static Relationship__c between(Contact person, Account other, String type) {
        return new Relationship__c(
            Contact__c = person.Id,
            Related_Person_Account__c = other.Id,
            Type__c = type,
            Status__c = 'Current',
            Is_Reciprocal_Managed__c = true
        );
    }

    /** An affiliation from a person held as a contact, not yet inserted. */
    public static Affiliation__c affiliation(Contact person, Account organization, String role) {
        return new Affiliation__c(
            Contact__c = person.Id,
            Organization__c = organization.Id,
            Role__c = role,
            Status__c = 'Current'
        );
    }

    /** An affiliation from a person held as an account, not yet inserted. */
    public static Affiliation__c affiliation(Account person, Account organization, String role) {
        return new Affiliation__c(
            Person_Account__c = person.Id,
            Organization__c = organization.Id,
            Role__c = role,
            Status__c = 'Current'
        );
    }

    /**
     * Every relationship on file, read in system mode so a test sees the records the package
     * wrote as well as the ones it wrote itself.
     */
    public static List<Relationship__c> allRelationships() {
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Person_Account__c,
                Related_Contact__c,
                Related_Person_Account__c,
                Type__c,
                Reciprocal_Type__c,
                Status__c,
                Start_Date__c,
                End_Date__c,
                Description__c,
                Reciprocal_Relationship__c,
                Is_Reciprocal_Managed__c
            FROM Relationship__c
            ORDER BY Name
            LIMIT 5000
        ];
    }

    /** Every affiliation on file, read the same way. */
    public static List<Affiliation__c> allAffiliations() {
        return [
            SELECT
                Id,
                Name,
                Contact__c,
                Person_Account__c,
                Organization__c,
                Role__c,
                Status__c,
                Is_Primary__c,
                Start_Date__c,
                End_Date__c
            FROM Affiliation__c
            ORDER BY Name
            LIMIT 5000
        ];
    }

    private static Id organizationRecordTypeId() {
        Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosByDeveloperName()
            .get('Organization');
        return info == null ? null : info.getRecordTypeId();
    }
}
