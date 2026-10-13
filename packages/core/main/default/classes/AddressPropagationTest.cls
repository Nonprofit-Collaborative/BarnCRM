/**
 * Propagation of the default address to household members, in both membership modes, and
 * the handler classes the trigger dispatcher instantiates.
 *
 * Contact mode is exercised end to end through the triggers. Junction mode is exercised by
 * handing AddressService the membership HouseholdService would return, because the
 * membership junction and person accounts cannot both be created in one org shape; the
 * service reads membership only through that one call, so this is the whole of the
 * difference between the two modes as far as addresses are concerned.
 */
@IsTest
private class AddressPropagationTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final String WINTER_CITY = 'Phoenix';
    private static final String MEMBER_OWN_STREET = '1912 North Third Street';
    private static final String MEMBER_OWN_CITY = 'Tucson';

    @IsTest
    static void contactModeMembersGetTheHouseholdAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Sofia', 'Garcia', garcia.Id)
            };
            insert members;

            Test.startTest();
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
            Test.stopTest();

            List<Contact> moved = [
                SELECT MailingStreet, MailingCity
                FROM Contact
                WHERE AccountId = :garcia.Id
            ];
            Assert.areEqual(3, moved.size(), 'All three members should still be in the household.');
            for (Contact member : moved) {
                Assert.areEqual(
                    WINTER_STREET,
                    member.MailingStreet,
                    'Every member moves with the household.'
                );
                Assert.areEqual(
                    WINTER_CITY,
                    member.MailingCity,
                    'Every member moves with the household.'
                );
            }
        }
    }

    @IsTest
    static void junctionModeMembershipOverridesWhatContactModeWouldSay() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Account otherHousehold = AddressTestDataFactory.newHousehold('The Nowak Family');
            insert new List<Account>{ garcia, otherHousehold };
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', otherHousehold.Id);
            insert ana;

            Test.startTest();
            AddressService.membersByHouseholdOverride = new Map<Id, Set<Id>>{
                garcia.Id => new Set<Id>{ ana.Id }
            };
            try {
                insert new Address__c(
                    Account__c = garcia.Id,
                    Type__c = 'Home',
                    Street__c = WINTER_STREET,
                    City__c = WINTER_CITY,
                    Is_Default__c = true
                );
            } finally {
                AddressService.membersByHouseholdOverride = null;
            }
            Test.stopTest();

            Contact moved = [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id];
            Assert.areEqual(
                WINTER_STREET,
                moved.MailingStreet,
                'A person who belongs to the household through the junction moves with it, even though the contact sits under another account.'
            );
        }
    }

    /**
     * Only the half of the claim that this org shape can reach. A member held as an account is
     * written through its person mailing fields, and those fields exist only where the org has
     * person accounts, which a Platform only org (ADR-0013) does not: `personMailingCopy`
     * returns nothing there, so there is no written value to assert. What is asserted instead
     * is the part that holds in every org shape and that the propagation code could get wrong:
     * a member account is never written through its billing fields, which is what would happen
     * if it were treated as the address owner. The member therefore carries a billing address
     * of its own before the propagation runs, so the assertion is that the propagation left it
     * alone rather than that the field started empty.
     *
     * On an org that does have person accounts this method covers a second thing, which is why
     * the member is a household record rather than a person: the member account does not hold a
     * person, so the propagation must leave it out entirely. Before that guard existed the
     * propagation wrote person mailing fields on it, the platform refused the update, and the
     * address the user was saving was refused with it.
     */
    @IsTest
    static void aMemberAccountIsNeverWrittenThroughItsBillingFields() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Account personLikeAccount = AddressTestDataFactory.newHousehold('Ana Garcia');
            personLikeAccount.BillingStreet = MEMBER_OWN_STREET;
            personLikeAccount.BillingCity = MEMBER_OWN_CITY;
            insert new List<Account>{ garcia, personLikeAccount };

            Test.startTest();
            AddressService.membersByHouseholdOverride = new Map<Id, Set<Id>>{
                garcia.Id => new Set<Id>{ personLikeAccount.Id }
            };
            try {
                insert new Address__c(
                    Account__c = garcia.Id,
                    Type__c = 'Home',
                    Street__c = WINTER_STREET,
                    City__c = WINTER_CITY,
                    Is_Default__c = true
                );
            } finally {
                AddressService.membersByHouseholdOverride = null;
            }
            Test.stopTest();

            Account member = [
                SELECT BillingStreet, BillingCity
                FROM Account
                WHERE Id = :personLikeAccount.Id
            ];
            Assert.areEqual(
                MEMBER_OWN_STREET,
                member.BillingStreet,
                'The household address is never copied into a member account billing fields.'
            );
            Assert.areEqual(
                MEMBER_OWN_CITY,
                member.BillingCity,
                'Which is true of every billing field, not just the street.'
            );
            Account household = [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                WINTER_STREET,
                household.BillingStreet,
                'The household that owns the address still gets its billing fields.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'And the address was saved rather than refused on account of the member.'
            );
        }
    }

    @IsTest
    static void addressHandlerIgnoresASaveThatChangedNothingAboutTheAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            Address__c home = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
            insert home;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            update new Contact(Id = ana.Id, MailingStreet = null, MailingCity = null);

            Test.startTest();
            Address__c unchanged = [
                SELECT
                    Id,
                    Account__c,
                    Contact__c,
                    Person_Account__c,
                    Type__c,
                    Street__c,
                    City__c,
                    State__c,
                    Postal_Code__c,
                    Country__c,
                    Is_Default__c
                FROM Address__c
                WHERE Id = :home.Id
            ];
            driveAfterUpdate(
                new AddressTriggerHandler(),
                new List<SObject>{ unchanged },
                new Map<Id, SObject>{ unchanged.Id => unchanged }
            );
            Test.stopTest();

            Contact stillCleared = [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id];
            Assert.areEqual(
                null,
                stillCleared.MailingStreet,
                'Saving an address without changing it should not rewrite anybody.'
            );
        }
    }

    @IsTest
    static void handlerContextsThatDoNothingAreSafeToCall() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;

            Test.startTest();
            for (
                TriggerHandler handler : new List<TriggerHandler>{
                    new AddressTriggerHandler(),
                    new ContactAddressHandler(),
                    new AccountAddressHandler()
                }
            ) {
                TriggerHandler.testNew = new List<SObject>();
                TriggerHandler.testNewMap = new Map<Id, SObject>();
                TriggerHandler.testOld = new List<SObject>();
                TriggerHandler.testOldMap = new Map<Id, SObject>();
                handler.beforeInsert();
                handler.beforeUpdate();
                handler.beforeDelete();
                handler.afterInsert();
                handler.afterUpdate();
                handler.afterDelete();
                handler.afterUndelete();
            }
            clearHandlerContext();
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c],
                'A handler called with nothing to do writes nothing.'
            );
        }
    }

    @IsTest
    static void handlersCalledDirectlyDoTheirWork() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = WINTER_STREET;
            garcia.BillingCity = WINTER_CITY;
            insert garcia;
            Account reloaded = [
                SELECT
                    Id,
                    RecordTypeId,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingPostalCode,
                    BillingCountry
                FROM Account
                WHERE Id = :garcia.Id
            ];
            delete [SELECT Id FROM Address__c];

            Test.startTest();
            driveAfterInsert(new AccountAddressHandler(), new List<SObject>{ reloaded });
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'The account handler should keep the address the household was created with.'
            );
        }
    }

    @IsTest
    static void contactHandlerCapturesOnlyThePeopleWhoActuallyMoved() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
            };
            insert members;
            Contact ana = new Contact(Id = members[0].Id, MailingStreet = WINTER_STREET);
            Contact luis = new Contact(Id = members[1].Id);
            Map<Id, SObject> oldMap = new Map<Id, SObject>{
                members[0].Id => new Contact(Id = members[0].Id),
                members[1].Id => new Contact(Id = members[1].Id)
            };

            Test.startTest();
            driveAfterUpdate(new ContactAddressHandler(), new List<SObject>{ ana, luis }, oldMap);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'One household address, created once, from the one person who moved.'
            );
        }
    }

    /**
     * Drives one handler context outside a trigger. `TriggerHandler` reads the records
     * through its own accessors, which return these overrides when they are set, so a test
     * can exercise a handler without arranging a real DML that would fire every other
     * automation as well.
     */
    private static void driveAfterInsert(TriggerHandler handler, List<SObject> records) {
        TriggerHandler.testNew = records;
        TriggerHandler.testNewMap = new Map<Id, SObject>(records);
        try {
            handler.afterInsert();
        } finally {
            clearHandlerContext();
        }
    }

    private static void driveAfterUpdate(
        TriggerHandler handler,
        List<SObject> records,
        Map<Id, SObject> previousById
    ) {
        TriggerHandler.testNew = records;
        TriggerHandler.testNewMap = new Map<Id, SObject>(records);
        TriggerHandler.testOld = previousById.values();
        TriggerHandler.testOldMap = previousById;
        try {
            handler.afterUpdate();
        } finally {
            clearHandlerContext();
        }
    }

    private static void clearHandlerContext() {
        TriggerHandler.testNew = null;
        TriggerHandler.testNewMap = null;
        TriggerHandler.testOld = null;
        TriggerHandler.testOldMap = null;
    }
}
