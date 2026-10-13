/**
 * What the household screens ask for: the naming preview, the members panel, the move
 * action, and the recompute.
 */
@IsTest
private class HouseholdControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void thePreviewShowsFiveSampleHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            List<HouseholdController.HouseholdPreview> rows = HouseholdController.preview(
                'The {LastName} Family',
                '{Salutation} {FirstName} {LastName}',
                '{FirstName}'
            );
            Test.stopTest();

            Assert.areEqual(5, rows.size(), 'Maria sees five sample households');
            Assert.areEqual(
                'The Smith Family',
                rows[0].name,
                'The first sample is a couple who share a surname'
            );
            Assert.areEqual(
                'Mr. and Mrs. John Smith',
                rows[0].formalGreeting,
                'The formal greeting is combined'
            );
            Assert.areEqual(
                'John and Jane',
                rows[0].informalGreeting,
                'The informal greeting names both'
            );
        }
    }

    @IsTest
    static void thePreviewFollowsThePatternBeingTyped() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            List<HouseholdController.HouseholdPreview> rows = HouseholdController.preview(
                '{LastName} Household',
                '{Salutation} {FirstName} {LastName}',
                '{FirstName}'
            );
            Test.stopTest();

            Assert.areEqual(
                'Smith Household',
                rows[0].name,
                'The preview uses the pattern, not the saved one'
            );
        }
    }

    @IsTest
    static void theMembersPanelListsTheHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Smith Family');
            insert household;
            Contact john = new Contact(
                Salutation = 'Mr.',
                FirstName = 'John',
                LastName = 'Smith',
                AccountId = household.Id,
                Household_Role__c = 'Head'
            );
            insert john;
            update new Account(Id = household.Id, Primary_Contact__c = john.Id);

            Test.startTest();
            List<HouseholdController.MemberView> members = HouseholdController.getMembers(
                household.Id
            );
            Test.stopTest();

            Assert.areEqual(1, members.size(), 'One member');
            Assert.areEqual('John Smith', members[0].name, 'The member is named in full');
            Assert.areEqual('Head', members[0].role, 'The role is shown');
            Assert.isFalse(members[0].isDeceased, 'John is alive');
        }
    }

    @IsTest
    static void askingForMembersOfSomethingThatIsNotAHouseholdIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Boolean refused = false;

            Test.startTest();
            try {
                HouseholdController.getMembers(maria.Id);
            } catch (Exception e) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'A person is not a household');
        }
    }

    @IsTest
    static void movingSomeoneFromThePanelMovesThem() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id toHousehold = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

            Test.startTest();
            HouseholdController.moveContact(maria.Id, toHousehold);
            Test.stopTest();

            Assert.areEqual(
                toHousehold,
                [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId,
                'Maria is in the household she was moved to'
            );
        }
    }

    @IsTest
    static void movingSomeoneNowhereReturnsAMessageTheScreenCanShow() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Boolean refused = false;

            Test.startTest();
            try {
                HouseholdController.moveContact(null, null);
            } catch (Exception e) {
                refused = true;
            }
            Test.stopTest();

            Assert.isTrue(refused, 'The screen is told that nothing was chosen');
        }
    }

    @IsTest
    static void recomputeAllStartsTheJob() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            String jobId = HouseholdController.recomputeAll();
            Test.stopTest();

            Assert.isNotNull(jobId, 'Maria gets a job to watch');
        }
    }

    @IsTest
    static void thePageOpensOnTheSavedPatterns() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = HouseholdTestDataFactory.settings(
                HouseholdTestDataFactory.MODE_CONTACT
            );
            settings.Household_Name_Pattern__c = '{LastName} Household';
            HouseholdTestDataFactory.save(settings);

            Test.startTest();
            HouseholdController.NamingSettings saved = HouseholdController.getNamingSettings();
            Test.stopTest();

            Assert.areEqual('{LastName} Household', saved.namePattern, 'Maria sees what she saved');
            Assert.areEqual(
                '{Salutation} {FirstName} {LastName}',
                saved.formalPattern,
                'And the formal greeting pattern'
            );
            Assert.areEqual('{FirstName}', saved.informalPattern, 'And the informal one');
        }
    }

    @IsTest
    static void recomputingEveryHouseholdNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            User staff = HouseholdTestDataFactory.standardUser('recomp');
            Boolean refused = false;

            Test.startTest();
            System.runAs(staff) {
                try {
                    HouseholdController.recomputeAll();
                } catch (Exception e) {
                    refused = true;
                }
            }
            Test.stopTest();

            Assert.isTrue(refused, 'A user without the settings permission is refused');
        }
    }

    @IsTest
    static void theScreenIsToldHowPeopleBelongToAHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();

            Test.startTest();
            String mode = HouseholdController.getMembershipMode();
            Test.stopTest();

            Assert.areEqual('Junction', mode, 'The panel is told this org uses the flexible mode');
        }
    }

    /**
     * The household somebody is moved into is checked against the mover's own record
     * access, the way a merge or a split checks both of its ends: the reads behind a move
     * run in system mode and would otherwise let a person be moved into a household the
     * mover cannot see.
     */
    @IsTest
    static void movingSomeoneIntoAHouseholdThisPersonCannotEditIsRefused() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id fromHousehold = householdOf(maria.Id);
            Id toHousehold = householdOf(wei.Id);
            User reader = readOnlyUser();

            String message;
            Test.startTest();
            System.runAs(reader) {
                try {
                    HouseholdController.moveContact(maria.Id, toHousehold);
                } catch (Exception e) {
                    message = e.getMessage();
                }
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorMoveNoEditAccess,
                message,
                'The refusal says what is missing, in plain words'
            );
            Assert.areEqual(
                fromHousehold,
                householdOf(maria.Id),
                'Nobody was moved into a household the person cannot edit'
            );
        }
    }

    // ------------------------------------------------------------------ helpers

    private static Id householdOf(Id contactId) {
        return [SELECT AccountId FROM Contact WHERE Id = :contactId].AccountId;
    }

    /**
     * A user on the most restricted standard profile, the same one the merge tests use, so
     * that a move refused for want of edit access is refused by the same record access
     * check the merge screen asks about.
     */
    private static User readOnlyUser() {
        // "Read Only" is absent from some editions and org shapes, so the first of the
        // known profiles without edit access that this org actually has is used.
        Map<String, Profile> byName = new Map<String, Profile>();
        for (Profile candidate : [
            SELECT Id, Name
            FROM Profile
            WHERE Name IN ('Read Only', 'Minimum Access - Salesforce')
        ]) {
            byName.put(candidate.Name, candidate);
        }
        Profile readOnly = byName.containsKey('Read Only')
            ? byName.get('Read Only')
            : byName.get('Minimum Access - Salesforce');
        Assert.isNotNull(
            readOnly,
            'This org has no standard profile without edit access, so a move refused for ' +
            'want of edit access cannot be exercised at all'
        );
        User reader = new User(
            ProfileId = readOnly.Id,
            LastName = 'Reader',
            Email = 'reader@barncrm.test.invalid',
            Username = 'reader' + DateTime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'reader',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        // A user is a setup record, so it is saved on its own, after the households.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reader;
        }
        return reader;
    }
}
