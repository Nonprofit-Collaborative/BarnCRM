/**
 * What the merge and split screen calls, including the picker and the read only check.
 */
@IsTest(testFor='ApexClass:HouseholdMergeController')
private class HouseholdMergeControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void theSearchOffersHouseholdsAndNotOrganizations() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account duplicate = HouseholdTestDataFactory.newHousehold('Garcia Household');
            Account organization = new Account(Name = 'Garcia Family Foundation');
            Database.insert(
                new List<Account>{ household, duplicate, organization },
                AccessLevel.SYSTEM_MODE
            );

            Test.startTest();
            List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
                'Garcia',
                household.Id
            );
            Test.stopTest();

            Assert.areEqual(1, options.size(), 'Only the other household is offered');
            Assert.areEqual(duplicate.Id, options[0].id, 'And it is the duplicate');
        }
    }

    /**
     * A typed % or _ is a letter to search for, not a wildcard: otherwise typing % would
     * offer every household in the org.
     */
    @IsTest
    static void theSearchTreatsWildcardsAsLetters() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account plain = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account percent = HouseholdTestDataFactory.newHousehold('100% Garcia');
            Account underscore = HouseholdTestDataFactory.newHousehold('Garcia_Lee');
            Database.insert(
                new List<Account>{ plain, percent, underscore },
                AccessLevel.SYSTEM_MODE
            );

            Test.startTest();
            List<HouseholdMergeController.HouseholdOption> byPercent = HouseholdMergeController.searchHouseholds(
                '0% G',
                null
            );
            List<HouseholdMergeController.HouseholdOption> byUnderscore = HouseholdMergeController.searchHouseholds(
                'ia_L',
                null
            );
            Test.stopTest();

            Assert.areEqual(1, byPercent.size(), 'Only the household with a percent sign matches');
            Assert.areEqual(percent.Id, byPercent[0].id, 'And it is that one');
            Assert.areEqual(
                1,
                byUnderscore.size(),
                'Only the household with an underscore matches'
            );
            Assert.areEqual(underscore.Id, byUnderscore[0].id, 'And it is that one');
        }
    }

    @IsTest
    static void aVeryShortSearchAsksForMore() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

            Test.startTest();
            List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
                'G',
                null
            );
            Test.stopTest();

            Assert.isTrue(options.isEmpty(), 'One letter is not a search');
        }
    }

    @IsTest
    static void theScreenIsToldWhenThePersonCanEdit() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Database.insert(household, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            Boolean canEdit = HouseholdMergeController.canEdit(household.Id);
            Test.stopTest();

            Assert.isTrue(canEdit, 'The person who created it can edit it');
            Assert.isFalse(HouseholdMergeController.canEdit(null), 'Nothing is not editable');
        }
    }

    @IsTest
    static void previewReachesTheScreen() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            Database.insert(new List<Account>{ survivor, victim }, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            HouseholdMergeService.MergePreview preview = HouseholdMergeController.preview(
                survivor.Id,
                victim.Id
            );
            Test.stopTest();

            Assert.areEqual(survivor.Id, preview.survivorId, 'The survivor comes back');
            Assert.isTrue(preview.canEdit, 'The person who created both may merge them');
            Assert.isFalse(preview.fields.isEmpty(), 'There is something to compare');
        }
    }

    @IsTest
    static void mergeFromTheScreenReturnsTheSurvivor() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            insert new List<Contact>{ maria, wei };
            Id survivorId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Id victimId = [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId;

            Test.startTest();
            HouseholdMergeService.MergeResult result = HouseholdMergeController.mergeHouseholds(
                survivorId,
                victimId,
                new Map<String, String>()
            );
            Test.stopTest();

            Assert.areEqual(survivorId, result.survivorId, 'The screen is sent to the survivor');
            Assert.areEqual(
                2,
                [SELECT Member_Count__c FROM Account WHERE Id = :survivorId].Member_Count__c,
                'Both people are in it'
            );
        }
    }

    @IsTest
    static void splitFromTheScreenReturnsTheNewHousehold() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id householdId = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Contact wei = HouseholdTestDataFactory.newContact('Mr.', 'Wei', 'Lee');
            wei.AccountId = householdId;
            insert wei;

            Test.startTest();
            Id created = HouseholdMergeController.splitHousehold(
                householdId,
                new List<Id>{ wei.Id },
                null
            );
            Test.stopTest();

            Assert.isNotNull(created, 'The screen is sent to the household that was created');
            Assert.areEqual(
                created,
                [SELECT AccountId FROM Contact WHERE Id = :wei.Id].AccountId,
                'Wei is in it'
            );
        }
    }

    @IsTest
    static void aRefusalReachesTheScreenAsSomethingAPersonCanRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account organization = new Account(Name = 'Bay Area Food Bank');
            Database.insert(new List<Account>{ household, organization }, AccessLevel.SYSTEM_MODE);

            String message;
            Test.startTest();
            try {
                HouseholdMergeController.mergeHouseholds(
                    household.Id,
                    organization.Id,
                    new Map<String, String>()
                );
            } catch (Exception e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorNotHousehold,
                message,
                'The screen shows the same words the guide quotes'
            );
        }
    }

    /**
     * A failure the package did not expect reaches the screen as the plain message, and the
     * platform's wording goes to the Error Log. The comparison's reads strip what a person
     * cannot read rather than fail, so no user's access produces one any more:
     * the test raises it.
     */
    @IsTest
    static void aPlatformFailureReachesTheScreenInPlainWords() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
            Database.insert(new List<Account>{ survivor, victim }, AccessLevel.SYSTEM_MODE);
            HouseholdMergeController.previewFailureForTest = new QueryException(
                'Insufficient permissions: secure query included inaccessible field'
            );

            String message;
            Test.startTest();
            try {
                HouseholdMergeController.preview(survivor.Id, victim.Id);
            } catch (Exception e) {
                message = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Core_Households_ErrorUnexpected,
                message,
                'The person is told something went wrong, in words meant for them'
            );
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :Label.Core_HouseholdMerge_ErrorContext
                ],
                'What actually happened is in the Error Log for the administrator'
            );
        }
    }
}
