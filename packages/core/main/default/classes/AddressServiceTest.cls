/**
 * AddressService: capture from the standard fields, propagation back to them, one default
 * per owner, the loop guard, bulk safety, and the seasonal helper C-18 will use.
 *
 * The households belong to Maria's organization and the people are the Garcia family from
 * the admin guide, who spend January to March in Arizona.
 */
@IsTest
private class AddressServiceTest {
    private static final String HOME_STREET = '812 Willow Lane';
    private static final String HOME_CITY = 'Springfield';
    private static final String WINTER_STREET = '4120 East Camelback Road';
    private static final String WINTER_CITY = 'Phoenix';

    @IsTest
    static void capturesAddressWhenHouseholdIsCreatedWithOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            garcia.BillingCity = HOME_CITY;
            garcia.BillingState = 'IL';
            garcia.BillingPostalCode = '62704';
            garcia.BillingCountry = 'United States';

            Test.startTest();
            insert garcia;
            Test.stopTest();

            List<Address__c> addresses = [
                SELECT Id, Type__c, Street__c, City__c, Is_Default__c, Account__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
            ];
            Assert.areEqual(
                1,
                addresses.size(),
                'The household should keep the address it was created with.'
            );
            Assert.areEqual('Home', addresses[0].Type__c, 'A household address is a home address.');
            Assert.areEqual(HOME_STREET, addresses[0].Street__c, 'The street should be kept.');
            Assert.isTrue(
                addresses[0].Is_Default__c,
                'The only address on file is the one in use.'
            );
        }
    }

    @IsTest
    static void capturesWorkAddressWhenOrganizationIsCreatedWithOne() {
        System.runAs(TestUsers.admin()) {
            Account funder = AddressTestDataFactory.newOrganization(
                'Springfield Community Foundation'
            );
            funder.BillingStreet = '55 Foundation Way';
            funder.BillingCity = HOME_CITY;

            Test.startTest();
            insert funder;
            Test.stopTest();

            List<Address__c> addresses = [
                SELECT Id, Type__c, Is_Default__c
                FROM Address__c
                WHERE Account__c = :funder.Id
            ];
            Assert.areEqual(1, addresses.size(), 'The organization should keep its address.');
            Assert.areEqual(
                'Work',
                addresses[0].Type__c,
                'An organization address is a work address.'
            );
            Assert.isTrue(
                addresses[0].Is_Default__c,
                'The only address on file is the one in use.'
            );
        }
    }

    @IsTest
    static void capturesNothingWhenNoAddressWasEntered() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');

            Test.startTest();
            insert garcia;
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'A household created with no address should not get an empty address record.'
            );
        }
    }

    @IsTest
    static void capturesPersonalAddressWhenAContactIsCreatedWithOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            ana.MailingStreet = HOME_STREET;
            ana.MailingCity = HOME_CITY;

            Test.startTest();
            insert ana;
            Test.stopTest();

            List<Address__c> addresses = [
                SELECT Id, Account__c, Contact__c, Street__c, Is_Default__c
                FROM Address__c
            ];
            Assert.areEqual(1, addresses.size(), 'One address should have been created.');
            Assert.areEqual(
                garcia.Id,
                addresses[0].Account__c,
                'The default behavior moves the household.'
            );
            Assert.areEqual(HOME_STREET, addresses[0].Street__c, 'The street should be kept.');
        }
    }

    @IsTest
    static void updatingAMemberMovesTheWholeHouseholdInContactMode() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
            };
            insert members;

            Test.startTest();
            Contact ana = members[0];
            ana.MailingStreet = WINTER_STREET;
            ana.MailingCity = WINTER_CITY;
            update ana;
            Test.stopTest();

            Account moved = [SELECT BillingStreet, BillingCity FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(WINTER_STREET, moved.BillingStreet, 'The household should have moved.');
            for (Contact member : [
                SELECT MailingStreet
                FROM Contact
                WHERE AccountId = :garcia.Id
            ]) {
                Assert.areEqual(
                    WINTER_STREET,
                    member.MailingStreet,
                    'Every member of the household should have moved with it.'
                );
            }
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
                ],
                'The household keeps one address in use, not one per edit.'
            );
        }
    }

    @IsTest
    static void creatingAPersonalAddressLeavesTheHouseholdWhereItIs() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Contact_Address_Change_Behavior__c = 'Create personal address';
            upsert settings;

            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            insert garcia;
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
            };
            insert members;

            Test.startTest();
            Contact ana = members[0];
            ana.MailingStreet = WINTER_STREET;
            update ana;
            Test.stopTest();

            List<Address__c> personal = [
                SELECT Id, Street__c, Is_Default__c
                FROM Address__c
                WHERE Contact__c = :ana.Id
            ];
            Assert.areEqual(1, personal.size(), 'Ana should have an address of her own.');
            Assert.areEqual(WINTER_STREET, personal[0].Street__c, 'It should hold the new street.');
            Account household = [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                HOME_STREET,
                household.BillingStreet,
                'The rest of the household should not have moved.'
            );
            Contact luis = [SELECT MailingStreet FROM Contact WHERE Id = :members[1].Id];
            Assert.areNotEqual(
                WINTER_STREET,
                luis.MailingStreet,
                'Only Ana moved, so Luis should be where he was.'
            );
        }
    }

    @IsTest
    static void settingADefaultClearsThePreviousOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            garcia.BillingCity = HOME_CITY;
            insert garcia;
            Address__c winter = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31,
                Is_Default__c = true
            );

            Test.startTest();
            insert winter;
            Test.stopTest();

            List<Address__c> defaults = [
                SELECT Id, Street__c
                FROM Address__c
                WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(1, defaults.size(), 'A household has one address in use at a time.');
            Assert.areEqual(
                WINTER_STREET,
                defaults[0].Street__c,
                'The new address should be in use.'
            );
            Account moved = [SELECT BillingCity FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                WINTER_CITY,
                moved.BillingCity,
                'The standard fields follow the default.'
            );
        }
    }

    @IsTest
    static void deletingTheDefaultPromotesTheMostRecentRemainingAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            garcia.BillingCity = HOME_CITY;
            insert garcia;
            Address__c winter = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Other',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );
            insert winter;

            Test.startTest();
            delete winter;
            Test.stopTest();

            List<Address__c> remaining = [
                SELECT Id, Street__c, Is_Default__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
            ];
            Assert.areEqual(1, remaining.size(), 'The home address should still be on file.');
            Assert.isTrue(remaining[0].Is_Default__c, 'It should have been promoted.');
            Account household = [SELECT BillingCity FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                HOME_CITY,
                household.BillingCity,
                'The standard fields follow the promotion.'
            );
        }
    }

    @IsTest
    static void loopGuardStopsTheTwoDirectionsCallingEachOther() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            ana.MailingStreet = HOME_STREET;

            Test.startTest();
            insert ana;
            Integer queriesAfterCapture = Limits.getQueries();
            Assert.isTrue(
                queriesAfterCapture < Limits.getLimitQueries(),
                'The capture must not run away.'
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Address__c],
                'One edit should produce one address, not an address per pass round the loop.'
            );
        }
    }

    @IsTest
    static void loopGuardSkipsWorkWhilePropagationIsInFlight() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;

            Test.startTest();
            AddressService.isPropagating = true;
            try {
                AddressService.captureFromStandardFields(new List<Account>{ garcia }, null);
                AddressService.syncDefaultToStandardFields(
                    new List<Address__c>{
                        new Address__c(Account__c = garcia.Id, Is_Default__c = true)
                    }
                );
            } finally {
                AddressService.isPropagating = false;
            }
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c],
                'Nothing runs while a propagation is already in flight.'
            );
        }
    }

    @IsTest
    static void twoHundredHouseholdsAreCapturedInOneInsert() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                Account household = AddressTestDataFactory.newHousehold('Household ' + i);
                household.BillingStreet = i + ' Willow Lane';
                household.BillingCity = HOME_CITY;
                households.add(household);
            }

            Test.startTest();
            insert households;
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Address__c WHERE Is_Default__c = TRUE],
                'Every household in the batch should have kept its address.'
            );
        }
    }

    @IsTest
    static void twoHundredContactsMoveTheirHouseholdsInOneUpdate() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 200; i++) {
                households.add(AddressTestDataFactory.newHousehold('Household ' + i));
            }
            insert households;
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(
                    AddressTestDataFactory.newContact('Person', 'Number ' + i, households[i].Id)
                );
            }
            insert people;
            for (Integer i = 0; i < 200; i++) {
                people[i].MailingStreet = i + ' East Camelback Road';
                people[i].MailingCity = WINTER_CITY;
            }

            Test.startTest();
            update people;
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Address__c WHERE Is_Default__c = TRUE],
                'Each household should hold exactly one address in use.'
            );
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Account WHERE BillingCity = :WINTER_CITY],
                'Every household should have moved.'
            );
        }
    }

    /**
     * The owner named in Person Account is an account that does not hold a person, which is a
     * mistake the object cannot prevent: the field is a lookup to Account. On an org without
     * person accounts the mailing fields are not there to write. On an org with them they are
     * there on every account, and only a person account will take a value, so the propagation
     * has to leave this one alone. Either way the address saves and the household keeps its
     * own billing address, so one method covers both shapes.
     */
    @IsTest
    static void personOwnedAddressSkipsAnAccountThatHoldsNoPerson() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            insert garcia;
            Address__c personal = new Address__c(
                Person_Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );

            Test.startTest();
            insert personal;
            Test.stopTest();

            Address__c saved = [SELECT Id, Is_Default__c FROM Address__c WHERE Id = :personal.Id];
            Assert.isTrue(
                saved.Is_Default__c,
                'The address saves rather than being refused because its owner holds no person.'
            );
            Account untouched = [SELECT BillingCity FROM Account WHERE Id = :garcia.Id];
            Assert.areEqual(
                null,
                untouched.BillingCity,
                'A person owned address writes the person, never the household billing fields.'
            );
        }
    }

    /**
     * Mutual exclusion (product-plan Section 11.2 item 9). A household Account that already
     * carries a native Nonprofit Cloud household group never has its billing address written
     * from a default Address__c, and the address is never propagated from it to household
     * members either.
     */
    @IsTest
    static void billingAndMemberAddressesAreNotWrittenForAHouseholdWithANativeGroup() {
        System.runAs(TestUsers.admin()) {
            Account nativeHousehold = AddressTestDataFactory.newHousehold('Native Household');
            insert nativeHousehold;
            Contact member = AddressTestDataFactory.newContact(
                'Maria',
                'Garcia',
                nativeHousehold.Id
            );
            insert member;
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{
                nativeHousehold.Id
            };
            Address__c address = new Address__c(
                Account__c = nativeHousehold.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY,
                Is_Default__c = true
            );

            Test.startTest();
            insert address;
            Test.stopTest();

            Account untouchedHousehold = [
                SELECT BillingStreet, BillingCity
                FROM Account
                WHERE Id = :nativeHousehold.Id
            ];
            Assert.isNull(
                untouchedHousehold.BillingStreet,
                'The billing address of a household with a native group is never written'
            );
            Contact untouchedMember = [SELECT MailingStreet FROM Contact WHERE Id = :member.Id];
            Assert.isNull(
                untouchedMember.MailingStreet,
                'The address of a household with a native group is never propagated to its members'
            );
        }
    }

    @IsTest
    static void seasonalRangeInsideOneYearIsActiveOnlyInsideIt() {
        System.runAs(TestUsers.admin()) {
            Address__c winter = new Address__c(
                Type__c = 'Seasonal',
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31
            );
            Assert.isTrue(
                AddressService.isSeasonalActiveOn(winter, Date.newInstance(2027, 2, 14)),
                'February falls inside January to March.'
            );
            Assert.isFalse(
                AddressService.isSeasonalActiveOn(winter, Date.newInstance(2027, 7, 4)),
                'July falls outside January to March.'
            );
        }
    }

    @IsTest
    static void seasonalRangeThatWrapsTheYearIsOneRange() {
        System.runAs(TestUsers.admin()) {
            Address__c snowbird = new Address__c(
                Type__c = 'Seasonal',
                Seasonal_Start_Month__c = 11,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31
            );
            Assert.isTrue(
                AddressService.isSeasonalActiveOn(snowbird, Date.newInstance(2027, 12, 25)),
                'December falls inside November to March.'
            );
            Assert.isTrue(
                AddressService.isSeasonalActiveOn(snowbird, Date.newInstance(2028, 2, 2)),
                'February falls inside November to March.'
            );
            Assert.isFalse(
                AddressService.isSeasonalActiveOn(snowbird, Date.newInstance(2027, 6, 1)),
                'June falls outside November to March.'
            );
        }
    }

    @IsTest
    static void anAddressThatIsNotSeasonalIsNeverSeasonallyActive() {
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(AddressService.isSeasonalActiveToday(null), 'Nothing is not active.');
            Assert.isFalse(
                AddressService.isSeasonalActiveToday(new Address__c(Type__c = 'Home')),
                'A home address is not a seasonal one.'
            );
            Assert.isFalse(
                AddressService.isSeasonalActiveToday(
                    new Address__c(Type__c = 'Seasonal', Seasonal_Start_Month__c = 1)
                ),
                'A seasonal address with no full range cannot be judged.'
            );
        }
    }
}
