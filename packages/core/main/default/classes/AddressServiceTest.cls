/**
 * AddressService: capture from the standard fields, propagation back to them, one default
 * per owner, the loop guard, bulk safety, and the seasonal helper C-18 will use.
 *
 * The households belong to Maria's organization and the people are the Garcia family from
 * the admin guide, who spend January to March in Arizona.
 */
@IsTest(testFor='ApexClass:AddressService')
private class AddressServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

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
            AddressTestDataFactory.putStateAndCountry(garcia, 'Billing', 'IL', 'US');
            garcia.BillingPostalCode = '62704';

            Test.startTest();
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Address__c WHERE Account__c = :garcia.Id],
                'A household created with no address should not get an empty address record.'
            );
        }
    }

    @IsTest
    static void aStateTypedAsACodeReachesTheMembersInEitherKindOfOrg() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;

            Test.startTest();
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY,
                State__c = 'IL',
                Postal_Code__c = '62704',
                Country__c = 'US',
                Is_Default__c = true
            );
            Test.stopTest();

            Contact saved = [
                SELECT MailingStreet, MailingState, MailingCountry
                FROM Contact
                WHERE Id = :ana.Id
            ];
            Assert.areEqual(HOME_STREET, saved.MailingStreet, 'The address reached Ana');
            if (AddressService.usesStateAndCountryPicklists()) {
                // The platform shows the name of the code that was written.
                Assert.areEqual('Illinois', saved.MailingState, 'Written as the state code');
                Assert.areEqual('United States', saved.MailingCountry, 'And the country code');
            } else {
                Assert.areEqual('IL', saved.MailingState, 'Written as typed');
                Assert.areEqual('US', saved.MailingCountry, 'Both of them');
            }
        }
    }

    @IsTest
    static void capturesPersonalAddressWhenAContactIsCreatedWithOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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

    /**
     * The household already has a default address. A member's new mailing address becomes
     * a new default, the old one is kept as history (R-AD7), and the move reaches the
     * household's billing address and every other member, as the admin guide walks through.
     */
    @IsTest
    static void aNewAddressReplacesAnExistingDefaultAndKeepsTheOldOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            garcia.BillingStreet = HOME_STREET;
            garcia.BillingCity = HOME_CITY;
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            List<Contact> members = new List<Contact>{
                AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id),
                AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id)
            };
            insert members;
            Id oldDefaultId = [
                SELECT Id
                FROM Address__c
                WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
            ]
            .Id;

            Test.startTest();
            update new Contact(
                Id = members[0].Id,
                MailingStreet = WINTER_STREET,
                MailingCity = WINTER_CITY
            );
            Test.stopTest();

            Address__c oldAddress = [
                SELECT Street__c, Is_Default__c
                FROM Address__c
                WHERE Id = :oldDefaultId
            ];
            Assert.areEqual(
                HOME_STREET,
                oldAddress.Street__c,
                'The old address is not overwritten'
            );
            Assert.isFalse(oldAddress.Is_Default__c, 'It is no longer the one in use');
            Address__c inUse = [
                SELECT Street__c, Type__c
                FROM Address__c
                WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
            ];
            Assert.areEqual(WINTER_STREET, inUse.Street__c, 'The new address is in use');
            Assert.areEqual(
                WINTER_STREET,
                [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id].BillingStreet,
                'The household billing address followed'
            );
            Assert.areEqual(
                WINTER_STREET,
                [SELECT MailingStreet FROM Contact WHERE Id = :members[1].Id].MailingStreet,
                'Luis moved with the household'
            );
        }
    }

    /**
     * During a season the seasonal address is the default. A permanent address typed in
     * then is a new record; the seasonal one is not overwritten, so the new permanent
     * address is there to come back to in the spring.
     */
    @IsTest
    static void anEditDuringASeasonDoesNotOverwriteTheSeasonalAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            Address__c seasonal = new Address__c(
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
            insert seasonal;

            Test.startTest();
            update new Contact(Id = ana.Id, MailingStreet = HOME_STREET, MailingCity = HOME_CITY);
            Test.stopTest();

            Address__c kept = [
                SELECT Street__c, Type__c
                FROM Address__c
                WHERE Id = :seasonal.Id
            ];
            Assert.areEqual(WINTER_STREET, kept.Street__c, 'The seasonal address is unchanged');
            Assert.areEqual('Seasonal', kept.Type__c, 'And still seasonal');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c = :garcia.Id AND Type__c = 'Home' AND Street__c = :HOME_STREET
                ],
                'The permanent address is its own Home record'
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);

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
            Database.insert(households, AccessLevel.SYSTEM_MODE);
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
            Database.insert(households, AccessLevel.SYSTEM_MODE);
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
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
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
            Database.insert(nativeHousehold, AccessLevel.SYSTEM_MODE);
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
            Date today = Date.today();
            Assert.isFalse(AddressService.isSeasonalActiveOn(null, today), 'Nothing is not active.');
            Assert.isFalse(
                AddressService.isSeasonalActiveOn(new Address__c(Type__c = 'Home'), today),
                'A home address is not a seasonal one.'
            );
            Assert.isFalse(
                AddressService.isSeasonalActiveOn(
                    new Address__c(Type__c = 'Seasonal', Seasonal_Start_Month__c = 1),
                    today
                ),
                'A seasonal address with no full range cannot be judged.'
            );
        }
    }

    @IsTest
    static void selectorReturnsNothingWhenAskedForNothing() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Assert.areEqual(
                0,
                AddressSelector.selectByOwnerIds(null).size(),
                'No owners, no addresses.'
            );
            Assert.areEqual(
                0,
                AddressSelector.selectByOwnerIds(new Set<Id>()).size(),
                'No owners, no addresses.'
            );
            Assert.areEqual(
                0,
                AddressSelector.selectDefaultsByOwnerIds(null, null).size(),
                'No owners, no defaults.'
            );
            Assert.areEqual(
                0,
                AddressSelector.selectStoredValues(Contact.SObjectType, null, null).size(),
                'No records, no stored values.'
            );
            Test.stopTest();
        }
    }

    /**
     * Copying an address onto standard fields that already hold it is not sent as a second
     * save; a copy that changes any value, even only its case, still is.
     */
    @IsTest
    static void onlyCopiesThatChangeAStoredValueAreWritten() {
        System.runAs(TestUsers.admin()) {
            Contact elena = new Contact(
                FirstName = 'Elena',
                LastName = 'Garcia',
                MailingStreet = HOME_STREET,
                MailingCity = HOME_CITY
            );
            insert as user elena;
            Contact held = [
                SELECT Id, MailingStreet, MailingCity
                FROM Contact
                WHERE Id = :elena.Id
                WITH USER_MODE
            ];
            Contact same = new Contact(
                Id = held.Id,
                MailingStreet = held.MailingStreet,
                MailingCity = held.MailingCity
            );
            Contact recased = new Contact(
                Id = held.Id,
                MailingStreet = held.MailingStreet.toUpperCase(),
                MailingCity = held.MailingCity
            );
            Contact cleared = new Contact(Id = held.Id, MailingStreet = null);
            Contact unknown = new Contact(
                Id = Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                        .getKeyPrefix() + '000000000000AAA',
                MailingStreet = HOME_STREET
            );

            Test.startTest();
            List<SObject> written = AddressService.withChanges(
                new List<SObject>{ same, recased, cleared, unknown }
            );
            Test.stopTest();

            Assert.areEqual(
                3,
                written.size(),
                'Only the copy that matches what is stored is left out.'
            );
            Assert.isTrue(written[0] === recased, 'A change of case is a change.');
            Assert.isTrue(written[1] === cleared, 'Clearing a value is a change.');
            Assert.isTrue(written[2] === unknown, 'A record that is not found is still written.');
            Assert.areEqual(
                0,
                AddressService.withChanges(null).size(),
                'Nothing, nothing written.'
            );
        }
    }

    /**
     * An address added through the account lookup stays on it for a household or an
     * organization, on every org shape.
     */
    @IsTest
    static void anAddressOnAHouseholdStaysOnTheAccountLookup() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            Address__c home = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                Is_Default__c = true
            );
            insert home;
            Test.stopTest();

            Address__c saved = [
                SELECT Account__c, Person_Account__c
                FROM Address__c
                WHERE Id = :home.Id
            ];
            Assert.areEqual(garcia.Id, saved.Account__c, 'A household owns its address');
            Assert.isNull(saved.Person_Account__c, 'And is not taken for a person');
        }
    }

    /**
     * The address panel on a person account page saves through the account lookup. The
     * address is moved to the person lookup, so it reaches the person's mailing address
     * (R-AD3). Needs real person accounts of a type the running user is given (oi-pa).
     */
    @IsTest
    static void anAddressAddedOnAPersonAccountBelongsToThePerson() {
        System.runAs(TestUsers.admin()) {
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            if (personType == null) {
                // No person account type this user may create: a Platform-only org, or an
                // org (a Nonprofit Cloud trial) that does not give the admin profile one.
                return;
            }
            SObject person = Account.SObjectType.newSObject();
            person.put('RecordTypeId', personType);
            person.put('FirstName', 'Ana');
            person.put('LastName', 'Okafor');
            insert person;

            Test.startTest();
            Address__c home = new Address__c(
                Account__c = person.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                Is_Default__c = true
            );
            insert home;
            Test.stopTest();

            Address__c saved = [
                SELECT Account__c, Person_Account__c
                FROM Address__c
                WHERE Id = :home.Id
            ];
            Assert.areEqual(person.Id, saved.Person_Account__c, 'The person owns the address');
            Assert.isNull(saved.Account__c, 'Not the account lookup');
        }
    }

    /** PEOPLE-24: with no household to move, the person keeps the address as their own. */
    @IsTest
    static void aPersonWithNoHouseholdKeepsTheirAddressAsTheirOwn() {
        System.runAs(TestUsers.admin()) {
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', null);
            ana.MailingStreet = HOME_STREET;
            ana.MailingCity = HOME_CITY;

            Test.startTest();
            HouseholdService.suspendAutomaticCreation();
            insert ana;
            HouseholdService.resumeAutomaticCreation();
            Test.stopTest();

            List<Address__c> addresses = [
                SELECT Contact__c, Account__c, Street__c, Is_Default__c
                FROM Address__c
            ];
            Assert.areEqual(1, addresses.size(), 'The address was kept');
            Assert.areEqual(ana.Id, addresses[0].Contact__c, 'As her own');
            Assert.isTrue(addresses[0].Is_Default__c, 'And in use');
        }
    }

    // ------------------------------------------------ one address in use (PEOPLE-22, 49)

    @IsTest
    static void twoDefaultsForOneOwnerInOneSaveLeaveTheLastInUse() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c first = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY,
                Is_Default__c = true
            );
            Address__c second = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Other',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Is_Default__c = true
            );

            Test.startTest();
            insert new List<Address__c>{ first, second };
            Test.stopTest();

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Account__c = :garcia.Id AND Is_Default__c = TRUE
                ],
                'One address in use (R-AD2)'
            );
            Assert.isTrue(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :second.Id].Is_Default__c,
                'The last in the save'
            );
            Assert.areEqual(
                WINTER_CITY,
                [SELECT BillingCity FROM Account WHERE Id = :garcia.Id].BillingCity,
                'The standard fields show the one in use'
            );
        }
    }

    @IsTest
    static void untickingTheOnlyAddressInUseIsRefused() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c home = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY,
                Is_Default__c = true
            );
            insert home;

            Test.startTest();
            Database.SaveResult result = Database.update(
                new Address__c(Id = home.Id, Is_Default__c = false),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'The household would have no address in use');
            Assert.areEqual(
                Label.Core_Address_CannotUntickOnlyDefault,
                result.getErrors()[0].getMessage(),
                'The person is told what to do instead'
            );
        }
    }

    @IsTest
    static void movingTheDefaultInOneSaveIsAllowed() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c home = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY,
                Is_Default__c = true
            );
            Address__c other = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Other',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY
            );
            insert new List<Address__c>{ home, other };

            Test.startTest();
            update new List<Address__c>{
                new Address__c(Id = home.Id, Is_Default__c = false),
                new Address__c(Id = other.Id, Is_Default__c = true)
            };
            Test.stopTest();

            Assert.isTrue(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :other.Id].Is_Default__c,
                'The other address is in use'
            );
        }
    }

    @IsTest
    static void deletingTheDefaultPrefersAnAddressThatIsNotSeasonal() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c home = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = HOME_STREET,
                City__c = HOME_CITY
            );
            insert home;
            Address__c winter = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                Street__c = WINTER_STREET,
                City__c = WINTER_CITY,
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 3,
                Seasonal_End_Day__c = 31
            );
            insert winter;
            Address__c work = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Other',
                City__c = 'Chicago',
                Is_Default__c = true
            );
            insert work;

            Test.startTest();
            delete work;
            Test.stopTest();

            Assert.isTrue(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :home.Id].Is_Default__c,
                'The home address is put in use, not the newer seasonal one'
            );
            Assert.isFalse(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :winter.Id].Is_Default__c,
                'The seasonal address waits for its season'
            );
        }
    }

    @IsTest
    static void aDayItsMonthDoesNotHaveIsRefused() {
        System.runAs(TestUsers.admin()) {
            Account garcia = AddressTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Address__c aprilThirtyFirst = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                City__c = WINTER_CITY,
                Seasonal_Start_Month__c = 4,
                Seasonal_Start_Day__c = 31,
                Seasonal_End_Month__c = 5,
                Seasonal_End_Day__c = 31
            );
            Address__c februaryTwentyNinth = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Seasonal',
                City__c = WINTER_CITY,
                Seasonal_Start_Month__c = 1,
                Seasonal_Start_Day__c = 1,
                Seasonal_End_Month__c = 2,
                Seasonal_End_Day__c = 29
            );

            Test.startTest();
            List<Database.SaveResult> results = Database.insert(
                new List<Address__c>{ aprilThirtyFirst, februaryTwentyNinth },
                false
            );
            Test.stopTest();

            Assert.isFalse(results[0].isSuccess(), 'April has 30 days');
            Assert.isTrue(results[1].isSuccess(), 'February 29 is a day in a leap year');
        }
    }

    @IsTest
    static void ownerIdOfPrefersAccountThenContactThenPerson() {
        // runs-as: deploying user (pure function over in-memory records, no data access)
        Id accountId = Id.valueOf('001000000000001');
        Id contactId = Id.valueOf('003000000000001');
        Assert.isNull(AddressService.ownerIdOf(null));
        Assert.areEqual(
            accountId,
            AddressService.ownerIdOf(new Address__c(Account__c = accountId, Contact__c = contactId))
        );
        Assert.areEqual(
            contactId,
            AddressService.ownerIdOf(new Address__c(Contact__c = contactId))
        );
        Assert.isNull(AddressService.ownerIdOf(new Address__c()));
    }
}
