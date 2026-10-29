/**
 * A person account's mailing address is kept as an address record of their own, on insert and
 * on update (PEOPLE-17, R-AD5). Contact triggers do not fire for person account saves, so the
 * Account handler does it.
 *
 * The person tests need an org with person accounts and return early, on purpose, where the
 * org has none: the Platform-only shape Core must also run on (ADR-0013) has no person fields.
 * In an org that has person accounts but gives the running user no person record type, they
 * fail instead, so that person account coverage cannot quietly not run. The person fields are
 * named only as text and written with put, so this class compiles on that shape too. The
 * last two tests run in every shape.
 */
@IsTest(
    testFor='ApexClass:AccountAddressHandler, ApexClass:AccountTriggerHandler, ApexTrigger:AccountTrigger'
)
private class AccountPersonAddressCaptureTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Account person(String lastName, String street) {
        Account record = new Account(RecordTypeId = OrgShapeDetector.creatablePersonRecordTypeId());
        record.put('FirstName', 'Pat');
        record.put('LastName', lastName);
        if (street != null) {
            record.put('PersonMailingStreet', street);
            record.put('PersonMailingCity', 'Portland');
            record.put('PersonMailingState', 'OR');
            record.put('PersonMailingPostalCode', '97201');
            record.put('PersonMailingCountry', 'United States');
        }
        return record;
    }

    /** The household automations stand down, so the tests are about addresses only. */
    private static void quietHouseholds() {
        AutomationControl.bypass('AccountTriggerHandler');
        AutomationControl.bypass('ContactTriggerHandler');
    }

    private static List<Address__c> addressesOf(Set<Id> personIds) {
        return [
            SELECT Id, Person_Account__c, Type__c, Is_Default__c, Street__c, City__c, Postal_Code__c
            FROM Address__c
            WHERE Person_Account__c IN :personIds
            WITH SYSTEM_MODE
            ORDER BY CreatedDate, Id
        ];
    }

    @IsTest
    static void aPersonAccountSavedWithAMailingAddressGetsADefaultAddressOfTheirOwn() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            quietHouseholds();
            Account pat = person('Alder', '12 Alder Street');

            Test.startTest();
            insert pat;
            Test.stopTest();

            List<Address__c> addresses = addressesOf(new Set<Id>{ pat.Id });
            Assert.areEqual(1, addresses.size(), 'One address record for the person.');
            Assert.areEqual('12 Alder Street', addresses[0].Street__c, 'With what was typed.');
            Assert.areEqual('Portland', addresses[0].City__c, 'All of it.');
            Assert.isTrue(addresses[0].Is_Default__c, 'It is the default.');
            Assert.areEqual('Home', addresses[0].Type__c, 'A home address.');
        }
    }

    @IsTest
    static void aPersonAccountSavedWithNoMailingAddressGetsNoAddressRecord() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            quietHouseholds();
            Account pat = person('Alder', null);

            Test.startTest();
            insert pat;
            Test.stopTest();

            Assert.isTrue(addressesOf(new Set<Id>{ pat.Id }).isEmpty(), 'Nothing was typed.');
        }
    }

    @IsTest
    static void changingAPersonAccountsMailingAddressAddsANewDefaultAndKeepsTheOldOne() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            quietHouseholds();
            Account pat = person('Alder', '12 Alder Street');
            insert pat;

            Account moved = new Account(Id = pat.Id);
            moved.put('PersonMailingStreet', '9 Birch Road');
            Test.startTest();
            update moved;
            Test.stopTest();

            List<Address__c> addresses = addressesOf(new Set<Id>{ pat.Id });
            Assert.areEqual(2, addresses.size(), 'The old address stays on file (R-AD7).');
            Integer defaults = 0;
            for (Address__c address : addresses) {
                if (address.Is_Default__c) {
                    defaults++;
                    Assert.areEqual(
                        '9 Birch Road',
                        address.Street__c,
                        'The new one is the default.'
                    );
                }
            }
            Assert.areEqual(1, defaults, 'Only one is the default (R-AD2).');
        }
    }

    @IsTest
    static void savingAPersonAccountWithTheSameMailingAddressAddsNothing() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            quietHouseholds();
            Account pat = person('Alder', '12 Alder Street');
            insert pat;

            Account renamed = new Account(Id = pat.Id);
            renamed.put('FirstName', 'Patricia');
            Test.startTest();
            update renamed;
            Test.stopTest();

            Assert.areEqual(
                1,
                addressesOf(new Set<Id>{ pat.Id }).size(),
                'The address did not change, so no record was added.'
            );
        }
    }

    @IsTest
    static void twoHundredPersonAccountsAreCapturedOnInsertAndOnUpdate() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                return;
            }
            quietHouseholds();
            List<Account> people = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                people.add(person('Bulk' + i, i + ' Alder Street'));
            }

            Test.startTest();
            insert people;
            Test.stopTest();

            Set<Id> ids = new Map<Id, Account>(people).keySet();
            Assert.areEqual(200, addressesOf(ids).size(), 'Each person has one address.');

            List<Account> moved = new List<Account>();
            for (Account pat : people) {
                Account change = new Account(Id = pat.Id);
                change.put('PersonMailingStreet', 'New ' + pat.get('LastName'));
                moved.add(change);
            }
            update moved;

            Assert.areEqual(400, addressesOf(ids).size(), 'Each move added one more.');
            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Person_Account__c IN :ids AND Is_Default__c = TRUE
                ],
                'And each person has exactly one default.'
            );
        }
    }

    @IsTest
    static void aHouseholdBillingAddressIsCapturedOnInsertAndWhenItChanges() {
        System.runAs(TestUsers.admin()) {
            quietHouseholds();
            Account household = HouseholdTestDataFactory.newHousehold('The Alder Family');
            household.BillingStreet = '12 Alder Street';
            Database.insert(household, AccessLevel.SYSTEM_MODE);
            Integer afterInsert = [SELECT COUNT() FROM Address__c WHERE Account__c = :household.Id];

            update new Account(Id = household.Id, BillingStreet = '9 Birch Road');

            Assert.areEqual(1, afterInsert, 'Captured on insert, as before.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :household.Id],
                'A changed household billing address is captured as a new address.'
            );
        }
    }

    @IsTest
    static void thePersonCaptureDoesNothingAndRunsNoQueryWhereTheOrgHasNoPersonAccounts() {
        System.runAs(TestUsers.admin()) {
            if (OrgShapeDetector.detect().hasPersonAccounts) {
                return;
            }
            Account organization = new Account(Name = 'Acme Foundation');
            insert organization;

            Integer queriesBefore = Limits.getQueries();
            AddressService.capturePersonMailingChanges(
                new List<Account>{ organization },
                new Map<Id, SObject>{ organization.Id => new Account(Id = organization.Id) }
            );

            Assert.areEqual(queriesBefore, Limits.getQueries(), 'No query was run.');
            Assert.areEqual(0, [SELECT COUNT() FROM Address__c], 'And nothing was captured.');
        }
    }
}
