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
@IsTest(
    testFor='ApexClass:AddressService, ApexClass:AccountAddressHandler, ApexClass:ContactAddressHandler, ApexClass:AddressTriggerHandler'
)
private class AddressPropagationTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final String WINTER_CITY = 'Phoenix';
    private static final String MEMBER_OWN_STREET = '1912 North Third Street';
    private static final String MEMBER_OWN_CITY = 'Tucson';
    private static final String HOME_STREET = '6830 Sunset Lane';
    private static final String HOME_CITY = 'Springfield';
    private static final Integer TWO_HUNDRED = 200;

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

    // ------------------------------------------------- a billing address edited later (R-AD3)

    @IsTest
    static void aHouseholdBillingEditBecomesItsDefaultAndMovesTheMembers() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAt(HOME_STREET);
            insert garcia;
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
            };
            insert members;

            Test.startTest();
            update new Account(
                Id = garcia.Id,
                BillingStreet = WINTER_STREET,
                BillingCity = WINTER_CITY
            );
            Test.stopTest();

            List<Address__c> addresses = [
                SELECT Street__c, Type__c, Is_Default__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
                ORDER BY CreatedDate, Id
            ];
            Assert.areEqual(2, addresses.size(), 'The edit is kept as a new address record.');
            for (Address__c address : addresses) {
                Assert.areEqual(
                    address.Street__c == WINTER_STREET,
                    address.Is_Default__c,
                    'The new street is the default and the old one is kept as history.'
                );
                Assert.areEqual('Home', address.Type__c, 'A household address is a Home.');
            }
            for (Contact member : [SELECT MailingStreet FROM Contact WHERE Id IN :members]) {
                Assert.areEqual(
                    WINTER_STREET,
                    member.MailingStreet,
                    'Every member moves with the edited billing address.'
                );
            }
        }
    }

    @IsTest
    static void barnCrmsOwnBillingWriteIsNotCapturedAgain() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAt(HOME_STREET);
            insert garcia;
            update new Account(Id = garcia.Id, BillingStreet = WINTER_STREET);

            Test.startTest();
            // Writes the billing address from the address record, which fires the account
            // trigger again: that write must not come back as a capture.
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = MEMBER_OWN_STREET,
                City__c = MEMBER_OWN_CITY,
                Is_Default__c = true
            );
            // A save that leaves the billing address as it is adds nothing either.
            update new Account(Id = garcia.Id, Description = 'Moved in May');
            Test.stopTest();

            Assert.areEqual(
                3,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'One address on insert, one for the edit, one added on the card: no echo of either.'
            );
            Account household = [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                MEMBER_OWN_STREET,
                household.BillingStreet,
                'The default added on the card is the billing address.'
            );
        }
    }

    @IsTest
    static void twoHundredHouseholdBillingEditsAreCapturedInOneSave() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                Account household = householdAt(i + ' Sunset Lane');
                household.Name = 'The Bulk Family ' + i;
                households.add(household);
            }
            insert households;
            List<Contact> members = new List<Contact>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                members.add(AddressTestDataFactory.newContact('Ana', 'Bulk' + i, households[i].Id));
            }
            insert members;
            List<Account> edits = new List<Account>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                edits.add(new Account(Id = households[i].Id, BillingStreet = i + ' Winter Road'));
            }

            Test.startTest();
            update edits;
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED * 2,
                [SELECT COUNT() FROM Address__c WHERE Account__c IN :households],
                'Each household keeps its first address and gains one for the edit.'
            );
            Integer movedDefaults = 0;
            for (Address__c address : [
                SELECT Street__c
                FROM Address__c
                WHERE Account__c IN :households AND Is_Default__c = TRUE
            ]) {
                movedDefaults += address.Street__c.endsWith(' Winter Road') ? 1 : 0;
            }
            Assert.areEqual(
                TWO_HUNDRED,
                movedDefaults,
                'Every household has the edit as its default.'
            );
            Integer movedMembers = 0;
            for (Contact member : [SELECT MailingStreet FROM Contact WHERE Id IN :members]) {
                movedMembers += member.MailingStreet?.endsWith(' Winter Road') == true ? 1 : 0;
            }
            Assert.areEqual(TWO_HUNDRED, movedMembers, 'Every member moved with their household.');
        }
    }

    @IsTest
    static void aBillingEditOnAHouseholdWithANativeGroupIsLeftAlone() {
        System.runAs(TestUsers.admin()) {
            Account nativeHousehold = householdAt(HOME_STREET);
            insert nativeHousehold;
            Contact member = AddressTestDataFactory.newContact(
                'Maria',
                'Garcia',
                nativeHousehold.Id
            );
            insert member;
            Account before = [
                SELECT
                    Id,
                    RecordTypeId,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingPostalCode,
                    BillingCountry
                FROM Account
                WHERE Id = :nativeHousehold.Id
            ];
            Account edited = before.clone(true);
            edited.BillingStreet = WINTER_STREET;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{
                nativeHousehold.Id
            };

            Test.startTest();
            driveAfterUpdate(
                new AccountAddressHandler(),
                new List<SObject>{ edited },
                new Map<Id, SObject>{ before.Id => before }
            );
            Test.stopTest();

            Assert.isFalse(edited.hasErrors(), 'The save is not refused.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :nativeHousehold.Id],
                'Nonprofit Cloud manages this household, so its billing edit is not captured.'
            );
            Assert.isNull(
                [SELECT MailingStreet FROM Contact WHERE Id = :member.Id].MailingStreet,
                'And its members are not moved.'
            );
        }
    }

    // ------------------------------------------- members who keep their own address (R-AD3)

    @IsTest
    static void aMemberWithAnAddressOfTheirOwnStaysWhenTheHouseholdMoves() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAt(HOME_STREET);
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            insert personalAddress(ana.Id);

            Test.startTest();
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
            update new Account(Id = garcia.Id, BillingCity = 'Mesa');
            Test.stopTest();

            Assert.areEqual(
                MEMBER_OWN_STREET,
                [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id].MailingStreet,
                'Ana has an address of her own, so neither household move reaches her.'
            );
            Contact moved = [SELECT MailingStreet, MailingCity FROM Contact WHERE Id = :luis.Id];
            Assert.areEqual(WINTER_STREET, moved.MailingStreet, 'Luis moves with the household.');
            Assert.areEqual('Mesa', moved.MailingCity, 'Including the billing edit.');
        }
    }

    @IsTest
    static void theSeasonalSwapLeavesAMemberWithAnAddressOfTheirOwn() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAt(HOME_STREET);
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            insert personalAddress(ana.Id);
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = AddressService.TYPE_SEASONAL,
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31
            );

            Test.startTest();
            SeasonalAddressService.RunSummary summary = SeasonalAddressService.swapOwners(
                new Set<Id>{ garcia.Id },
                Date.newInstance(2027, 2, 14)
            );
            Test.stopTest();

            Assert.areEqual(1, summary.movedIn, 'The household moved to its winter address.');
            Assert.areEqual(
                WINTER_STREET,
                [SELECT MailingStreet FROM Contact WHERE Id = :luis.Id].MailingStreet,
                'Luis goes south with the household.'
            );
            Assert.areEqual(
                MEMBER_OWN_STREET,
                [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id].MailingStreet,
                'Ana keeps the address of her own.'
            );
        }
    }

    @IsTest
    static void inJunctionModeAHouseholdThatIsNotAPersonsOwnDoesNotMoveThem() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Account nowak = AddressTestDataFactory.newHousehold('The Nowak Family');
            insert new List<Account>{ garcia, nowak };
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Nowak');
            Contact luis = HouseholdTestDataFactory.newContact('Luis', 'Garcia');
            insert new List<Contact>{ ana, luis };
            // Ana's household is the Nowaks', where she is the primary member; she also
            // belongs to the Garcias'. Luis's only household is the Garcias'.
            insert new List<Household_Member__c>{
                new Household_Member__c(
                    Household__c = nowak.Id,
                    Contact__c = ana.Id,
                    Is_Primary__c = true
                ),
                new Household_Member__c(Household__c = garcia.Id, Contact__c = ana.Id),
                new Household_Member__c(
                    Household__c = garcia.Id,
                    Contact__c = luis.Id,
                    Is_Primary__c = true
                )
            };

            Test.startTest();
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
            Test.stopTest();

            Assert.areEqual(
                WINTER_STREET,
                [SELECT MailingStreet FROM Contact WHERE Id = :luis.Id].MailingStreet,
                'Luis moves with his household.'
            );
            Assert.isNull(
                [SELECT MailingStreet FROM Contact WHERE Id = :ana.Id].MailingStreet,
                'The Garcias are not Ana\'s household, so their address does not move her.'
            );
        }
    }

    private static Account householdAt(String street) {
        Account household = AddressTestDataFactory.newHousehold('The Garcia Family');
        household.BillingStreet = street;
        household.BillingCity = HOME_CITY;
        return household;
    }

    /** A default address owned by one person, as "Only that person moves" makes one. */
    private static Address__c personalAddress(Id contactId) {
        return new Address__c(
            Contact__c = contactId,
            Type__c = 'Home',
            Street__c = MEMBER_OWN_STREET,
            City__c = MEMBER_OWN_CITY,
            Is_Default__c = true
        );
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
