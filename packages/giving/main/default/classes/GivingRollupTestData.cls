/**
 * Shared setup for the giving rollup tests: the real-time tests and the engine regression suite.
 *
 * Everything here goes through the public rollup entry points (`RollupService` and ordinary
 * saves) and reads back plain field values, never the engine's own classes, so the tests built on
 * it keep their meaning when the engine behind `RollupService` is replaced (rollup proposal D1,
 * migration step 1).
 */
@IsTest
public class GivingRollupTestData {
    /** The Gift-sourced totals on a person, by definition key. */
    public static final String CONTACT_TOTAL = 'Contact_Total_Giving';
    public static final String CONTACT_COUNT = 'Contact_Gift_Count';
    public static final String CONTACT_LARGEST = 'Contact_Largest_Gift';
    public static final String CONTACT_FIRST_DATE = 'Contact_First_Gift_Date';
    public static final String CONTACT_LAST_DATE = 'Contact_Last_Gift_Date';
    public static final String CONTACT_THIS_YEAR = 'Contact_Giving_This_Year';
    public static final String CONTACT_LAST_YEAR = 'Contact_Giving_Last_Year';
    public static final String CONTACT_TWO_YEARS_AGO = 'Contact_Giving_Two_Years_Ago';
    public static final String CONTACT_GIFTS_LAST_YEAR = 'Contact_Gifts_Last_Year';

    /** The Gift-sourced totals on a household. */
    public static final String HOUSEHOLD_TOTAL = 'Household_Total_Giving';
    public static final String HOUSEHOLD_COUNT = 'Household_Gift_Count';
    public static final String HOUSEHOLD_LARGEST = 'Household_Largest_Gift';

    /** The Gift-sourced totals on an organization. */
    public static final String ACCOUNT_TOTAL = 'Account_Total_Giving';
    public static final String ACCOUNT_COUNT = 'Account_Gift_Count';

    /** Soft credit totals. */
    public static final String CONTACT_SOFT_TOTAL = 'Contact_Total_Soft_Credits';
    public static final String HOUSEHOLD_SOFT_TOTAL = 'Household_Total_Soft_Credits';
    public static final String HOUSEHOLD_SOFT_COUNT = 'Household_Soft_Credit_Count';

    /** Fund totals, sourced from Gift Allocation. */
    public static final String FUND_TOTAL = 'Fund_Total_Raised';
    public static final String FUND_COUNT = 'Fund_Gift_Count';

    /**
     * Creates the shipped rollups, as the Giving install does. From here on every save of a gift,
     * soft credit, allocation or commitment runs the real-time rollups.
     */
    public static void installShippedRollups() {
        RollupService.ensureDefaults();
    }

    /**
     * Marks the start of the next save, as a separate transaction would in an org.
     *
     * The trigger framework runs a handler once per record per transaction, so a rollup that
     * causes its own record to be saved again does not run twice. A test method is one
     * transaction, so a test that saves the same record twice, as a person would in two separate
     * edits, clears that memory between the saves.
     */
    public static void nextSave() {
        TriggerHandler.clearRunClaims();
    }

    /** The materialized definitions for these shipped keys, failing when any is missing. */
    public static List<Rollup_Definition__c> definitions(Set<String> keys) {
        List<Rollup_Definition__c> found = [
            SELECT
                Id,
                Name,
                Definition_Key__c,
                Source_Object__c,
                Target_Object__c,
                Relationship_Path__c,
                Aggregate__c,
                Source_Field__c,
                Order_By_Field__c,
                Target_Field__c,
                Filter_JSON__c,
                Target_Filter_JSON__c,
                Fiscal_Year_Aware__c,
                Fiscal_Year_Offset__c,
                Fiscal_Date_Field__c,
                Mode__c,
                Active__c,
                Last_Calculated__c
            FROM Rollup_Definition__c
            WHERE Definition_Key__c IN :keys
        ];
        Assert.areEqual(
            keys.size(),
            found.size(),
            'The shipped rollups under test have to be installed before they can run.'
        );
        return found;
    }

    /**
     * The nightly recalculation, limited to these shipped keys. Callers wrap it in
     * `Test.startTest` and `Test.stopTest` so that work the engine queues has finished before
     * anything is asserted.
     */
    public static void recalculate(Set<String> keys) {
        RollupService.runFullRecalculation(definitions(keys));
    }

    /**
     * One person in a household of their own for each name, inserted in two saves however many
     * there are. Returns the people, each with AccountId set to their household.
     */
    public static List<Contact> peopleInOwnHouseholds(List<String> lastNames) {
        Id householdType = HouseholdService.householdRecordTypeId();
        List<Account> households = new List<Account>();
        for (String lastName : lastNames) {
            households.add(
                new Account(Name = 'The ' + lastName + ' Family', RecordTypeId = householdType)
            );
        }
        insert households;
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < lastNames.size(); i++) {
            people.add(
                new Contact(
                    FirstName = 'Test',
                    LastName = lastNames[i],
                    AccountId = households[i].Id
                )
            );
        }
        insert people;
        return people;
    }

    /** A person's giving totals as they are stored now. */
    public static Contact person(Id contactId) {
        return [
            SELECT
                Id,
                AccountId,
                Total_Giving__c,
                Gift_Count__c,
                Largest_Gift__c,
                First_Gift_Date__c,
                Last_Gift_Date__c,
                Giving_This_Year__c,
                Giving_Last_Year__c,
                Giving_Two_Years_Ago__c,
                Gifts_Last_Year__c,
                Total_Soft_Credits__c,
                Soft_Credit_Count__c,
                Pledge_Balance__c,
                Rollups_Last_Calculated__c
            FROM Contact
            WHERE Id = :contactId
        ];
    }

    /** A household's or an organization's giving totals as they are stored now. */
    public static Account account(Id accountId) {
        return [
            SELECT
                Id,
                Total_Giving__c,
                Gift_Count__c,
                Largest_Gift__c,
                Total_Soft_Credits__c,
                Soft_Credit_Count__c,
                Pledge_Balance__c,
                Rollups_Last_Calculated__c
            FROM Account
            WHERE Id = :accountId
        ];
    }

    /** A fund's totals as they are stored now. */
    public static Fund__c fund(Id fundId) {
        return [
            SELECT Id, Total_Raised__c, Gift_Count__c, Rollups_Last_Calculated__c
            FROM Fund__c
            WHERE Id = :fundId
        ];
    }

    /** A blank total counts as zero, so a sum or a count can be compared without a null check. */
    public static Decimal valueOf(Object total) {
        return total == null ? 0 : (Decimal) total;
    }
}
