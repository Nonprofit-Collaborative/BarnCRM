/**
 * Address history (AH1, canonical model R-AD10): a move ends the primary it replaces and starts
 * the new one, on every path that adds a new primary (the card, a captured standard address,
 * Use for Whole Household, Update Everyone's Address), while choosing an address already on
 * file, the seasonal swap and the promotion after a delete end nothing. Undeliverable is only
 * ever a person's, a Former address is not put back in use on its own, the card's extra fields
 * follow the Address Card Fields setting, and every write runs as the user except the three
 * history fields BarnCRM keeps itself, so a save never fails for want of access to them.
 */
@IsTest(
    testFor='ApexClass:AddressService, ApexClass:AddressTriggerHandler, ApexClass:SeasonalAddressService, ApexClass:AddressMoveController'
)
private class AddressHistoryTest {
    @TestSetup
    static void createTestUser() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            TestUsers.admin();
        }
    }

    private static final String HOME_STREET = '6830 Sunset Lane';
    private static final String NEW_STREET = '1912 North Third Street';
    private static final String WINTER_STREET = '4120 East Camelback Road';
    /** A day inside the winter season below, and one outside it. */
    private static final Date IN_SEASON = Date.newInstance(2027, 1, 15);
    private static final Date OUT_OF_SEASON = Date.newInstance(2027, 5, 15);

    // ------------------------------------------------------------ moves

    @IsTest
    static void aNewPrimaryAddedOnTheCardEndsTheOldOneAndStartsTheNew() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;

            Test.startTest();
            Address__c moved = newPrimary(garcia.Id, NEW_STREET);
            insert moved;
            Test.stopTest();

            Address__c old = addressAt(garcia.Id, HOME_STREET);
            Assert.isFalse(old.Is_Default__c, 'The old address is no longer the primary.');
            Assert.areEqual('Former', old.Status__c, 'The old address is Former.');
            Assert.areEqual(Date.today(), old.End_Date__c, 'It ended today.');
            Address__c now = addressAt(garcia.Id, NEW_STREET);
            Assert.areEqual('Current', now.Status__c, 'The new address is Current.');
            Assert.areEqual(Date.today(), now.Start_Date__c, 'It started today.');
            Assert.isNull(now.End_Date__c, 'It has not ended.');
        }
    }

    @IsTest
    static void twoHundredHouseholdsMovingInOneSaveAreEachEnded() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = new List<Account>();
            for (Integer index = 0; index < 200; index++) {
                households.add(householdAtHome('The Family ' + index));
            }
            insert households;
            List<Address__c> moves = new List<Address__c>();
            for (Account household : households) {
                moves.add(newPrimary(household.Id, NEW_STREET));
            }

            Test.startTest();
            insert moves;
            Test.stopTest();

            Assert.areEqual(
                200,
                [
                    SELECT COUNT()
                    FROM Address__c
                    WHERE Street__c = :HOME_STREET AND Status__c = 'Former' AND End_Date__c = TODAY
                ],
                'Every old address is ended.'
            );
        }
    }

    @IsTest
    static void aNewPrimaryAtTheSameAddressIsNotAMove() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;

            Address__c home = [
                SELECT Street__c, City__c, State__c, Postal_Code__c, Country__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
            ];
            Address__c same = newPrimary(garcia.Id, home.Street__c);
            same.City__c = home.City__c;
            same.State__c = home.State__c;
            same.Postal_Code__c = home.Postal_Code__c;
            same.Country__c = home.Country__c;

            Test.startTest();
            insert same;
            Test.stopTest();

            for (Address__c address : [
                SELECT Status__c, Start_Date__c, End_Date__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
            ]) {
                Assert.areEqual('Current', address.Status__c, 'Nobody moved.');
                Assert.isNull(address.End_Date__c, 'Nothing ended.');
                Assert.isNull(address.Start_Date__c, 'Nothing started.');
            }
        }
    }

    @IsTest
    static void choosingAnAddressAlreadyOnFileAsPrimaryEndsNothing() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Address__c work = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Work',
                Street__c = NEW_STREET,
                Is_Default__c = false
            );
            insert work;

            Test.startTest();
            update new Address__c(Id = work.Id, Is_Default__c = true);
            Test.stopTest();

            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Assert.isFalse(home.Is_Default__c, 'The primary moved to the work address.');
            Assert.areEqual('Current', home.Status__c, 'Set as Primary is not a move.');
            Assert.isNull(home.End_Date__c, 'Nothing ended.');
            Assert.areEqual('Current', addressAt(garcia.Id, NEW_STREET).Status__c, 'Work too.');
        }
    }

    @IsTest
    static void aChangedMailingAddressCapturedForTheHouseholdEndsItsOldAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact luis = AddressTestDataFactory.newContact('Luis', 'Garcia', garcia.Id);
            insert luis;

            Test.startTest();
            update new Contact(Id = luis.Id, MailingStreet = NEW_STREET, MailingCity = 'Tucson');
            Test.stopTest();

            Address__c now = addressAt(garcia.Id, NEW_STREET);
            Assert.isTrue(now.Is_Default__c, 'Everyone in the household moves together.');
            Assert.areEqual(Date.today(), now.Start_Date__c, 'The new address started today.');
            Address__c old = addressAt(garcia.Id, HOME_STREET);
            Assert.areEqual('Former', old.Status__c, 'The old household address is Former.');
            Assert.areEqual(Date.today(), old.End_Date__c, 'It ended today.');
        }
    }

    @IsTest
    static void useForWholeHouseholdEndsTheHouseholdsOldAddressNotThePersonsOwn() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            Address__c anasOwn = new Address__c(
                Contact__c = ana.Id,
                Type__c = 'Home',
                Street__c = NEW_STREET,
                Is_Default__c = true
            );
            insert anasOwn;

            Test.startTest();
            AddressService.useForWholeHousehold(new Map<Id, Id>{ anasOwn.Id => garcia.Id });
            Test.stopTest();

            Address__c old = addressAt(garcia.Id, HOME_STREET);
            Assert.areEqual('Former', old.Status__c, 'The household left its old address.');
            Assert.areEqual(Date.today(), old.End_Date__c, 'It ended today.');
            Assert.areEqual(
                Date.today(),
                addressAt(garcia.Id, NEW_STREET).Start_Date__c,
                'The household started at Ana\'s address today.'
            );
            Address__c kept = [
                SELECT Is_Default__c, Status__c, End_Date__c
                FROM Address__c
                WHERE Id = :anasOwn.Id
            ];
            Assert.isFalse(kept.Is_Default__c, 'Ana follows the household again.');
            Assert.areEqual('Current', kept.Status__c, 'Ana still lives there: not a move.');
            Assert.isNull(kept.End_Date__c, 'Nothing ended for Ana.');
        }
    }

    @IsTest
    static void updateEveryonesAddressEndsATickedPersonsOwnAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Contact ana = AddressTestDataFactory.newContact('Ana', 'Garcia', garcia.Id);
            insert ana;
            Address__c anasOwn = new Address__c(
                Contact__c = ana.Id,
                Type__c = 'Home',
                Street__c = NEW_STREET,
                Is_Default__c = true
            );
            insert anasOwn;

            Test.startTest();
            AddressService.updateEveryonesAddress(
                new Map<Id, Set<Id>>{ garcia.Id => new Set<Id>{ ana.Id } }
            );
            Test.stopTest();

            Address__c ended = [
                SELECT Is_Default__c, Status__c, End_Date__c
                FROM Address__c
                WHERE Id = :anasOwn.Id
            ];
            Assert.isFalse(ended.Is_Default__c, 'Ana takes the household address.');
            Assert.areEqual('Former', ended.Status__c, 'Ana left her own address.');
            Assert.areEqual(Date.today(), ended.End_Date__c, 'It ended today.');
            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Assert.areEqual('Current', home.Status__c, 'The household did not move.');
            Assert.isNull(home.End_Date__c, 'Nothing ended for the household.');
        }
    }

    @IsTest
    static void aMoveKeepsAnUndeliverableStatusAndAnEndDateAPersonGave() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Date given = Date.today().addDays(-3);
            update new Address__c(Id = home.Id, Status__c = 'Undeliverable', End_Date__c = given);

            Test.startTest();
            insert newPrimary(garcia.Id, NEW_STREET);
            Test.stopTest();

            Address__c old = addressAt(garcia.Id, HOME_STREET);
            Assert.areEqual('Undeliverable', old.Status__c, 'Only a person changes Undeliverable.');
            Assert.areEqual(given, old.End_Date__c, 'The end date the person gave stays.');
        }
    }

    // ------------------------------------------------------------ the seasonal swap

    @IsTest
    static void theSeasonalSwapIsNotAMoveEitherWay() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            insert winterAddress(garcia.Id, null);

            Test.startTest();
            SeasonalAddressService.swapOwners(new Set<Id>{ garcia.Id }, IN_SEASON);
            Address__c inWinter = addressAt(garcia.Id, WINTER_STREET);
            SeasonalAddressService.swapOwners(new Set<Id>{ garcia.Id }, OUT_OF_SEASON);
            Test.stopTest();

            Assert.isTrue(inWinter.Is_Default__c, 'The winter address took over.');
            Assert.isTrue(addressAt(garcia.Id, HOME_STREET).Is_Default__c, 'Home came back.');
            for (Address__c address : [
                SELECT Status__c, Start_Date__c, End_Date__c
                FROM Address__c
                WHERE Account__c = :garcia.Id
            ]) {
                Assert.areEqual('Current', address.Status__c, 'The swap ends nothing.');
                Assert.isNull(address.End_Date__c, 'No end date.');
                Assert.isNull(address.Start_Date__c, 'No start date.');
            }
        }
    }

    @IsTest
    static void aFormerSeasonalAddressIsNotSwappedIn() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            insert winterAddress(garcia.Id, 'Former');

            Test.startTest();
            SeasonalAddressService.swapOwners(new Set<Id>{ garcia.Id }, IN_SEASON);
            Test.stopTest();

            Assert.isTrue(
                addressAt(garcia.Id, HOME_STREET).Is_Default__c,
                'The household no longer winters there, so home stays the primary.'
            );
        }
    }

    @IsTest
    static void aMoveDuringTheSeasonEndsTheHomeLeftNotTheSeasonalAddress() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            insert winterAddress(garcia.Id, null);
            SeasonalAddressService.swapOwners(new Set<Id>{ garcia.Id }, IN_SEASON);

            Test.startTest();
            insert newPrimary(garcia.Id, NEW_STREET);
            Test.stopTest();

            Address__c winter = addressAt(garcia.Id, WINTER_STREET);
            Assert.isFalse(winter.Is_Default__c, 'The new address is the primary.');
            Assert.areEqual('Current', winter.Status__c, 'They still winter there.');
            Assert.isNull(winter.End_Date__c, 'The winter address did not end.');
            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Assert.areEqual('Former', home.Status__c, 'The home they left is Former.');
            Assert.areEqual(Date.today(), home.End_Date__c, 'It ended today.');
        }
    }

    // ------------------------------------------------------------ Former addresses

    @IsTest
    static void aFormerAddressMadePrimaryIsCurrentAgain() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            insert newPrimary(garcia.Id, NEW_STREET);
            Address__c old = addressAt(garcia.Id, HOME_STREET);

            Test.startTest();
            update new Address__c(Id = old.Id, Is_Default__c = true);
            Test.stopTest();

            Address__c back = addressAt(garcia.Id, HOME_STREET);
            Assert.isTrue(back.Is_Default__c, 'They moved back.');
            Assert.areEqual('Current', back.Status__c, 'The primary is never Former.');
            Assert.isNull(back.End_Date__c, 'Its end date is cleared.');
            Assert.areEqual(
                'Current',
                addressAt(garcia.Id, NEW_STREET).Status__c,
                'Set as Primary ends nothing.'
            );
        }
    }

    @IsTest
    static void aDeletedPrimaryIsReplacedByACurrentAddressBeforeAFormerOne() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            Address__c work = new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Work',
                Street__c = '1 Office Park',
                Is_Default__c = false
            );
            insert work;
            insert new Address__c(
                Account__c = garcia.Id,
                Type__c = 'Home',
                Street__c = '3 Elm Street',
                Is_Default__c = false,
                Status__c = 'Former'
            );

            Test.startTest();
            delete addressAt(garcia.Id, HOME_STREET);
            Test.stopTest();

            Assert.isTrue(
                [SELECT Is_Default__c FROM Address__c WHERE Id = :work.Id].Is_Default__c,
                'The Current address is put in use, not the newer Former one.'
            );
        }
    }

    @IsTest
    static void anAddressSavedWithNoStatusIsCurrent() {
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;

            Test.startTest();
            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Test.stopTest();

            Assert.areEqual('Current', home.Status__c, 'A captured address is saved Current.');
        }
    }

    // ------------------------------------------------------------ permissions

    @IsTest
    static void staffMoveAHouseholdAsThemselves() {
        User sam;
        System.runAs(TestUsers.admin()) {
            sam = TestDataFactory.createUser('Sam', new List<String>{ 'BarnCRM_Staff' });
        }
        Account garcia = householdAtHome('The Garcia Family');

        Test.startTest();
        System.runAs(sam) {
            insert garcia;
            insert newPrimary(garcia.Id, NEW_STREET);
        }
        Test.stopTest();

        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                'Former',
                addressAt(garcia.Id, HOME_STREET).Status__c,
                'Staff hold edit on the history fields, so their move is recorded.'
            );
        }
    }

    @IsTest
    static void readOnlyUsersSeeTheStatusButCannotChangeIt() {
        Address__c home;
        System.runAs(TestUsers.admin()) {
            Account garcia = householdAtHome('The Garcia Family');
            insert garcia;
            home = addressAt(garcia.Id, HOME_STREET);
        }
        User rita;
        System.runAs(TestUsers.admin()) {
            rita = TestDataFactory.createUser('Rita', new List<String>{ 'BarnCRM_Read_Only' });
        }

        Test.startTest();
        Address__c seen;
        Boolean refused = false;
        System.runAs(rita) {
            seen = [SELECT Status__c FROM Address__c WHERE Id = :home.Id WITH USER_MODE];
            try {
                Database.update(
                    new Address__c(Id = home.Id, Status__c = 'Undeliverable'),
                    AccessLevel.USER_MODE
                );
            } catch (Exception expected) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.areEqual('Current', seen.Status__c, 'Read Only users can read the status.');
        Assert.isTrue(refused, 'Read Only users cannot mark an address Undeliverable.');
    }

    /**
     * Someone who may save addresses without access to the three history fields (a profile
     * that grants Address__c, and no BarnCRM permission set that gives the new fields) still
     * adds, edits and deletes addresses: BarnCRM keeps the history itself, so the save never
     * fails on those fields, and the move is still recorded.
     */
    @IsTest
    static void someoneWithoutAccessToTheHistoryFieldsStillSavesAddresses() {
        User pat;
        System.runAs(TestUsers.admin()) {
            pat = TestDataFactory.createUser('Pat', new List<String>{ 'BarnCRM_Staff' });
        }
        withoutHistoryFieldAccess('BarnCRM_Staff');
        Account garcia = householdAtHome('The Garcia Family');

        Test.startTest();
        Boolean canReadStatus;
        Address__c endedOnMove;
        System.runAs(pat) {
            canReadStatus = Schema.SObjectType.Address__c.fields.Status__c.isAccessible();
            insert garcia;
            Address__c moved = newPrimary(garcia.Id, NEW_STREET);
            insert moved;
            endedOnMove = addressAt(garcia.Id, HOME_STREET);
            update new Address__c(Id = moved.Id, City__c = 'Phoenix');
            delete new Address__c(Id = moved.Id);
        }
        Test.stopTest();

        Assert.isFalse(canReadStatus, 'The person cannot read the status: the case under test.');
        Assert.isFalse(endedOnMove.Is_Default__c, 'The move took the old primary out of use.');
        Assert.areEqual('Former', endedOnMove.Status__c, 'BarnCRM still ended the old address.');
        Assert.areEqual(Date.today(), endedOnMove.End_Date__c, 'It ended on the day of the move.');
        System.runAs(TestUsers.admin()) {
            Address__c home = addressAt(garcia.Id, HOME_STREET);
            Assert.isTrue(home.Is_Default__c, 'Deleting the new primary put the old one back.');
            Assert.areEqual('Current', home.Status__c, 'Back in use, it is Current again.');
            Assert.isNull(home.End_Date__c, 'Its end date is cleared.');
        }
        Assert.isNull(AddressSelector.withHistory(null), 'Nothing in, nothing out.');
    }

    // ------------------------------------------------------------ Address Card Fields

    @IsTest
    static void theCardShowsTheChosenFieldsItDoesNotAlreadyShowOnce() {
        String verification = Address__c.Verification_Status__c.getDescribe().getName();
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Address_Card_Fields__c =
                verification +
                ', Street__c, Not_A_Field__c, ' +
                verification.toLowerCase() +
                ',Name';
            upsert settings;
            SettingsService.clearCaches();
        }
        User rita;
        System.runAs(TestUsers.admin()) {
            rita = TestDataFactory.createUser('Rita', new List<String>{ 'BarnCRM_Read_Only' });
        }

        Test.startTest();
        List<AddressMoveController.CardField> fields;
        System.runAs(rita) {
            fields = AddressMoveController.getCardFields();
        }
        Test.stopTest();

        Assert.areEqual(2, fields.size(), 'Each new field once, in the order saved: ' + fields);
        Assert.areEqual(verification, fields[0].apiName, 'The verification status first.');
        Assert.isNotNull(fields[0].label, 'With the label the card shows.');
        Assert.areEqual('Name', fields[1].apiName, 'Then the address number.');
    }

    @IsTest
    static void theCardShowsNoExtraFieldsWhenNoneAreChosen() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            List<AddressMoveController.CardField> fields = AddressMoveController.getCardFields();
            Test.stopTest();

            Assert.isTrue(fields.isEmpty(), 'Nothing ticked shows only the usual fields.');
        }
    }

    // ------------------------------------------------------------ helpers

    /**
     * Takes Status, Start Date and End Date out of a permission set, for this test only (a
     * test's setup changes are rolled back): the access of someone given Address__c without
     * the new fields. Written in its own context, apart from the records the test saves.
     */
    private static void withoutHistoryFieldAccess(String permissionSetName) {
        String objectName = Address__c.SObjectType.getDescribe().getName();
        List<String> fields = new List<String>();
        for (
            Schema.SObjectField token : new List<Schema.SObjectField>{
                Address__c.Status__c,
                Address__c.Start_Date__c,
                Address__c.End_Date__c
            }
        ) {
            fields.add(objectName + '.' + token.getDescribe().getName());
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            delete [
                SELECT Id
                FROM FieldPermissions
                WHERE Parent.Name = :permissionSetName AND Field IN :fields
            ];
        }
    }

    private static Account householdAtHome(String name) {
        Account household = AddressTestDataFactory.newHousehold(name);
        household.BillingStreet = HOME_STREET;
        household.BillingCity = 'Springfield';
        return household;
    }

    private static Address__c newPrimary(Id householdId, String street) {
        return new Address__c(
            Account__c = householdId,
            Type__c = 'Home',
            Street__c = street,
            City__c = 'Tucson',
            Is_Default__c = true
        );
    }

    /** A winter address from November 1 to March 31, not the primary. */
    private static Address__c winterAddress(Id householdId, String status) {
        return new Address__c(
            Account__c = householdId,
            Type__c = 'Seasonal',
            Street__c = WINTER_STREET,
            City__c = 'Phoenix',
            Is_Default__c = false,
            Seasonal_Start_Month__c = 11,
            Seasonal_Start_Day__c = 1,
            Seasonal_End_Month__c = 3,
            Seasonal_End_Day__c = 31,
            Status__c = status
        );
    }

    private static Address__c addressAt(Id householdId, String street) {
        return [
            SELECT Id, Is_Default__c, Status__c, Start_Date__c, End_Date__c
            FROM Address__c
            WHERE Account__c = :householdId AND Street__c = :street
            LIMIT 1
        ];
    }
}
