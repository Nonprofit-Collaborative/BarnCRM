/**
 * DuplicateController: what the Duplicates panel shows, and the actions on it (C-20).
 * Suggestions are written directly with DuplicateService.recordPairs, so these tests do not
 * depend on what the org's duplicate rules match. The platform does require every suggestion
 * to name an active rule, so a test that needs one stops, with an assertion, in an org that
 * has no active rule for its object.
 */
@IsTest(testFor='ApexClass:DuplicateController')
private class DuplicateControllerTest {
    @TestSetup
    static void grantPermission() {
        System.runAs(TestUsers.admin()) {
            SettingsTestPermissions.grantTo('C20_Duplicates_Test', UserInfo.getUserId());
        }
    }

    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        // System mode: households are among these, and no user has their record type (ADR-0141).
        Database.insert(records, options, AccessLevel.SYSTEM_MODE);
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
        System.runAs(TestUsers.admin()) {
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
            Map<String, String> compared = new Map<String, String>();
            for (DuplicateController.FieldView field : suggestion.records[0].fields) {
                compared.put(field.fieldName, field.value);
            }
            Assert.isTrue(
                compared.get('Email').endsWith('@example.org'),
                'The email is among the fields compared side by side.'
            );
            Assert.isTrue(
                compared.containsKey('Account.Name'),
                'The household is compared too, blank or not.'
            );
            Assert.areEqual(
                Schema.SObjectType.Contact.fields.Phone.isAccessible(),
                compared.containsKey('Phone'),
                'A readable compared field is listed even when blank, so the two sides line up.'
            );
            Assert.isNull(compared.get('Phone'), 'Neither person has a phone.');
            for (DuplicateController.RuleView rule : view.rules) {
                Assert.isTrue(
                    rule.objectName == 'Contact' || rule.objectName == 'Account',
                    'Only rules for people and accounts are listed.'
                );
            }
        }
    }

    @IsTest
    static void twoHouseholdsAreMergedFromThePanelAndTheSuggestionGoes() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = twoHouseholds();
            if (!suggest(households[0].Id, households[1].Id)) {
                return;
            }
            DuplicateController.DuplicateView before = DuplicateController.getView();
            Assert.isTrue(before.suggestions[0].canMerge, 'Two households can be merged here.');
            Assert.areEqual(
                DuplicateSelector.HOUSEHOLD_COMPARED.size(),
                before.suggestions[0].records[0].fields.size(),
                'A household is compared on its billing address and phone.'
            );

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
    }

    @IsTest
    static void aDismissedPairLeavesTheListAndIsCounted() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = twoHouseholds();
            if (!suggest(households[0].Id, households[1].Id)) {
                return;
            }
            Id setId = DuplicateController.getView().suggestions[0].setId;

            Test.startTest();
            DuplicateController.DuplicateView view = DuplicateController.dismiss(
                setId,
                'Neighbors'
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                view.suggestions.size(),
                'The dismissed pair is gone from the list.'
            );
            Assert.areEqual(1, view.dismissedCount, 'And counted as dismissed.');
        }
    }

    /**
     * A rule that reports on save writes the pair again when one of the two is saved past its
     * alert; the dismissal still holds for that new suggestion (R-DP5).
     */
    @IsTest
    static void aDismissedPairWrittenAgainStaysOffThePanel() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = twoHouseholds();
            if (!suggest(households[0].Id, households[1].Id)) {
                return;
            }
            DuplicateController.dismiss(DuplicateController.getView().suggestions[0].setId, null);
            suggest(households[0].Id, households[1].Id);

            Test.startTest();
            DuplicateController.DuplicateView view = DuplicateController.getView();
            Test.stopTest();

            Assert.areEqual(1, [SELECT COUNT() FROM DuplicateRecordSet], 'The set was written.');
            Assert.areEqual(0, view.suggestions.size(), 'But the dismissed pair is not offered.');
            Assert.areEqual(0, view.totalSuggestions, 'Nor counted.');
        }
    }

    @IsTest
    static void aNonprofitCloudHouseholdIsNotOfferedForMerge() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = twoHouseholds();
            if (!suggest(households[0].Id, households[1].Id)) {
                return;
            }
            HouseholdSelector.accountsWithNativeHouseholdGroupsOverride = new Set<Id>{
                households[1].Id
            };

            Test.startTest();
            DuplicateController.DuplicateView view = DuplicateController.getView();
            String refusal;
            try {
                DuplicateController.previewMerge(households[0].Id, households[1].Id);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(0, view.suggestions.size(), 'The pair is not shown (ADR-0036).');
            Assert.areEqual(
                Label.Core_HouseholdMerge_ErrorNativeHousehold,
                refusal,
                'And a merge of it is refused in words.'
            );
        }
    }

    @IsTest
    static void aSecondScanIsRefusedWhileOneIsRunning() {
        System.runAs(TestUsers.admin()) {
            DuplicateService.stubMatches = new List<DuplicateService.Pair>();

            Test.startTest();
            Database.executeBatch(
                new DuplicateScanBatch('Contact', new List<String>()),
                DuplicateService.MAX_RECORDS_PER_CALL
            );
            DuplicateController.DuplicateView view = DuplicateController.getView();
            String refusal;
            try {
                DuplicateController.startScan();
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.isTrue(view.scanRunning, 'The panel says a scan is running.');
            Assert.areEqual(
                Label.Core_Duplicates_ErrorScanRunning,
                refusal,
                'A second scan is refused in words.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'DuplicateScanBatch'],
                'Only the first scan was started.'
            );
        }
    }

    /**
     * Organization pairs the standard Account rule writes on save do not hide the households
     * behind them: the panel reads on past a window it can use none of.
     */
    @IsTest
    static void organizationPairsDoNotHideAHouseholdPairBehindThem() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = twoHouseholds();
            if (!suggest(households[0].Id, households[1].Id)) {
                return;
            }
            for (Integer index = 0; index < 3; index++) {
                List<Account> bakeries = (List<Account>) insertAllowingDuplicates(
                    new List<Account>{
                        new Account(Name = 'Dupview Bakery ' + index),
                        new Account(Name = 'Dupview Bakery ' + index)
                    }
                );
                suggest(bakeries[0].Id, bakeries[1].Id);
            }
            DuplicateController.maxRead = 2;

            Test.startTest();
            DuplicateController.DuplicateView view = DuplicateController.getView();
            Test.stopTest();

            Assert.areEqual(1, view.suggestions.size(), 'The households, found past the bakeries.');
            Assert.isTrue(view.suggestions[0].canMerge, 'And offered for merge.');
        }
    }

    @IsTest
    static void aPairWithAnOrganizationIsNotShown() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aScanStartsOnlyWhenARuleIsActive() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void everyActionNeedsTheSettingsPermission() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void aSuggestionAlreadyGoneIsSaidInWords() {
        System.runAs(TestUsers.admin()) {
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
    }

    @IsTest
    static void anAdministratorReviewsSuggestionsAndSeesHowMany() {
        System.runAs(TestUsers.admin()) {
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
    }

    /**
     * Duplicate record sets can be given only to a Sales Cloud or Service Cloud license, so no
     * Core permission set grants them (ADR-0050). A person with the settings permission but no
     * access to the sets is told so, and nothing on the panel acts.
     */
    @IsTest
    static void withoutAccessToSuggestionsThePanelSaysSoAndActsOnNothing() {
        System.runAs(TestUsers.admin()) {
            User admin = new User(
                ProfileId = TestUsers.minimumAccessProfileId(),
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
    }

    @IsTest
    static void aMergeFromThePanelMustBeThePairItSuggested() {
        System.runAs(TestUsers.admin()) {
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
                DuplicateController.mergeHouseholds(
                    setId,
                    households[0].Id,
                    households[2].Id,
                    null
                );
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
    }

    @IsTest
    static void theLastScanLineSaysWhatTheScanFound() {
        System.runAs(TestUsers.admin()) {
            String said = 'Duplicate scan of Contact finished: 0 new possible duplicates recorded.';
            ErrorLogger.logMessage(
                said,
                DuplicateScanBatch.LOG_CONTEXT,
                ErrorLogger.SEVERITY_WARNING
            );
            Test.getEventBus().deliver();

            Test.startTest();
            DuplicateController.DuplicateView view = DuplicateController.getView();
            Test.stopTest();

            Assert.areEqual(said, view.lastScanSummary, 'The latest summary is shown as written.');
            Assert.isTrue(view.lastScanHadFailures, 'A Warning summary is shown as one.');
        }
    }
}
