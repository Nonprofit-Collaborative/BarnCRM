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

    /**
     * Puts a state and country on a standard address the way the org takes them: the codes
     * where State and Country Picklists are on (the text fields there take full names only),
     * the same codes as text otherwise.
     *
     * @param record the account or contact
     * @param prefix the address, such as `Billing` or `Mailing`
     * @param stateCode a state code, such as `IL`
     * @param countryCode a country code, such as `US`
     */
    public static void putStateAndCountry(
        SObject record,
        String prefix,
        String stateCode,
        String countryCode
    ) {
        String suffix = AddressService.usesStateAndCountryPicklists() ? 'Code' : '';
        record.put(prefix + 'Country' + suffix, countryCode);
        record.put(prefix + 'State' + suffix, stateCode);
    }

    /** An organization account, not yet inserted. */
    public static Account newOrganization(String name) {
        return new Account(Name = name, RecordTypeId = recordTypeId('Organization'));
    }

    /** A person in the given household, not yet inserted. */
    public static Contact newContact(String firstName, String lastName, Id accountId) {
        return new Contact(
            Salutation = 'Ms.',
            FirstName = firstName,
            LastName = lastName,
            AccountId = accountId
        );
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
