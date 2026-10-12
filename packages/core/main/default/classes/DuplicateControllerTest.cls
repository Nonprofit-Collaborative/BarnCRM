/**
 * DuplicateController: what the Duplicates panel shows, and the actions on it (C-20).
 * Suggestions are written directly with DuplicateService.recordPairs, so these tests do not
 * depend on what the org's duplicate rules match. The platform does require every suggestion
 * to name an active rule, so a test that needs one stops, with an assertion, in an org that
 * has no active rule for its object.
 */
@IsTest
private class DuplicateControllerTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C20_Duplicates_Test', UserInfo.getUserId());
    }

    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, options);
        return records;
    }

    /** Writes the pair as a suggestion; answers false when no active rule allows one. */
    private static Boolean suggest(Id first, Id second) {
        String objectName = first.getSObjectType().getDescribe().getName();
        Integer written = DuplicateService.recordPairs(
            new List<DuplicateService.Pair>{ new DuplicateService.Pair(first, second, null) },
            null
        );
        if (
            !DuplicateSelector.objectsWithActiveRules(new Set<String>{ objectName })
                .contains(objectName)
        ) {
            Assert.areEqual(0, written, 'With no active rule no suggestion can be written.');
            return false;
        }
        return true;
    }

    private static List<Account> twoHouseholds() {
        return (List<Account>) insertAllowingDuplicates(
            new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Dupview Family'),
                HouseholdTestDataFactory.newHousehold('The Dupview Family')
            }
        );
    }

    @IsTest
    static void aPairOfPeopleIsShownWithTheirEmailAndNoMergeButton() {
        List<Contact> people = (List<Contact>) insertAllowingDuplicates(
            new List<Contact>{
                new Contact(
                    FirstName = 'Ana',
                    LastName = 'Dupview',
                    Email = 'ana.dupview@example.org'
                ),
                new Contact(
                    FirstName = 'Anna',
                    LastName = 'Dupview',
                    Email = 'anna.dupview@example.org'
                )
            }
        );
        if (!suggest(people[0].Id, people[1].Id)) {
            return;
        }

        Test.startTest();
        DuplicateController.DuplicateView view = DuplicateController.getView();
        Test.stopTest();

        Assert.isTrue(view.canManage, 'The test user holds Manage BarnCRM Settings.');
        Assert.areEqual(1, view.suggestions.size(), 'The one suggestion is listed.');
        DuplicateController.SuggestionView suggestion = view.suggestions[0];
        Assert.areEqual(2, suggestion.records.size(), 'Both people are named.');
        Assert.isFalse(
            suggestion.canMerge,
            'People are merged with the platform merge, not here (R-DP4).'
        );
        Assert.isTrue(
            suggestion.records[0].detail.endsWith('@example.org'),
            'A person is told apart by their email address.'
        );
        for (DuplicateController.RuleView rule : view.rules) {
            Assert.isTrue(
                rule.objectName == 'Contact' || rule.objectName == 'Account',
                'Only rules for people and accounts are listed.'
            );
        }
    }

    @IsTest
    static void twoHouseholdsAreMergedFromThePanelAndTheSuggestionGoes() {
        List<Account> households = twoHouseholds();
        if (!suggest(households[0].Id, households[1].Id)) {
            return;
        }
        DuplicateController.DuplicateView before = DuplicateController.getView();
        Assert.isTrue(before.suggestions[0].canMerge, 'Two households can be merged here.');

        HouseholdMergeService.MergePreview preview = DuplicateController.previewMerge(
            households[0].Id,
            households[1].Id
        );
        Assert.areEqual(
            households[0].Id,
            preview.survivorId,
            'The preview is the household merge preview.'
        );

        Test.startTest();
        DuplicateController.DuplicateView after = DuplicateController.mergeHouseholds(
            before.suggestions[0].setId,
            households[0].Id,
            households[1].Id,
            null
        );
        Test.stopTest();

        Assert.areEqual(0, after.suggestions.size(), 'The merged pair is no longer suggested.');
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Account WHERE Id IN :households],
            'Two households are now one.'
        );
        Assert.areEqual(0, after.dismissedCount, 'A merge is not a dismissal.');
    }

    @IsTest
    static void aDismissedPairLeavesTheListAndIsCounted() {
        List<Account> households = twoHouseholds();
        if (!suggest(households[0].Id, households[1].Id)) {
            return;
        }
        Id setId = DuplicateController.getView().suggestions[0].setId;

        Test.startTest();
        DuplicateController.DuplicateView view = DuplicateController.dismiss(setId, 'Neighbors');
        Test.stopTest();

        Assert.areEqual(0, view.suggestions.size(), 'The dismissed pair is gone from the list.');
        Assert.areEqual(1, view.dismissedCount, 'And counted as dismissed.');
    }

    @IsTest
    static void aPairWithAnOrganizationIsNotShown() {
        List<Account> accounts = (List<Account>) insertAllowingDuplicates(
            new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Dupview Family'),
                new Account(Name = 'Dupview Bakery')
            }
        );
        suggest(accounts[0].Id, accounts[1].Id);

        Test.startTest();
        DuplicateController.DuplicateView view = DuplicateController.getView();
        Test.stopTest();

        Assert.areEqual(
            0,
            view.suggestions.size(),
            'Nothing on the panel can act on an organization (R-DP2).'
        );
    }

    @IsTest
    static void aScanStartsOnlyWhenARuleIsActive() {
        Boolean anyActive = !DuplicateSelector.objectsWithActiveRules(
                new Set<String>(DuplicateSelector.REVIEWED_OBJECTS)
            )
            .isEmpty();
        Test.startTest();
        try {
            DuplicateController.DuplicateView view = DuplicateController.startScan();
            Assert.isTrue(anyActive, 'A scan starts only when a rule is active.');
            Assert.isTrue(view.anyRuleActive, 'The panel shows the active rule.');
        } catch (AuraHandledException refused) {
            Assert.isFalse(anyActive, 'A scan with an active rule must start.');
            Assert.areEqual(
                Label.Core_Duplicates_ErrorNoActiveRule,
                refused.getMessage(),
                'Said in words.'
            );
        }
        // No stopTest: the scan itself is DuplicateScanBatchTest's subject, and a started scan
        // chains a second batch, which a test method cannot run.
    }

    @IsTest
    static void everyActionNeedsTheSettingsPermission() {
        User staff = SettingsTestPermissions.buildStandardUser('Dana', 'Dupview', 'dupvw');
        insert staff;
        Test.startTest();
        System.runAs(staff) {
            try {
                DuplicateController.startScan();
                Assert.fail('A scan needs Manage BarnCRM Settings.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorPermissionRequired,
                    refused.getMessage(),
                    'Said in words.'
                );
            }
            try {
                DuplicateController.mergeHouseholds(null, null, null, null);
                Assert.fail('A merge from the panel needs Manage BarnCRM Settings.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorPermissionRequired,
                    refused.getMessage(),
                    'Said in words.'
                );
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void aSuggestionAlreadyGoneIsSaidInWords() {
        Test.startTest();
        try {
            DuplicateController.dismiss(null, null);
            Assert.fail('Nothing to dismiss.');
        } catch (AuraHandledException refused) {
            Assert.areEqual(
                Label.Core_Duplicates_ErrorNoSuggestion,
                refused.getMessage(),
                'Said in words.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void anAdministratorReviewsSuggestionsAndSeesHowMany() {
        List<Account> households = twoHouseholds();
        if (!suggest(households[0].Id, households[1].Id)) {
            return;
        }

        Test.startTest();
        DuplicateController.DuplicateView view = DuplicateController.getView();
        Test.stopTest();

        Assert.isTrue(view.canReviewSuggestions, 'An administrator can read the suggestions.');
        Assert.areEqual(1, view.totalSuggestions, 'The total counts every usable suggestion.');
        Assert.isFalse(view.moreNotCounted, 'All of them were read.');
    }

    /**
     * Duplicate record sets can be given only to a Sales Cloud or Service Cloud license, so no
     * Core permission set grants them (ADR-0050). A person with the settings permission but no
     * access to the sets is told so, and nothing on the panel acts.
     */
    @IsTest
    static void withoutAccessToSuggestionsThePanelSaysSoAndActsOnNothing() {
        Profile minimum = [
            SELECT Id
            FROM Profile
            WHERE Name = 'Minimum Access - Salesforce'
            LIMIT 1
        ];
        User admin = new User(
            ProfileId = minimum.Id,
            LastName = 'Dupaccess',
            Email = 'dupaccess@barncrm.test.invalid',
            Username = 'dupaccess' + DateTime.now().getTime() + '@barncrm.test.invalid',
            Alias = 'dupacc',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert admin;
            insert new PermissionSetAssignment(
                AssigneeId = admin.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'BarnCRM_Admin']
                .Id
            );
        }

        Test.startTest();
        System.runAs(admin) {
            DuplicateController.DuplicateView view = DuplicateController.getView();
            Assert.isTrue(view.canManage, 'The Core administrator set carries the permission.');
            Assert.isFalse(view.canReviewSuggestions, 'But not the duplicate record sets.');
            Assert.isTrue(view.suggestions.isEmpty(), 'So nothing is listed.');
            try {
                DuplicateController.startScan();
                Assert.fail('A scan needs access to the duplicate record sets.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorNoSuggestionAccess,
                    refused.getMessage(),
                    'Said in words.'
                );
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void aMergeFromThePanelMustBeThePairItSuggested() {
        List<Account> households = (List<Account>) insertAllowingDuplicates(
            new List<Account>{
                HouseholdTestDataFactory.newHousehold('The Dupview Family'),
                HouseholdTestDataFactory.newHousehold('The Dupview Family'),
                HouseholdTestDataFactory.newHousehold('The Dupview Household')
            }
        );
        if (!suggest(households[0].Id, households[1].Id)) {
            return;
        }
        Id setId = DuplicateController.getView().suggestions[0].setId;

        Test.startTest();
        try {
            DuplicateController.mergeHouseholds(setId, households[0].Id, households[2].Id, null);
            Assert.fail('A merge of a pair the suggestion does not name is refused.');
        } catch (AuraHandledException refused) {
            Assert.areEqual(
                Label.Core_Duplicates_ErrorNotThisPair,
                refused.getMessage(),
                'Said in words.'
            );
        }
        Test.stopTest();

        Assert.areEqual(
            3,
            [SELECT COUNT() FROM Account WHERE Id IN :households],
            'Nothing is merged.'
        );
        Assert.areEqual(1, [SELECT COUNT() FROM DuplicateRecordSet], 'The suggestion stays.');
    }

    @IsTest
    static void theLastScanLineSaysWhatTheScanFound() {
        String said = 'Duplicate scan of Contact finished: 0 new possible duplicates recorded.';
        ErrorLogger.logMessage(said, DuplicateScanBatch.LOG_CONTEXT, ErrorLogger.SEVERITY_WARNING);
        Test.getEventBus().deliver();

        Test.startTest();
        DuplicateController.DuplicateView view = DuplicateController.getView();
        Test.stopTest();

        Assert.areEqual(said, view.lastScanSummary, 'The latest summary is shown as written.');
        Assert.isTrue(view.lastScanHadFailures, 'A Warning summary is shown as one.');
    }
}
