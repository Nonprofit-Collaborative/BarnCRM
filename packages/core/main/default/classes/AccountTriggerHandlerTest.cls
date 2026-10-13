/**
 * The household upkeep that happens when a household itself is saved or changed.
 */
@IsTest
private class AccountTriggerHandlerTest {
    @IsTest
    static void aHouseholdSavedWithNoNameGetsAPlaceholder() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            Account household = new Account(
                RecordTypeId = HouseholdService.householdRecordTypeId()
            );
            insert household;
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_NamePlaceholder,
                [SELECT Name FROM Account WHERE Id = :household.Id].Name,
                'An empty household is never saved without a name'
            );
        }
    }

    @IsTest
    static void clearingTheCustomNameBoxRenamesTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold(
                'The Reverend and Mrs. Smith'
            );
            household.Custom_Name__c = true;
            insert household;
            insert new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );

            Test.startTest();
            update new Account(Id = household.Id, Custom_Name__c = false);
            Test.stopTest();

            Assert.areEqual(
                'The Smith Family',
                [SELECT Name FROM Account WHERE Id = :household.Id].Name,
                'The household goes back to being named from the pattern'
            );
        }
    }

    @IsTest
    static void clearingTheCustomNameBoxLeavesANativeHouseholdAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold(
                'Name kept by Nonprofit Cloud'
            );
            household.Custom_Name__c = true;
            insert household;
            insert new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id
            );
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ household.Id };

            Test.startTest();
            update new Account(Id = household.Id, Custom_Name__c = false);
            Test.stopTest();

            Assert.areEqual(
                'Name kept by Nonprofit Cloud',
                [SELECT Name FROM Account WHERE Id = :household.Id].Name,
                'A household Nonprofit Cloud manages is never renamed, even once its custom name is released'
            );
        }
    }

    @IsTest
    static void checkingTheCustomNameBoxLeavesTheWordingAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :john.Id].AccountId;

            Test.startTest();
            update new Account(
                Id = household,
                Custom_Name__c = true,
                Name = 'The Reverend and Mrs. Smith'
            );
            Test.stopTest();

            Assert.areEqual(
                'The Reverend and Mrs. Smith',
                [SELECT Name FROM Account WHERE Id = :household].Name,
                'David keeps his wording'
            );
        }
    }

    @IsTest
    static void anOrganizationIsNeverRenamed() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            Account organization = new Account(Name = 'Riverside Community Trust');
            insert organization;
            update new Account(Id = organization.Id, Custom_Name__c = false);
            Test.stopTest();

            Assert.areEqual(
                'Riverside Community Trust',
                [SELECT Name FROM Account WHERE Id = :organization.Id].Name,
                'Household naming never touches an organization'
            );
        }
    }

    /**
     * The negative half of R-H2. Automatic creation being off has to be the only thing
     * stopping the household from being made, so two identical people are saved: one with
     * the setting off and one with it on. Without the person overrides an account is not
     * read as a person at all on a Platform only org (ADR-0013), and an empty result would
     * prove nothing.
     *
     * The setting is Auto_Create_Households__c, the same one a person stored as a contact
     * is given a household by. The separate person account setting this test used to read
     * is retired (ADR-0037).
     */
    @IsTest
    static void householdsForPeopleStoredAsAccountsFollowTheOneCreationSetting() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Auto_Create_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            HouseholdService.personAccountOverride = true;
            PersonRecordSelector.personRecordOverride = true;
            PersonRecordSelector.personOverridesByName = new Map<String, HouseholdService.Person>{
                'Maria Garcia' => HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head'),
                'Wei Lee' => HouseholdTestDataFactory.person('Mr.', 'Wei', 'Lee', 'Head')
            };

            Test.startTest();
            insert new Account(Name = 'Maria Garcia');
            Integer whileTheSettingIsOff = [SELECT COUNT() FROM Household_Member__c];
            settings.Auto_Create_Households__c = true;
            HouseholdTestDataFactory.save(settings);
            insert new Account(Name = 'Wei Lee');
            Test.stopTest();

            Assert.areEqual(0, whileTheSettingIsOff, 'The setting is off, so nothing was created');
            List<Household_Member__c> memberships = [SELECT Account__c FROM Household_Member__c];
            Assert.areEqual(
                1,
                memberships.size(),
                'And the person saved with the setting on is joined to a household, so the setting is the only reason the first one was not'
            );
            Id memberId = memberships[0].Account__c;
            Assert.areEqual(
                'Wei Lee',
                [SELECT Name FROM Account WHERE Id = :memberId].Name,
                'The membership belongs to the person saved after the setting was turned on'
            );
        }
    }

    /**
     * The shipped configuration of a Nonprofit Cloud org: junction membership, automatic
     * creation on, and nothing else asked for. This is the defect ADR-0037 closes, so it is
     * asserted from the setup an administrator actually arrives at.
     */
    @IsTest
    static void aPersonStoredAsAnAccountGetsAHouseholdOnTheShippedSettings() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            HouseholdService.personAccountOverride = true;
            PersonRecordSelector.personRecordOverride = true;
            // The org running this test may have no person name fields at all, so the test
            // declares the person these details belong to.
            PersonRecordSelector.personOverridesByName = new Map<String, HouseholdService.Person>{
                'Maria Garcia' => HouseholdTestDataFactory.person('Ms.', 'Maria', 'Garcia', 'Head')
            };

            Test.startTest();
            insert new Account(Name = 'Maria Garcia');
            Test.stopTest();

            List<Household_Member__c> memberships = [
                SELECT
                    Household__c,
                    Account__c,
                    Role__c,
                    Is_Primary__c,
                    Household__r.Name,
                    Household__r.Member_Count__c,
                    Household__r.RecordTypeId
                FROM Household_Member__c
            ];
            Assert.areEqual(1, memberships.size(), 'Maria was joined to a household');
            Assert.areEqual(
                HouseholdService.householdRecordTypeId(),
                memberships[0].Household__r.RecordTypeId,
                'The household is a household'
            );
            Assert.areEqual(
                'The Garcia Family',
                memberships[0].Household__r.Name,
                'And it is named from her surname'
            );
            Assert.areEqual(1, memberships[0].Household__r.Member_Count__c, 'And counts her');
            Assert.areEqual('Head', memberships[0].Role__c, 'She heads her own household');
            Assert.isTrue(memberships[0].Is_Primary__c, 'And is its primary member');
        }
    }

    /**
     * The households a person stored as an account belongs to, when they are deleted,
     * restored, or changed in a way the wording is built from.
     *
     * These four tests set `HouseholdService.personAccountOverride` and
     * `PersonRecordSelector.personRecordOverride`, because an org without person accounts
     * cannot hold a real one and the paths under test are the ones that only run there.
     * They do not use `PersonRecordSelector.personOverridesByName`, which is the stronger
     * of the two stand-ins: nothing here is asserted from a person's declared first name
     * or surname. The membership row, the member count, the tidying away and the rewriting
     * of the household's wording are all real behaviour of the real records.
     */
    @IsTest
    static void deletingAPersonStoredAsAnAccountSettlesTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account person = personInAHousehold();
            Decimal whileSheWasThere = [
                SELECT Member_Count__c
                FROM Account
                WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            ]
            .Member_Count__c;

            Test.startTest();
            delete person;
            Test.stopTest();

            Assert.areEqual(1, whileSheWasThere, 'Maria was counted while she was a member');
            Assert.areEqual(
                0,
                [
                    SELECT Member_Count__c
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ]
                .Member_Count__c,
                'The household is recounted when she is deleted'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'And her membership goes with her rather than being left naming nobody'
            );
        }
    }

    @IsTest
    static void deletingTheLastPersonStoredAsAnAccountTidiesTheHouseholdAway() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            Account person = personInAHousehold();

            Test.startTest();
            delete person;
            Test.stopTest();

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ],
                'The household nobody is left in is tidied away, as it is when a contact leaves'
            );
        }
    }

    /**
     * The half the platform cannot do for us. A membership row left to the platform comes
     * out of the person's deletion with its person lookup emptied and is never filled in
     * again, so the row has to be taken away with the person and brought back with them.
     */
    @IsTest
    static void restoringAPersonStoredAsAnAccountPutsThemBackInTheirHousehold() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account person = personInAHousehold();
            delete person;

            Test.startTest();
            undelete person;
            Test.stopTest();

            List<Household_Member__c> back = [SELECT Account__c FROM Household_Member__c];
            Assert.areEqual(1, back.size(), 'Her membership came back with her');
            Assert.areEqual(person.Id, back[0].Account__c, 'And it still names her');
            Assert.areEqual(
                1,
                [
                    SELECT Member_Count__c
                    FROM Account
                    WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
                ]
                .Member_Count__c,
                'And the household counts her again'
            );
        }
    }

    /**
     * R-H11 and R-H4 for a person stored as an account: marking somebody deceased is one of
     * the things the household's wording is built from, so the wording is rewritten. The
     * stale name is stamped on first, so that a household left alone would keep it.
     */
    @IsTest
    static void markingAPersonStoredAsAnAccountDeceasedRewritesTheirHouseholdWording() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Account person = personInAHousehold();
            Id householdId = [
                SELECT Id
                FROM Account
                WHERE RecordTypeId = :HouseholdService.householdRecordTypeId()
            ]
            .Id;
            update new Account(Id = householdId, Name = 'Stale Name');
            String beforeTheChange = [SELECT Name FROM Account WHERE Id = :householdId].Name;

            Test.startTest();
            update new Account(Id = person.Id, Deceased__c = true);
            Test.stopTest();

            Assert.areEqual(
                'Stale Name',
                beforeTheChange,
                'Renaming the household itself is not a membership change, so the wording stood'
            );
            Assert.areEqual(
                Label.Core_Households_NamePlaceholder,
                [SELECT Name FROM Account WHERE Id = :householdId].Name,
                'Marking her deceased rewrites the household wording from its members again'
            );
        }
    }

    /**
     * One person, held as an account, joined to one household. The two overrides are what
     * lets an org with no person accounts run the person account path at all.
     *
     * The membership is built by hand, so automatic creation is switched off first, as
     * `HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds` does for the
     * contact tests. Left on, it would give Maria a household of her own as well, and,
     * because the record override declares every account a person, the household too.
     */
    private static Account personInAHousehold() {
        BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
        settings.Auto_Create_Households__c = false;
        HouseholdTestDataFactory.save(settings);
        HouseholdService.personAccountOverride = true;
        PersonRecordSelector.personRecordOverride = true;
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Account person = new Account(Name = 'Maria Garcia');
        insert person;
        insert new Household_Member__c(
            Household__c = household.Id,
            Account__c = person.Id,
            Is_Primary__c = true
        );
        return person;
    }
}
