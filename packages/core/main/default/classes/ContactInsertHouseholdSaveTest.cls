/**
 * A person added without a household (contact mode) gets a new household named for them,
 * with them as its Primary Contact (R-H2, PEOPLE-27), and, when they were saved with a mailing
 * address, that address as the household's primary address and billing address (R-AD3, R-AD5).
 * The household is saved once for both when it can be (D-143): these tests pin the outcome on
 * every path, including the ones where it cannot.
 */
@IsTest(testFor='ApexClass:HouseholdService, ApexClass:AddressService, ApexClass:TriggerDispatcher')
private class ContactInsertHouseholdSaveTest {
    private static final String STREET = '6830 Sunset Lane';
    private static final String CITY = 'Springfield';

    @TestSetup
    static void createTestUser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestUsers.admin();
        }
    }

    @IsTest
    static void twoHundredPeopleWithAnAddressEachGetANamedAddressedHousehold() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = people(200, true);

            Test.startTest();
            insert people;
            Test.stopTest();

            assertSeededAndAddressed(people, true);
        }
    }

    @IsTest
    static void twoHundredPeopleWithoutAnAddressEachAreTheirHouseholdsPrimaryContact() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = people(200, false);

            Test.startTest();
            insert people;
            Test.stopTest();

            assertSeededAndAddressed(people, false);
        }
    }

    @IsTest
    static void withAddressCaptureSwitchedOffThePrimaryContactIsStillSet() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = people(5, true);

            Test.startTest();
            AutomationControl.bypass('Contact_Address_Capture');
            insert people;
            AutomationControl.clearBypass('Contact_Address_Capture');
            Test.stopTest();

            for (Account household : householdsOf(people).values()) {
                Assert.isNotNull(household.Primary_Contact__c, 'The person is still primary.');
                Assert.isNull(household.BillingStreet, 'Nothing captured the address.');
            }
        }
    }

    /**
     * Someone who may add people but may not edit Primary Contact (a profile or permission
     * set without it) still gets their new household's Primary Contact set: it is the
     * package's own bookkeeping (ADR-0021). Their address still reaches the household.
     */
    @IsTest
    static void someoneWhoMayNotEditPrimaryContactStillGetsItSet() {
        User pat;
        System.runAs(TestUsers.admin()) {
            pat = TestDataFactory.createUser('Pat', new List<String>{ 'BarnCRM_Staff' });
        }
        withoutPrimaryContactAccess('BarnCRM_Staff');
        List<Contact> people = people(3, true);

        Test.startTest();
        Boolean canEdit;
        System.runAs(pat) {
            canEdit = Schema.SObjectType.Account.fields.Primary_Contact__c.isUpdateable();
            insert people;
        }
        Test.stopTest();

        Assert.isFalse(canEdit, 'Pat may not edit Primary Contact: the case under test.');
        System.runAs(TestUsers.admin()) {
            assertSeededAndAddressed(people, true);
        }
    }

    @IsTest
    static void aPersonJoiningAnExistingHouseholdLeavesItsPrimaryContactAlone() {
        System.runAs(TestUsers.admin()) {
            Account smiths = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert smiths;
            Contact jane = HouseholdTestDataFactory.newContact('Jane', 'Smith');
            jane.AccountId = smiths.Id;
            insert jane;
            Id before = [SELECT Primary_Contact__c FROM Account WHERE Id = :smiths.Id]
            .Primary_Contact__c;
            Contact john = HouseholdTestDataFactory.newContact('John', 'Smith');
            john.AccountId = smiths.Id;
            john.MailingStreet = STREET;
            john.MailingCity = CITY;

            Test.startTest();
            insert john;
            Test.stopTest();

            Account after = [
                SELECT Primary_Contact__c, BillingStreet
                FROM Account
                WHERE Id = :smiths.Id
            ];
            Assert.areEqual(before, after.Primary_Contact__c, 'Primary Contact is unchanged.');
            Assert.areEqual(STREET, after.BillingStreet, 'The household took the address.');
        }
    }

    // ------------------------------------------------------------ helpers

    private static List<Contact> people(Integer count, Boolean withAddress) {
        List<Contact> people = new List<Contact>();
        for (Integer index = 0; index < count; index++) {
            Contact person = HouseholdTestDataFactory.newContact('Pat', 'Saveonce' + index);
            if (withAddress) {
                person.MailingStreet = index + ' ' + STREET;
                person.MailingCity = CITY;
            }
            people.add(person);
        }
        return people;
    }

    private static Map<Id, Account> householdsOf(List<Contact> people) {
        Set<Id> householdIds = new Set<Id>();
        for (Contact person : [
            SELECT AccountId
            FROM Contact
            WHERE Id IN :new Map<Id, Contact>(people).keySet()
            WITH SYSTEM_MODE
        ]) {
            householdIds.add(person.AccountId);
        }
        return new Map<Id, Account>(
            [
                SELECT Id, Name, Primary_Contact__c, BillingStreet, BillingCity
                FROM Account
                WHERE Id IN :householdIds
                WITH SYSTEM_MODE
            ]
        );
    }

    private static void assertSeededAndAddressed(List<Contact> people, Boolean withAddress) {
        Map<Id, Contact> saved = new Map<Id, Contact>(
            [
                SELECT Id, AccountId, LastName, MailingStreet
                FROM Contact
                WHERE Id IN :new Map<Id, Contact>(people).keySet()
                WITH SYSTEM_MODE
            ]
        );
        Map<Id, Account> households = householdsOf(people);
        Assert.areEqual(people.size(), households.size(), 'One household each.');
        Map<Id, Address__c> addressByHousehold = new Map<Id, Address__c>();
        for (Address__c address : [
            SELECT Account__c, Street__c, Is_Default__c
            FROM Address__c
            WHERE Account__c IN :households.keySet()
            WITH SYSTEM_MODE
        ]) {
            addressByHousehold.put(address.Account__c, address);
        }
        for (Contact person : saved.values()) {
            Account household = households.get(person.AccountId);
            Assert.areEqual(person.Id, household.Primary_Contact__c, 'They are its primary.');
            Assert.isTrue(household.Name.contains(person.LastName), 'Named for them.');
            Address__c address = addressByHousehold.get(household.Id);
            if (withAddress) {
                Assert.areEqual(person.MailingStreet, household.BillingStreet, 'Billing set.');
                Assert.areEqual(CITY, household.BillingCity, 'Billing city set.');
                Assert.isNotNull(address, 'The household has the address as a record.');
                Assert.isTrue(address.Is_Default__c, 'It is the primary address.');
            } else {
                Assert.isNull(household.BillingStreet, 'No billing address.');
                Assert.isNull(address, 'No address record.');
            }
        }
    }

    /**
     * Takes Primary Contact out of a permission set, for this test only (a test's setup changes
     * are rolled back). Written in its own context, apart from the records the test saves.
     */
    private static void withoutPrimaryContactAccess(String permissionSetName) {
        String field = 'Account.' + Account.Primary_Contact__c.getDescribe().getName();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            delete [
                SELECT Id
                FROM FieldPermissions
                WHERE Parent.Name = :permissionSetName AND Field = :field
            ];
        }
    }
}
