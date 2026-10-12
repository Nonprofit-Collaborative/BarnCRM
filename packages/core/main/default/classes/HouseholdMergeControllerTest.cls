/**
 * What the merge and split screen calls, including the picker and the read only check.
 */
@IsTest
private class HouseholdMergeControllerTest {
    @IsTest
    static void theSearchOffersHouseholdsAndNotOrganizations() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account duplicate = HouseholdTestDataFactory.newHousehold('Garcia Household');
        Account organization = new Account(Name = 'Garcia Family Foundation');
        insert new List<Account>{ household, duplicate, organization };

        Test.startTest();
        List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
            'Garcia',
            household.Id
        );
        Test.stopTest();

        Assert.areEqual(1, options.size(), 'Only the other household is offered');
        Assert.areEqual(duplicate.Id, options[0].id, 'And it is the duplicate');
    }

    /**
     * A typed % or _ is a letter to search for, not a wildcard: otherwise typing % would
     * offer every household in the org.
     */
    @IsTest
    static void theSearchTreatsWildcardsAsLetters() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account plain = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account percent = HouseholdTestDataFactory.newHousehold('100% Garcia');
        Account underscore = HouseholdTestDataFactory.newHousehold('Garcia_Lee');
        insert new List<Account>{ plain, percent, underscore };

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
        Assert.areEqual(1, byUnderscore.size(), 'Only the household with an underscore matches');
        Assert.areEqual(underscore.Id, byUnderscore[0].id, 'And it is that one');
    }

    @IsTest
    static void aVeryShortSearchAsksForMore() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        Test.startTest();
        List<HouseholdMergeController.HouseholdOption> options = HouseholdMergeController.searchHouseholds(
            'G',
            null
        );
        Test.stopTest();

        Assert.isTrue(options.isEmpty(), 'One letter is not a search');
    }

    @IsTest
    static void theScreenIsToldWhenThePersonCanEdit() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;

        Test.startTest();
        Boolean canEdit = HouseholdMergeController.canEdit(household.Id);
        Test.stopTest();

        Assert.isTrue(canEdit, 'The person who created it can edit it');
        Assert.isFalse(HouseholdMergeController.canEdit(null), 'Nothing is not editable');
    }

    @IsTest
    static void previewReachesTheScreen() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        insert new List<Account>{ survivor, victim };

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

    @IsTest
    static void mergeFromTheScreenReturnsTheSurvivor() {
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

    @IsTest
    static void splitFromTheScreenReturnsTheNewHousehold() {
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

    @IsTest
    static void aRefusalReachesTheScreenAsSomethingAPersonCanRead() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account organization = new Account(Name = 'Bay Area Food Bank');
        insert new List<Account>{ household, organization };

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

    /**
     * A failure the package did not expect (here, a user whose profile cannot read
     * households at all, so the platform refuses the comparison's own query) reaches the
     * screen as the plain message, and the platform's wording goes to the Error Log.
     */
    @IsTest
    static void aPlatformFailureReachesTheScreenInPlainWords() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        Account survivor = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        Account victim = HouseholdTestDataFactory.newHousehold('Garcia Household');
        insert new List<Account>{ survivor, victim };
        User reader = readOnlyUser();

        String message;
        Test.startTest();
        System.runAs(reader) {
            try {
                HouseholdMergeController.preview(survivor.Id, victim.Id);
            } catch (Exception e) {
                message = e.getMessage();
            }
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

    // ------------------------------------------------------------------ helpers

    /**
     * A user on the most restricted standard profile, the same one the service tests use.
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
            'This org has no standard profile without edit access, so a refused read ' +
            'cannot be exercised at all'
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
