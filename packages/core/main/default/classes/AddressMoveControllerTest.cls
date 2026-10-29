/**
 * The Addresses card's Apex surface for the two household moves (R-AD9): what the card offers
 * on a household and on a person, the confirmation's names, the two moves, and how a refusal
 * reaches the card.
 */
@IsTest(testFor='ApexClass:AddressMoveController, ApexClass:AddressSelector')
private class AddressMoveControllerTest {
    @TestSetup
    static void createTestUser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestUsers.admin();
        }
    }

    private static final String HOME_STREET = '6830 Sunset Lane';
    private static final String OWN_STREET = '1912 North Third Street';

    @IsTest
    static void aHouseholdIsOfferedUpdateEveryonesAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = household('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            AddressMoveController.CardContext context = AddressMoveController.getCardContext(
                garcia.Id
            );
            Test.stopTest();

            Assert.isTrue(
                context.isHousehold,
                'A household card offers Update Everyone\'s Address.'
            );
            Assert.isTrue(context.households.isEmpty(), 'There is no household to pick.');
        }
    }

    @IsTest
    static void inJunctionModeAPersonsHouseholdsAreListedTheirOwnFirst() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account garcia = household('The Garcia Family');
            Account nowak = household('The Nowak Family');
            Database.insert(new List<Account>{ garcia, nowak }, AccessLevel.SYSTEM_MODE);
            Contact ana = HouseholdTestDataFactory.newContact('Ana', 'Nowak');
            insert ana;
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = garcia.Id, Contact__c = ana.Id),
                new Household_Member__c(
                    Household__c = nowak.Id,
                    Contact__c = ana.Id,
                    Is_Primary__c = true
                )
            };

            Test.startTest();
            AddressMoveController.CardContext context = AddressMoveController.getCardContext(
                ana.Id
            );
            Test.stopTest();

            Assert.isFalse(context.isHousehold, 'Ana is a person.');
            Assert.areEqual(2, context.households.size(), 'She belongs to two households.');
            Assert.areEqual(nowak.Id, context.households[0].id, 'Her own household comes first.');
            Assert.areEqual('The Nowak Family', context.households[0].name, 'By name.');
            Assert.areEqual(garcia.Id, context.households[1].id, 'Then the other.');
        }
    }

    @IsTest
    static void thePreviewNamesWhoMovesAndWhoHasTheirOwn() {
        System.runAs(TestUsers.admin()) {
            Account garcia = household('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            insert ownAddress(ana.Id);

            Test.startTest();
            AddressMoveController.MovePreview preview = AddressMoveController.getMovePreview(
                garcia.Id
            );
            AddressMoveController.updateEveryonesAddress(garcia.Id, new List<Id>{ ana.Id });
            Test.stopTest();

            Assert.isTrue(preview.hasPrimary, 'The household has a primary address.');
            Assert.areEqual(1, preview.moving.size(), 'Luis takes it.');
            Assert.areEqual('Luis Garcia', preview.moving[0].name, 'Named.');
            Assert.areEqual(1, preview.withTheirOwn.size(), 'Ana has her own.');
            Assert.areEqual(ana.Id, preview.withTheirOwn[0].id, 'Ana.');
            Assert.areEqual(HOME_STREET, mailingStreetOf(ana.Id), 'Ticked, so Ana moves.');
        }
    }

    @IsTest
    static void aMoveLeavesOutTheDeceasedAndTellsApartPeopleWithOneName() {
        System.runAs(TestUsers.admin()) {
            Account ortiz = household('The Ortiz Family');
            Database.insert(ortiz, AccessLevel.SYSTEM_MODE);
            Contact andre = AddressTestDataFactory.newContact('Andre', 'Ortiz', ortiz.Id);
            Contact omarSenior = AddressTestDataFactory.newContact('Omar', 'Ortiz', ortiz.Id);
            Contact omarBorn = AddressTestDataFactory.newContact('Omar', 'Ortiz', ortiz.Id);
            Contact omarEmail = AddressTestDataFactory.newContact('Omar', 'Ortiz', ortiz.Id);
            omarSenior.Deceased__c = true;
            omarBorn.Birthdate = Date.newInstance(1980, 3, 4);
            omarEmail.Email = 'omar.ortiz@example.org';
            // Saved past an org duplicate rule that only alerts: the Omars share a name on purpose.
            Database.DMLOptions allowDuplicates = new Database.DMLOptions();
            allowDuplicates.DuplicateRuleHeader.AllowSave = true;
            Database.insert(
                new List<Contact>{ andre, omarSenior, omarBorn, omarEmail },
                allowDuplicates,
                AccessLevel.USER_MODE
            );
            Address__c andresOwn = ownAddress(andre.Id);
            insert andresOwn;

            Test.startTest();
            AddressMoveController.MovePreview preview = AddressMoveController.getMovePreview(
                ortiz.Id
            );
            AddressMoveController.useForWholeHousehold(andresOwn.Id, ortiz.Id);
            Test.stopTest();

            Set<String> moving = new Set<String>();
            Set<Id> listed = new Set<Id>();
            for (AddressMoveController.Choice choice : preview.moving) {
                moving.add(choice.name);
                listed.add(choice.id);
            }
            for (AddressMoveController.Choice choice : preview.withTheirOwn) {
                listed.add(choice.id);
            }
            Assert.isFalse(listed.contains(omarSenior.Id), 'The deceased Omar is not listed.');
            Assert.areEqual(
                new Set<String>{
                    String.format(
                        System.Label.Core_Address_SameNameBorn,
                        new List<Object>{ 'Omar Ortiz', omarBorn.Birthdate.format() }
                    ),
                    String.format(
                        System.Label.Core_Address_SameNameEmail,
                        new List<Object>{ 'Omar Ortiz', 'omar.ortiz@example.org' }
                    )
                },
                moving,
                'Each living Omar is told apart; Andre has his own address.'
            );
            Assert.areEqual(OWN_STREET, mailingStreetOf(omarBorn.Id), 'The living move.');
            Assert.areNotEqual(
                OWN_STREET,
                mailingStreetOf(omarSenior.Id),
                'The deceased keeps the address on their record.'
            );
        }
    }

    @IsTest
    static void useForWholeHouseholdMovesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            Account garcia = household('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            Address__c anasOwn = ownAddress(ana.Id);
            insert anasOwn;

            Test.startTest();
            AddressMoveController.useForWholeHousehold(anasOwn.Id, garcia.Id);
            Test.stopTest();

            Assert.areEqual(
                OWN_STREET,
                [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id].BillingStreet,
                'The household moved to Ana\'s address.'
            );
        }
    }

    @IsTest
    static void aRefusalTheCardCanShowPassesThrough() {
        System.runAs(TestUsers.admin()) {
            Account empty = AddressTestDataFactory.newHousehold('The Empty Family');
            Database.insert(empty, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            String message;
            try {
                AddressMoveController.updateEveryonesAddress(empty.Id, null);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(System.Label.Core_Address_MoveNoPrimary, message, 'As it is.');
        }
    }

    @IsTest
    static void aUserWhoMayNotEditIsToldInPlainWordsAndNothingChanges() {
        User reader = TestUsers.peopleReaderWith(
            'MoveCardReader',
            new List<String>{ 'BarnCRM_Read_Only' }
        );
        Account garcia;
        Contact luis;
        Address__c anasOwn;
        System.runAs(TestUsers.admin()) {
            garcia = household('The Garcia Family');
            Database.insert(garcia, AccessLevel.SYSTEM_MODE);
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert new List<Contact>{ ana, luis };
            anasOwn = ownAddress(ana.Id);
            insert anasOwn;
        }

        Test.startTest();
        List<String> messages = new List<String>();
        System.runAs(reader) {
            try {
                AddressMoveController.updateEveryonesAddress(garcia.Id, null);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
            try {
                AddressMoveController.useForWholeHousehold(anasOwn.Id, garcia.Id);
            } catch (AuraHandledException refused) {
                messages.add(refused.getMessage());
            }
        }
        Test.stopTest();

        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                new List<String>{
                    System.Label.Core_Address_MoveFailed,
                    System.Label.Core_Address_MoveFailed
                },
                messages,
                'Both are refused in plain words.'
            );
            Assert.isNull(mailingStreetOf(luis.Id), 'Luis did not move.');
            Assert.areEqual(
                HOME_STREET,
                [SELECT BillingStreet FROM Account WHERE Id = :garcia.Id].BillingStreet,
                'Nor did the household.'
            );
        }
    }

    private static Account household(String name) {
        Account record = AddressTestDataFactory.newHousehold(name);
        record.BillingStreet = HOME_STREET;
        return record;
    }

    private static Address__c ownAddress(Id contactId) {
        return new Address__c(
            Contact__c = contactId,
            Type__c = 'Home',
            Street__c = OWN_STREET,
            Is_Default__c = true
        );
    }

    private static String mailingStreetOf(Id contactId) {
        return [SELECT MailingStreet FROM Contact WHERE Id = :contactId].MailingStreet;
    }
}
