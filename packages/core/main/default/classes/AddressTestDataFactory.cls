/**
 * Test data for the address tests. Kept apart from the shared TestDataFactory so that C-17
 * adds helpers without touching a file every other feature also edits (plan Section 9.2).
 */
@IsTest
public class AddressTestDataFactory {
    /** A household account, not yet inserted, named the way the naming service expects. */
    public static Account newHousehold(String name) {
        return HouseholdTestDataFactory.newHousehold(name);
    }

    /** An organization account, not yet inserted. */
    public static Account newOrganization(String name) {
        return (Account) TestDataFactory.pastDuplicateRules(
            new Account(Name = name, RecordTypeId = recordTypeId('Organization'))
        );
    }

    /** A person in the given household, not yet inserted. */
    public static Contact newContact(String firstName, String lastName, Id accountId) {
        Contact person = HouseholdTestDataFactory.newContact('Ms.', firstName, lastName);
        person.AccountId = accountId;
        return person;
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null ? null : info.getRecordTypeId();
    }
}
