/**
 * The two household moves (R-AD9, ADR-NEXT) as AddressService makes them: Use for Whole
 * Household and Update Everyone's Address, in both membership modes, in "Nobody moves until
 * you choose", for many households at once, and refused for a user who may not make them.
 */
@IsTest(testFor='ApexClass:AddressService, ApexClass:HouseholdService')
private class AddressMoveTest {
    @TestSetup
    static void createTestUser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestUsers.admin();
        }
    }

    private static final String HOME_STREET = '6830 Sunset Lane';
    private static final String HOME_CITY = 'Springfield';
    private static final String OWN_STREET = '1912 North Third Street';
    private static final String OWN_CITY = 'Tucson';
    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final Integer TWO_HUNDRED = 200;

    // ------------------------------------------------------------ Use for Whole Household

    @IsTest
    static void usingAPersonsAddressMovesTheHouseholdAndBringsThemBack() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            Address__c anasOwn = ownAddress(ana.Id);
            insert anasOwn;

            Test.startTest();
            List<Address__c> added = AddressService.useForWholeHousehold(
                new Map<Id, Id>{ anasOwn.Id => garcia.Id }
            );
            Test.stopTest();

            Assert.areEqual(1, added.size(), 'The household gets one new address.');
            Assert.areEqual(
                OWN_STREET,
                primaryStreetOf(garcia.Id),
                'Ana\'s address is now the household\'s primary.'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c = :garcia.Id AND Street__c = :HOME_STREET
                ],
                'The old household address stays on file as history.'
            );
            Address__c kept = [SELECT Is_Default__c FROM Address__c WHERE Id = :anasOwn.Id];
            Assert.isFalse(kept.Is_Default__c, 'Ana follows the household again.');
            Assert.areEqual(OWN_STREET, mailingStreetOf(luis.Id), 'Luis moves with it.');
            Assert.areEqual(OWN_STREET, mailingStreetOf(ana.Id), 'So does Ana.');
            Assert.areEqual(
                OWN_STREET,
                [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id].BillingStreet,
                'The household\'s own address fields hold it.'
            );
        }
    }

    @IsTest
    static void usingAPersonsAddressMovesMembersEvenWhenNobodyMovesUntilYouChoose() {
        System.runAs(TestUsers.admin()) {
            useAddressUpdates('Manual');
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            Address__c anasOwn = ownAddress(ana.Id);
            insert anasOwn;

            Test.startTest();
            AddressService.useForWholeHousehold(new Map<Id, Id>{ anasOwn.Id => garcia.Id });
            Test.stopTest();

            Assert.areEqual(
                OWN_STREET,
                mailingStreetOf(luis.Id),
                'Choosing the button is choosing the move, so Luis moves.'
            );
        }
    }

    @IsTest
    static void inJunctionModeAPersonsOtherHouseholdCanTakeTheirAddress() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account garcia = householdAtHome('The Garcia Family');
            Account nowak = householdAtHome('The Nowak Family');
            Account stranger = householdAtHome('The Okafor Family');
            insert new List<Account>{ garcia, nowak, stranger };
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Nowak');
            Contact luis = HouseholdTestDataFactory.newContact('Luis', 'Garcia');
            insert new List<Contact>{ ana, luis };
            // Ana's household is the Nowaks'; she also belongs to the Garcias'.
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
            Address__c anasOwn = ownAddress(ana.Id);
            insert anasOwn;

            Test.startTest();
            Map<Id, Set<Id>> households = HouseholdService.currentHouseholdIdsByPerson(
                new Set<Id>{ ana.Id }
            );
            String refusal;
            try {
                AddressService.useForWholeHousehold(new Map<Id, Id>{ anasOwn.Id => stranger.Id });
            } catch (AddressService.AddressMoveException refused) {
                refusal = refused.getMessage();
            }
            AddressService.useForWholeHousehold(new Map<Id, Id>{ anasOwn.Id => garcia.Id });
            Test.stopTest();

            Assert.areEqual(
                new Set<Id>{ nowak.Id, garcia.Id },
                households.get(ana.Id),
                'Ana belongs to two households, so the card asks which.'
            );
            Assert.areEqual(
                System.Label.Core_Address_MoveNotTheirHousehold,
                refusal,
                'A household she does not belong to is refused.'
            );
            Assert.areEqual(OWN_STREET, primaryStreetOf(garcia.Id), 'The Garcias take it.');
            Assert.areEqual(OWN_STREET, mailingStreetOf(luis.Id), 'Luis moves with them.');
            Assert.isTrue(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :anasOwn.Id].Is_Default__c,
                'The Garcias are not Ana\'s own household, so she keeps her own address.'
            );
        }
    }

    @IsTest
    static void aHouseholdsOwnAddressIsNotAPersonsToUse() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Address__c householdAddress = [
                SELECT Id
                FROM Address__c
                WHERE Account__c = :garcia.Id
                LIMIT 1
            ];

            Test.startTest();
            String refusal;
            try {
                AddressService.useForWholeHousehold(
                    new Map<Id, Id>{ householdAddress.Id => garcia.Id }
                );
            } catch (AddressService.AddressMoveException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(System.Label.Core_Address_MoveNotAPersonsAddress, refusal, 'Refused.');
        }
    }

    @IsTest
    static void twoHundredPeopleCanEachMoveTheirHouseholdInOneCall() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer index = 0; index < TWO_HUNDRED; index++) {
                households.add(householdAtHome('Household ' + index));
            }
            insert households;
            List<Contact> people = new List<Contact>();
            for (Account household : households) {
                people.add(AddressTestDataFactory.newContact('Ana', household.Name, household.Id));
            }
            insert people;
            List<Address__c> owns = new List<Address__c>();
            for (Contact person : people) {
                owns.add(ownAddress(person.Id));
            }
            insert owns;
            Map<Id, Id> householdByAddress = new Map<Id, Id>();
            for (Integer index = 0; index < TWO_HUNDRED; index++) {
                householdByAddress.put(owns[index].Id, households[index].Id);
            }

            Test.startTest();
            List<Address__c> added = AddressService.useForWholeHousehold(householdByAddress);
            Test.stopTest();

            Assert.areEqual(TWO_HUNDRED, added.size(), 'Every household gets a new primary.');
            Assert.areEqual(
                TWO_HUNDRED,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Id IN :households AND BillingStreet = :OWN_STREET
                ],
                'Every household moved.'
            );
        }
    }

    // ------------------------------------------------------------ Update Everyone's Address

    @IsTest
    static void updateEveryonesAddressMovesTheRestAndOnlyTheTickedOwners() {
        System.runAs(TestUsers.admin()) {
            useAddressUpdates('Manual');
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            Contact sofia = AddressTestDataFactory.newContact('Sofia', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis, sofia };
            Address__c anasOwn = ownAddress(ana.Id);
            insert new List<Address__c>{ anasOwn, ownAddress(sofia.Id) };
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                Is_Default__c = true
            );
            Assert.isNull(mailingStreetOf(luis.Id), 'In Manual the new primary reached nobody.');

            Test.startTest();
            AddressService.HouseholdMove move = AddressService.householdMoves(
                    new Set<Id>{ garcia.Id }
                )
                .get(garcia.Id);
            AddressService.updateEveryonesAddress(
                new Map<Id, Set<Id>>{ garcia.Id => new Set<Id>{ ana.Id, luis.Id } }
            );
            Test.stopTest();

            Assert.areEqual(WINTER_STREET, move.primary.Street__c, 'The household\'s primary.');
            Assert.areEqual(new Set<Id>{ luis.Id }, move.taking, 'Only Luis takes it on his own.');
            Assert.areEqual(
                new Set<Id>{ ana.Id, sofia.Id },
                move.withTheirOwn,
                'Ana and Sofia have their own.'
            );
            Assert.areEqual(WINTER_STREET, mailingStreetOf(luis.Id), 'Luis moves.');
            Assert.areEqual(
                WINTER_STREET,
                mailingStreetOf(ana.Id),
                'Ana was ticked, so she moves.'
            );
            Assert.isFalse(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :anasOwn.Id].Is_Default__c,
                'Her own address stays on file, no longer in use.'
            );
            Assert.areEqual(OWN_STREET, mailingStreetOf(sofia.Id), 'Sofia was not ticked.');
        }
    }

    @IsTest
    static void updateEveryonesAddressNeedsAPrimary() {
        System.runAs(TestUsers.admin()) {
            Account empty = AddressTestDataFactory.newHousehold('The Empty Family');
            insert empty;

            Test.startTest();
            String refusal;
            try {
                AddressService.updateEveryonesAddress(new Map<Id, Set<Id>>{ empty.Id => null });
            } catch (AddressService.AddressMoveException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(System.Label.Core_Address_MoveNoPrimary, refusal, 'Refused.');
        }
    }

    @IsTest
    static void twoHundredHouseholdsCanBeUpdatedInOneCall() {
        System.runAs(TestUsers.admin()) {
            useAddressUpdates('Manual');
            List<Account> households = new List<Account>();
            for (Integer index = 0; index < TWO_HUNDRED; index++) {
                households.add(householdAtHome('Household ' + index));
            }
            insert households;
            List<Contact> people = new List<Contact>();
            for (Account household : households) {
                people.add(AddressTestDataFactory.newContact('Luis', household.Name, household.Id));
            }
            insert people;
            Map<Id, Set<Id>> everyone = new Map<Id, Set<Id>>();
            for (Account household : households) {
                everyone.put(household.Id, new Set<Id>());
            }

            Test.startTest();
            AddressService.updateEveryonesAddress(everyone);
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED,
                [SELECT COUNT() FROM Contact WHERE Id IN :people AND MailingStreet = :HOME_STREET],
                'Everyone took their household\'s address.'
            );
        }
    }

    @IsTest
    static void aUserWhoMayNotEditPeopleIsRefusedAndNothingChanges() {
        User reader = TestUsers.peopleReaderWith(
            'MoveReader',
            new List<String>{ 'BarnCRM_Read_Only' }
        );
        Account garcia;
        Contact luis;
        Address__c anasOwn;
        System.runAs(TestUsers.admin()) {
            useAddressUpdates('Manual');
            garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            anasOwn = ownAddress(ana.Id);
            insert anasOwn;
        }

        Test.startTest();
        Integer refused = 0;
        System.runAs(reader) {
            try {
                AddressService.updateEveryonesAddress(
                    new Map<Id, Set<Id>>{ garcia.Id => new Set<Id>() }
                );
            } catch (Exception noEdit) {
                refused++;
            }
            try {
                AddressService.useForWholeHousehold(new Map<Id, Id>{ anasOwn.Id => garcia.Id });
            } catch (Exception noEdit) {
                refused++;
            }
        }
        Test.stopTest();

        System.runAs(TestUsers.admin()) {
            Assert.areEqual(2, refused, 'Both moves are refused: they are written as the user.');
            Assert.isNull(mailingStreetOf(luis.Id), 'Luis did not move.');
            Assert.areEqual(HOME_STREET, primaryStreetOf(garcia.Id), 'Nor did the household.');
        }
    }

    // ------------------------------------------------------------ helpers

    private static void useAddressUpdates(String choice) {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Contact_Address_Change_Behavior__c = choice;
        upsert settings;
    }

    private static Account householdAtHome(String name) {
        Account household = AddressTestDataFactory.newHousehold(name);
        household.BillingStreet = HOME_STREET;
        household.BillingCity = HOME_CITY;
        return household;
    }

    private static Address__c ownAddress(Id contactId) {
        return new Address__c(
            Contact__c = contactId,
            Type__c = 'Home',
            Street__c = OWN_STREET,
            City__c = OWN_CITY,
            Is_Default__c = true
        );
    }

    private static String primaryStreetOf(Id householdId) {
        return [
            SELECT Street__c
            FROM Address__c
            WHERE Account__c = :householdId AND Is_Default__c = TRUE
            LIMIT 1
        ]
        .Street__c;
    }

    private static String mailingStreetOf(Id contactId) {
        return [SELECT MailingStreet FROM Contact WHERE Id = :contactId].MailingStreet;
    }
}
