/**
 * The household's Primary Contact and the member marked primary (R-M3, R-H10, ADR-0044
 * primary contact mirrors the primary member).
 *
 * In junction mode the field mirrors the membership marked Is Primary on every path that
 * changes it, a person stored as an account is named by their person contact, and a hand
 * edit is refused. In contact mode the field stays the mark people set.
 */
@IsTest(testFor='ApexClass:HouseholdMergeService, ApexClass:HouseholdService')
private class HouseholdPrimaryContactTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Account household(String name) {
        Account record = HouseholdTestDataFactory.newHousehold(name);
        insert record;
        return record;
    }

    private static Household_Member__c membership(
        Id householdId,
        Id personId,
        String role,
        Boolean isPrimary
    ) {
        Household_Member__c record = new Household_Member__c(
            Household__c = householdId,
            Role__c = role,
            Is_Primary__c = isPrimary,
            Start_Date__c = Date.today()
        );
        if (personId.getSObjectType() == Contact.SObjectType) {
            record.Contact__c = personId;
        } else {
            record.Account__c = personId;
        }
        return record;
    }

    private static Id primaryContactOf(Id householdId) {
        return [SELECT Primary_Contact__c FROM Account WHERE Id = :householdId].Primary_Contact__c;
    }

    @IsTest
    static void thePrimaryMemberIsMirroredWhenTheMembershipIsSaved() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };

            Test.startTest();
            insert new List<Household_Member__c>{
                membership(smiths.Id, john.Id, 'Head', false),
                membership(smiths.Id, jane.Id, 'Spouse or Partner', true)
            };
            Test.stopTest();

            Assert.areEqual(jane.Id, primaryContactOf(smiths.Id), 'Jane is marked primary (R-M3)');
        }
    }

    @IsTest
    static void thePrimaryContactFollowsWhenAnotherMemberIsMadePrimary() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            insert new List<Household_Member__c>{
                membership(smiths.Id, john.Id, 'Head', true),
                membership(smiths.Id, jane.Id, 'Spouse or Partner', false)
            };
            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'John starts as primary');

            Test.startTest();
            HouseholdOfPersonController.makePrimary(smiths.Id, jane.Id);
            Test.stopTest();

            Assert.areEqual(jane.Id, primaryContactOf(smiths.Id), 'The field follows Make primary');
        }
    }

    @IsTest
    static void endingThePrimaryMembershipClearsThePrimaryContactAndPromotesNobody() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            Household_Member__c johns = membership(smiths.Id, john.Id, 'Head', true);
            insert new List<Household_Member__c>{
                johns,
                membership(smiths.Id, jane.Id, 'Spouse or Partner', false)
            };

            Test.startTest();
            update new Household_Member__c(Id = johns.Id, End_Date__c = Date.today());
            Test.stopTest();

            Assert.isNull(
                primaryContactOf(smiths.Id),
                'John has left, and Jane is proposed rather than assigned (R-H10)'
            );
        }
    }

    @IsTest
    static void deletingAndRestoringThePrimaryMembershipClearsAndRestoresTheField() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            Household_Member__c johns = membership(smiths.Id, john.Id, 'Head', true);
            insert new List<Household_Member__c>{
                johns,
                membership(smiths.Id, jane.Id, 'Spouse or Partner', false)
            };

            Test.startTest();
            delete new Household_Member__c(Id = johns.Id);
            Id afterDelete = primaryContactOf(smiths.Id);
            undelete new Household_Member__c(Id = johns.Id);
            Test.stopTest();

            Assert.isNull(afterDelete, 'The primary membership is gone, so is the field');
            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'Restored with the membership');
        }
    }

    /**
     * A person stored as an account is named by the contact the platform keeps behind that
     * account. The overrides stand in for an org with person accounts, so this holds on
     * every org shape; the test below proves the same on a real one where the org has them.
     */
    @IsTest
    static void aPrimaryPersonAccountIsMirroredAsItsPersonContact() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            HouseholdService.personAccountOverride = true;
            Account garcias = household('The Garcia Family');
            Account maria = new Account(Name = 'Maria Garcia');
            insert maria;
            Contact behindMaria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert behindMaria;
            PersonRecordSelector.personContactIdOverride = new Map<Id, Id>{
                maria.Id => behindMaria.Id
            };

            Test.startTest();
            insert membership(garcias.Id, maria.Id, 'Head', true);
            Test.stopTest();

            Assert.areEqual(
                behindMaria.Id,
                primaryContactOf(garcias.Id),
                'The person account is named by its person contact (R-M3)'
            );
        }
    }

    @IsTest
    static void aRealPersonAccountIsItsNewHouseholdsPrimaryContact() {
        System.runAs(TestUsers.admin()) {
            if (PersonAccountTestShape.skipReason() != null) {
                // Proven on every shape by the test above; this one needs real person accounts,
                // of a record type the running user is given. The reason is checked and logged.
                return;
            }
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_JUNCTION
            );
            // Kept when emptied, so the household is still there for the person to come back to.
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            SObject person = Account.SObjectType.newSObject();
            person.put('RecordTypeId', personType);
            person.put('LastName', 'Okafor');
            person.put('FirstName', 'Ada');

            Test.startTest();
            insert person;
            Household_Member__c joined = [
                SELECT Household__c, Is_Primary__c
                FROM Household_Member__c
                WHERE Account__c = :person.Id
            ];
            Id personContactId = (Id) Database.queryWithBinds(
                    'SELECT PersonContactId FROM Account WHERE Id = :personId',
                    new Map<String, Object>{ 'personId' => person.Id },
                    AccessLevel.SYSTEM_MODE
                )[0]
                .get('PersonContactId');
            Id created = primaryContactOf(joined.Household__c);
            delete person;
            Id afterDelete = primaryContactOf(joined.Household__c);
            undelete person;
            Test.stopTest();

            Assert.isTrue(joined.Is_Primary__c, 'The new person is their household primary (R-H2)');
            Assert.areEqual(personContactId, created, 'Named by their person contact (R-M3)');
            Assert.isNull(afterDelete, 'Deleting the person empties the field');
            Assert.areEqual(
                personContactId,
                primaryContactOf(joined.Household__c),
                'Restoring the person restores their membership and the field with it'
            );
        }
    }

    /**
     * The bulk path (ADR-NEXT): a save of many rows, as a data load makes, is let through
     * with two primaries, and settled the existing way.
     */
    @IsTest
    static void withTwoPrimariesTheFirstInMemberOrderIsMirroredAndTheRowsAreLeftAlone() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };

            Test.startTest();
            insert new List<Household_Member__c>{
                membership(smiths.Id, jane.Id, 'Spouse or Partner', true),
                membership(smiths.Id, john.Id, 'Head', true)
            };
            Test.stopTest();

            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'Head comes first (R-H5)');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Household_Member__c WHERE Is_Primary__c = TRUE],
                'Which of the two is right is a decision somebody makes, so no row is changed'
            );
        }
    }

    /**
     * R-M3, ADR-NEXT: one person's save that adds a second current primary to a household is
     * refused, with a message pointing to Make primary.
     */
    @IsTest
    static void aSingleSaveAddingASecondPrimaryIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            insert membership(smiths.Id, john.Id, 'Head', true);

            Test.startTest();
            Database.SaveResult result = Database.insert(
                membership(smiths.Id, jane.Id, 'Spouse or Partner', true),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'A second primary is refused');
            Assert.areEqual(
                Label.Core_Households_ErrorSecondPrimary,
                result.getErrors()[0].getMessage(),
                'The refusal says where to make the change instead'
            );
            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'John is still the primary');
        }
    }

    /**
     * R-M3, ADR-NEXT: ticking Is Primary on a second member by hand is refused the same way,
     * and ticking it where nobody else holds it is allowed.
     */
    @IsTest
    static void markingASecondMemberPrimaryByHandIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            Household_Member__c johns = membership(smiths.Id, john.Id, 'Head', false);
            Household_Member__c janes = membership(smiths.Id, jane.Id, 'Spouse or Partner', false);
            insert new List<Household_Member__c>{ johns, janes };

            Test.startTest();
            update new Household_Member__c(Id = johns.Id, Is_Primary__c = true);
            Database.SaveResult result = Database.update(
                new Household_Member__c(Id = janes.Id, Is_Primary__c = true),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Jane cannot be made a second primary by hand');
            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'John became the primary');
        }
    }

    /**
     * R-M3, ADR-NEXT: an ended primary does not count, so a new primary is allowed.
     */
    @IsTest
    static void anEndedPrimaryDoesNotBlockANewOne() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            Household_Member__c johns = membership(smiths.Id, john.Id, 'Head', true);
            johns.Start_Date__c = Date.today().addYears(-2);
            johns.End_Date__c = Date.today().addDays(-1);
            insert johns;

            Test.startTest();
            insert membership(smiths.Id, jane.Id, 'Spouse or Partner', true);
            Test.stopTest();

            Assert.areEqual(jane.Id, primaryContactOf(smiths.Id), 'Jane is the primary now');
        }
    }

    /**
     * ADR-NEXT: one row arriving through a load (the APIs, the Bulk API, background Apex) is
     * let through as before, so an import never newly fails.
     */
    @IsTest
    static void aSecondPrimaryArrivingThroughALoadIsLetThrough() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            insert membership(smiths.Id, john.Id, 'Head', true);

            Test.startTest();
            HouseholdMemberTriggerHandler.quiddityOverride = Quiddity.BULK_API;
            insert membership(smiths.Id, jane.Id, 'Spouse or Partner', true);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Household_Member__c WHERE Is_Primary__c = TRUE],
                'The loaded row is saved as it came'
            );
            Assert.areEqual(john.Id, primaryContactOf(smiths.Id), 'Head comes first (R-H5)');
        }
    }

    @IsTest
    static void aHandEditOfAHouseholdsPrimaryContactIsRefusedInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            insert john;

            Test.startTest();
            Database.SaveResult result = Database.update(
                new Account(Id = smiths.Id, Primary_Contact__c = john.Id),
                false
            );
            Test.stopTest();

            Assert.isFalse(result.isSuccess(), 'Only HouseholdService writes the mirror');
            Assert.areEqual(
                Label.Core_Households_PrimaryContactFollowsMembers,
                result.getErrors()[0].getMessage(),
                'The refusal says where to make the change instead'
            );
        }
    }

    @IsTest
    static void anOrganizationsPrimaryContactIsSetByHandInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account shelter = new Account(Name = 'Riverside Shelter');
            insert shelter;
            Contact ada = HouseholdTestDataFactory.newContact('Ms.', 'Ada', 'Nkosi');
            insert ada;

            Test.startTest();
            update new Account(Id = shelter.Id, Primary_Contact__c = ada.Id);
            Test.stopTest();

            Assert.areEqual(
                ada.Id,
                primaryContactOf(shelter.Id),
                'R-O3: not a mirror on an organization'
            );
        }
    }

    @IsTest
    static void aHouseholdsPrimaryContactIsSetByHandInContactMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account smiths = household('The Smith Family');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            john.AccountId = smiths.Id;
            insert john;

            Test.startTest();
            update new Account(Id = smiths.Id, Primary_Contact__c = john.Id);
            Test.stopTest();

            Assert.areEqual(
                john.Id,
                primaryContactOf(smiths.Id),
                'In contact mode the field is the mark'
            );
        }
    }

    @IsTest
    static void aMergeInJunctionModeMirrorsThePrimaryItCarriesAndOffersNoChoiceAboutIt() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            Account survivor = household('The Smith Family');
            Account other = household('Smith Household');
            Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
            Contact jane = HouseholdTestDataFactory.newContact('Mrs.', 'Jane', 'Smith');
            insert new List<Contact>{ john, jane };
            insert new List<Household_Member__c>{
                membership(survivor.Id, john.Id, 'Head', false),
                membership(other.Id, jane.Id, 'Spouse or Partner', true)
            };

            Test.startTest();
            HouseholdMergeService.MergePreview preview = HouseholdMergeService.preview(
                survivor.Id,
                other.Id
            );
            HouseholdMergeService.mergeHouseholds(
                survivor.Id,
                other.Id,
                new HouseholdMergeService.MergeChoices(null)
            );
            Test.stopTest();

            for (HouseholdMergeService.FieldChoice choice : preview.fields) {
                Assert.areNotEqual(
                    'Primary_Contact__c',
                    choice.fieldName,
                    'The membership rows decide the primary in junction mode'
                );
            }
            Assert.areEqual(
                jane.Id,
                primaryContactOf(survivor.Id),
                'The survivor had no primary, so Jane keeps the flag and the field follows'
            );
        }
    }
}
