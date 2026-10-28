/**
 * The Rollup Builder's reads and its save (R-R10, R-R8, slice S11). Core holds no giving objects,
 * so organizations count their child organizations (`ParentId`) into Account fields BarnCRM ships,
 * which the BarnCRM Admin permission set lets Maria edit. Maria is an administrator who builds
 * rollups: BarnCRM Admin for Manage BarnCRM Settings, Rollup Builder Admin for the definitions.
 */
@IsTest(testFor='ApexClass:RollupBuilderController')
private class RollupBuilderControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Rollup_Builder_Admin' }
        );
    }

    private static RollupBuilderController.Draft childCount() {
        RollupBuilderController.Draft draft = new RollupBuilderController.Draft();
        draft.name = 'Child organization count';
        draft.targetObject = 'Account';
        draft.targetField = 'Member_Count__c';
        draft.sourceObject = 'Account';
        draft.relationshipPath = 'ParentId';
        draft.aggregate = 'COUNT';
        draft.mode = RollupService.MODE_BOTH;
        draft.active = true;
        return draft;
    }

    private static Rollup_Definition__c existing(String name, String targetFilter) {
        return new Rollup_Definition__c(
            Name = name,
            Definition_Key__c = 'Test_' + name.replace(' ', '_'),
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Target_Filter_JSON__c = targetFilter,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = true
        );
    }

    private static String nameFilter(String operator, String value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Name',
                        'operator' => operator,
                        'value' => value
                    }
                }
            }
        );
    }

    private static String saveRefusal(RollupBuilderController.Draft draft) {
        try {
            RollupBuilderController.save(draft, false);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return null;
    }

    // ------------------------------------------------------------------------------------ reads

    @IsTest
    static void theModelNamesAnotherRollupToolOnlyWhenOneIsHere() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            OtherRollupTools.overrideForTest(new Set<String>());
            List<String> without = RollupBuilderController.getModel().otherToolNotices;
            OtherRollupTools.overrideForTest(new Set<String>{ OtherRollupTools.DLRS_NAMESPACE });
            List<String> withDlrs = RollupBuilderController.getModel().otherToolNotices;

            System.Assert.isTrue(without.isEmpty(), 'Nothing is said in an org without DLRS');
            System.Assert.areEqual(
                OtherRollupTools.notices(),
                withDlrs,
                'The Builder says DLRS is a separate tool, as Core words it'
            );
            System.Assert.areEqual(1, withDlrs.size(), 'One notice, for DLRS');
        }
    }

    @IsTest
    static void theModelOffersAccountAndCustomObjectsButNotBookkeeping() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.BuilderModel model = RollupBuilderController.getModel();

            Set<String> targets = new Set<String>();
            for (RollupBuilderController.Option option : model.targets) {
                targets.add(option.value.toLowerCase());
            }
            System.Assert.isTrue(targets.contains('account'), 'Account can show a total');
            // BarnCRM's own objects by exact name, bare and qualified: another package's object
            // may end the same way (another vendor's error log object) and is rightly offered.
            for (String bookkeeping : new List<String>{ 'Rollup_Queue__c', 'Error_Log__c' }) {
                System.Assert.isFalse(
                    targets.contains(bookkeeping.toLowerCase()) ||
                    targets.contains(NamespaceUtil.qualify(bookkeeping).toLowerCase()),
                    'BarnCRM bookkeeping is never offered: ' + bookkeeping
                );
            }
            System.Assert.isFalse(model.aggregates.isEmpty(), 'Every calculation is offered');
            System.Assert.areEqual(3, model.modes.size(), 'The three modes are offered');
        }
    }

    @IsTest
    static void targetFieldsAreWritableAndShowTheRollupThatFillsThem() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert existing('Child count', null);

            Map<String, RollupBuilderController.FieldOption> byName = new Map<String, RollupBuilderController.FieldOption>();
            for (
                RollupBuilderController.FieldOption option : RollupBuilderController.getTargetFields(
                    'Account'
                )
            ) {
                byName.put(option.value.toLowerCase(), option);
            }

            System.Assert.areEqual(
                'Child count',
                byName.get('member_count__c').filledBy,
                'A field another rollup fills names that rollup (R-R8)'
            );
            System.Assert.isTrue(
                byName.containsKey('deceased__c'),
                'A checkbox can hold Any or None'
            );
            System.Assert.isFalse(
                byName.containsKey('createddate'),
                'A system field is never offered'
            );
            System.Assert.isFalse(
                byName.containsKey('rollups_last_calculated__c'),
                'The freshness stamp is the engine own field'
            );
        }
    }

    @IsTest
    static void sourcesOfferEveryLinkAndThePersonsHousehold() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Set<String> values = new Set<String>();
            Boolean throughHousehold = false;
            for (
                RollupBuilderController.SourceOption option : RollupBuilderController.getSources(
                    'Account'
                )
            ) {
                values.add(option.value.toLowerCase());
                throughHousehold |= option.relationshipPath.endsWith(RollupPath.TOKEN_HOUSEHOLD);
                System.Assert.isTrue(
                    String.isNotBlank(option.recordsLabel),
                    'Each option names its records for the filter sentence'
                );
            }

            System.Assert.isTrue(values.contains('account|parentid'), 'Child organizations count');
            System.Assert.isTrue(values.contains('contact|accountid'), 'People count');
            System.Assert.isTrue(throughHousehold, 'Records about a person reach their household');
        }
    }

    /**
     * ADR-0136: standard objects are offered through describe, the shortlist first, and the
     * platform's companion objects never. Task stands in for every standard object: the
     * Platform-only gate forbids naming the sales and service objects here.
     */
    @IsTest
    static void standardObjectsAreOfferedTheShortlistFirst() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.BuilderModel model = RollupBuilderController.getModel();

            Map<String, RollupBuilderController.Option> byName = new Map<String, RollupBuilderController.Option>();
            Boolean pastTheCommon = false;
            Boolean commonFirst = true;
            for (RollupBuilderController.Option option : model.targets) {
                byName.put(option.value.toLowerCase(), option);
                if (option.common != true) {
                    pastTheCommon = true;
                } else if (pastTheCommon) {
                    commonFirst = false;
                }
            }

            System.Assert.isTrue(byName.containsKey('task'), 'A standard object is offered');
            System.Assert.isTrue(byName.get('task').common, 'On the shortlist, so listed first');
            System.Assert.isTrue(byName.get('account').common, 'Account is listed first');
            System.Assert.isTrue(commonFirst, 'Every common object comes before the others');
            for (String companion : new List<String>{ 'accountshare', 'accounthistory' }) {
                System.Assert.isFalse(byName.containsKey(companion), 'Never ' + companion);
            }
        }
    }

    /** ADR-0136: a standard object's records can be counted, and say whether they are instant. */
    @IsTest
    static void sourcesIncludeStandardObjectsAndSayWhichAreInstant() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Map<String, RollupBuilderController.SourceOption> byValue = new Map<String, RollupBuilderController.SourceOption>();
            Boolean task = false;
            for (
                RollupBuilderController.SourceOption option : RollupBuilderController.getSources(
                    'Account'
                )
            ) {
                byValue.put(option.value.toLowerCase(), option);
                if (option.sourceObject == 'Task') {
                    task = true;
                    System.Assert.isFalse(option.instant, 'No rollup trigger on Task yet');
                }
            }

            System.Assert.isTrue(task, 'Tasks can be counted on an Account');
            System.Assert.isTrue(
                byValue.get('contact|accountid').instant,
                'Contact has a packaged rollup trigger'
            );
        }
    }

    /** R-R12: only a packaged registration of the rollup handler makes an entity instant. */
    @IsTest
    static void anEntityIsInstantOnlyWithARegisteredRollupTrigger() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Automation_Registry__mdt row = TestDataFactory.registryEntry('Rollups_Task', true);
            row.Handler_Class__c = 'RollupTriggerHandler';
            row.Object_Name__c = 'Task';
            Automation_Registry__mdt other = TestDataFactory.registryEntry('Other_Event', true);
            other.Object_Name__c = 'Event';
            TestDataFactory.useRegistry(new List<Automation_Registry__mdt>{ row, other });

            System.Assert.isTrue(RollupService.hasInstantUpdates('Task'), 'Registered');
            System.Assert.isFalse(RollupService.hasInstantUpdates('Event'), 'Another handler');
            System.Assert.isFalse(RollupService.hasInstantUpdates('No_Such__c'), 'Not in the org');
        }
    }

    /** ADR-0136: with no rollup trigger, Instantly alone is refused; Both is saved. */
    @IsTest
    static void instantlyAloneIsRefusedForRecordsWithNoTrigger() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.Draft instantly = childCount();
            instantly.sourceObject = 'Task';
            instantly.relationshipPath = 'WhatId';
            instantly.mode = RollupService.MODE_REAL_TIME;
            RollupBuilderController.Draft both = childCount();
            both.sourceObject = 'Task';
            both.relationshipPath = 'WhatId';

            String instantlyRefusal;
            String bothRefusal;
            System.runAs(maria()) {
                instantlyRefusal = saveRefusal(instantly);
                bothRefusal = saveRefusal(both);
            }

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_ErrorNoInstant,
                    new List<String>{
                        Task.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                            .getLabelPlural()
                    }
                ),
                instantlyRefusal,
                'Says why, and what to choose'
            );
            System.Assert.isNull(bothRefusal, 'Both is saved');
            System.Assert.areEqual(
                'Task',
                [SELECT Source_Object__c FROM Rollup_Definition__c LIMIT 1].Source_Object__c,
                'Counting Tasks'
            );
        }
    }

    @IsTest
    static void sourceFieldsCarryTheirTypeAndPicklistValues() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Boolean sawPicklist = false;
            for (
                RollupBuilderController.FieldOption option : RollupBuilderController.getSourceFields(
                    'Account'
                )
            ) {
                if (option.type == 'picklist') {
                    sawPicklist = true;
                    System.Assert.isNotNull(option.picklistValues, 'A picklist carries its values');
                }
            }
            System.Assert.isTrue(sawPicklist, 'Account has a picklist to filter on');
        }
    }

    @IsTest
    static void anUnknownObjectIsRefusedInPlainWords() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            try {
                RollupBuilderController.getTargetFields('No_Such_Object__c');
                System.Assert.fail('An object the org does not have is refused');
            } catch (AuraHandledException refused) {
                System.Assert.areEqual(Label.Core_Rollups_ErrorUnknownObject, refused.getMessage());
            }
        }
    }

    // ----------------------------------------------------------------------------------- saving

    @IsTest
    static void mariaSavesANewRollupInUserModeWithItsOwnKey() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User admin = maria();
            RollupBuilderController.SaveResult result;

            Test.startTest();
            System.runAs(admin) {
                result = RollupBuilderController.save(childCount(), false);
            }
            Test.stopTest();

            Rollup_Definition__c saved = [
                SELECT Definition_Key__c, Is_Package_Default__c, Aggregate__c, CreatedById
                FROM Rollup_Definition__c
                WHERE Id = :result.recordId
            ];
            System.Assert.isTrue(
                saved.Definition_Key__c.startsWith('Custom_'),
                'A new key is made'
            );
            System.Assert.isFalse(saved.Is_Package_Default__c, 'It is her own rollup');
            System.Assert.areEqual(admin.Id, saved.CreatedById, 'Saved as Maria, not the package');
            System.Assert.areEqual(Label.Core_RollupBuilder_Saved, result.notice);
        }
    }

    @IsTest
    static void aNewRollupStartsInTheSettingsDefaultMode() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.areEqual(
                RollupService.MODE_BOTH,
                RollupBuilderController.getModel().defaultMode,
                'The wizard starts a new rollup in Both on an org that never saved the setting'
            );
            RollupBuilderController.Draft draft = childCount();
            draft.mode = null;
            RollupBuilderController.SaveResult result = RollupBuilderController.save(draft, false);
            System.Assert.areEqual(
                RollupService.MODE_BOTH,
                [SELECT Mode__c FROM Rollup_Definition__c WHERE Id = :result.recordId].Mode__c,
                'A rollup saved with no mode lands in Both'
            );

            SettingsService.saveValues(
                RollupService.SETTINGS_OBJECT,
                new Map<String, Object>{
                    RollupService.MODE_DEFAULT_SETTING => RollupService.MODE_SCHEDULED
                }
            );
            System.Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                RollupBuilderController.getModel().defaultMode,
                'And in the org default once it is changed in Settings'
            );
        }
    }

    @IsTest
    static void editingAShippedRollupKeepsItsKey() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c shipped = existing('Shipped count', null);
            shipped.Is_Package_Default__c = true;
            insert shipped;
            RollupBuilderController.Draft draft = RollupBuilderController.getDraft(shipped.Id);
            draft.name = 'Renamed count';
            draft.mode = RollupService.MODE_SCHEDULED;

            Test.startTest();
            System.runAs(maria()) {
                RollupBuilderController.save(draft, false);
            }
            Test.stopTest();

            Rollup_Definition__c saved = [
                SELECT Name, Definition_Key__c, Is_Package_Default__c, Mode__c
                FROM Rollup_Definition__c
                WHERE Id = :shipped.Id
            ];
            System.Assert.areEqual('Renamed count', saved.Name);
            System.Assert.areEqual('Test_Shipped_count', saved.Definition_Key__c, 'Key unchanged');
            System.Assert.isTrue(saved.Is_Package_Default__c, 'Still the shipped rollup');
            System.Assert.areEqual(RollupService.MODE_SCHEDULED, saved.Mode__c);
        }
    }

    /**
     * A real-time text list into Account.Description. No DLRS rollups, so an org whose DLRS fills
     * Account.Description does not turn the save into the switch-off question.
     */
    private static RollupBuilderController.Draft namesList(String customDelimiter) {
        RollupDlrsFake.use(new List<RollupDlrs.Definition>());
        RollupBuilderController.Draft draft = childCount();
        draft.name = 'Contact last names';
        draft.targetField = 'Description';
        draft.sourceObject = 'Contact';
        draft.relationshipPath = 'AccountId';
        draft.aggregate = 'TEXT_LIST';
        draft.sourceField = 'LastName';
        draft.orderByField = 'LastName';
        draft.delimiter = RollupPlanner.CUSTOM_DELIMITER;
        draft.customDelimiter = customDelimiter;
        draft.mode = RollupService.MODE_REAL_TIME;
        return draft;
    }

    /** Salesforce trims a text value's spaces on save, so " - " is stored with tokens. */
    @IsTest
    static void aCustomDelimiterWithSpacesSurvivesTheSaveTheEngineAndTheBuilder() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.SaveResult result;
            System.runAs(maria()) {
                result = RollupBuilderController.save(namesList(' - '), false);
            }

            Rollup_Definition__c stored = [
                SELECT Delimiter__c, Custom_Delimiter__c
                FROM Rollup_Definition__c
                WHERE Id = :result.recordId
            ];
            System.Assert.areEqual(
                'SP()-SP()',
                stored.Custom_Delimiter__c,
                'Spaces kept as tokens'
            );
            System.Assert.areEqual(
                ' - ',
                RollupPlanner.separatorOf(stored),
                'The engine writes it'
            );
            System.Assert.areEqual(
                ' - ',
                RollupBuilderController.getDraft(result.recordId).customDelimiter,
                'The Builder shows what was typed'
            );

            Account family = new Account(Name = 'Delimiter Family');
            insert family;
            // Real-time totals are queued and recalculated just after the save (ADR-0098), so the
            // queued run finishes at stopTest.
            Test.startTest();
            insert new List<Contact>{
                new Contact(LastName = 'Baker', AccountId = family.Id),
                new Contact(LastName = 'Ames', AccountId = family.Id)
            };
            Test.stopTest();
            System.Assert.areEqual(
                'Ames - Baker',
                [SELECT Description FROM Account WHERE Id = :family.Id].Description,
                'The concatenated value uses the spaces'
            );
        }
    }

    @IsTest
    static void aTabAtEitherEndOfACustomDelimiterRoundTrips() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.SaveResult result;
            Test.startTest();
            System.runAs(maria()) {
                result = RollupBuilderController.save(namesList('\t;\t'), false);
            }
            Test.stopTest();

            Rollup_Definition__c stored = [
                SELECT Delimiter__c, Custom_Delimiter__c
                FROM Rollup_Definition__c
                WHERE Id = :result.recordId
            ];
            System.Assert.areEqual('TB();TB()', stored.Custom_Delimiter__c, 'Tabs kept as tokens');
            System.Assert.areEqual('\t;\t', RollupPlanner.separatorOf(stored), 'The engine');
            System.Assert.areEqual(
                '\t;\t',
                RollupBuilderController.getDraft(result.recordId).customDelimiter,
                'The Builder'
            );
            System.Assert.areEqual('SP()SP()', RollupPlanner.encodeDelimiter('  '), 'Only spaces');
            System.Assert.areEqual('a b', RollupPlanner.encodeDelimiter('a b'), 'Inner stays');
        }
    }

    @IsTest
    static void aDelimiterSavedBeforeTokensExistedStillWorks() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c old = existing('Old delimiter', null);
            old.Aggregate__c = 'TEXT_LIST';
            old.Source_Object__c = 'Contact';
            old.Relationship_Path__c = 'AccountId';
            old.Source_Field__c = 'LastName';
            old.Target_Field__c = 'Description';
            old.Delimiter__c = RollupPlanner.CUSTOM_DELIMITER;
            // Saved before tokens: Salesforce had already trimmed it, so it never has edge spaces.
            old.Custom_Delimiter__c = '/';
            insert old;
            old = [
                SELECT Delimiter__c, Custom_Delimiter__c
                FROM Rollup_Definition__c
                WHERE Id = :old.Id
            ];

            System.Assert.areEqual('/', RollupPlanner.separatorOf(old), 'Used as it is');
            System.Assert.areEqual(
                '/',
                RollupBuilderController.getDraft(old.Id).customDelimiter,
                'Shown as it is'
            );
            System.Assert.areEqual(
                'a b',
                RollupPlanner.decodeDelimiter('a b'),
                'Inner spaces without tokens, no change'
            );
            System.Assert.isNull(RollupPlanner.decodeDelimiter(null), 'Nothing stays nothing');
        }
    }

    /** ADR-0136: the sum of the 5 largest, saved and read back for editing. */
    @IsTest
    static void aRowLimitAndItsDirectionAreSavedAndReadBack() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.Draft largest = childCount();
            largest.aggregate = 'SUM';
            largest.sourceField = 'NumberOfEmployees';
            largest.orderByField = 'NumberOfEmployees';
            largest.orderDirection = 'Descending';
            largest.rowLimit = 5;
            largest.includeDeleted = true;
            RollupBuilderController.SaveResult result;

            Test.startTest();
            System.runAs(maria()) {
                result = RollupBuilderController.save(largest, false);
            }
            Test.stopTest();

            RollupBuilderController.Draft reread = RollupBuilderController.getDraft(
                result.recordId
            );
            System.Assert.areEqual(5, reread.rowLimit, 'The limit');
            System.Assert.areEqual('Descending', reread.orderDirection, 'And its direction');
            System.Assert.isTrue(reread.includeDeleted, 'Deleted records included');
            largest.orderDirection = null;
            largest.rowLimit = null;
            largest.active = false; // the saved one fills the same field
            System.Assert.isNull(RollupBuilderController.problemWith(largest), 'Both optional');
        }
    }

    @IsTest
    static void saveAndCalculateNowStartsItsRecalculation() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.SaveResult result;
            Test.startTest();
            System.runAs(maria()) {
                result = RollupBuilderController.save(childCount(), true);
            }
            Test.stopTest();

            System.Assert.areEqual(Label.Core_RollupBuilder_SavedAndCalculating, result.notice);
            System.Assert.isNotNull(
                [SELECT Last_Calculated__c FROM Rollup_Definition__c WHERE Id = :result.recordId]
                .Last_Calculated__c,
                'The run finished and marked it calculated'
            );
        }
    }

    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String message;
            System.runAs(david) {
                message = saveRefusal(childCount());
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing saved');
        }
    }

    @IsTest
    static void eachSaveCheckSaysWhatToChange() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Map<String, RollupBuilderController.Draft> drafts = new Map<String, RollupBuilderController.Draft>();

            RollupBuilderController.Draft noName = childCount();
            noName.name = ' ';
            drafts.put(Label.Core_RollupBuilder_ErrorNameNeeded, noName);

            RollupBuilderController.Draft formula = childCount();
            formula.targetField = 'CreatedDate';
            drafts.put(Label.Core_Rollups_ErrorTargetNotWritable, formula);

            RollupBuilderController.Draft sumIntoCheckbox = childCount();
            sumIntoCheckbox.targetField = 'Deceased__c';
            drafts.put(Label.Core_Rollups_ErrorCheckboxTarget, sumIntoCheckbox);

            RollupBuilderController.Draft badPath = childCount();
            badPath.relationshipPath = 'Name';
            drafts.put(Label.Core_RollupBuilder_ErrorPathInvalid, badPath);

            RollupBuilderController.Draft sumOfText = childCount();
            sumOfText.aggregate = 'SUM';
            sumOfText.sourceField = 'Name';
            drafts.put(Label.Core_RollupBuilder_ErrorSumNeedsNumber, sumOfText);

            RollupBuilderController.Draft maxOfText = childCount();
            maxOfText.aggregate = 'MAX';
            maxOfText.sourceField = 'Name';
            drafts.put(Label.Core_RollupBuilder_ErrorMinMaxType, maxOfText);

            RollupBuilderController.Draft unordered = childCount();
            unordered.aggregate = 'LAST';
            unordered.sourceField = 'NumberOfEmployees';
            drafts.put(Label.Core_RollupBuilder_ErrorOrderByNeeded, unordered);

            RollupBuilderController.Draft limitedCount = childCount();
            limitedCount.rowLimit = 3;
            limitedCount.orderByField = 'NumberOfEmployees';
            drafts.put(Label.Core_Rollups_ErrorRowLimitAggregate, limitedCount);

            RollupBuilderController.Draft limitedUnordered = childCount();
            limitedUnordered.aggregate = 'SUM';
            limitedUnordered.sourceField = 'NumberOfEmployees';
            limitedUnordered.rowLimit = 3;
            drafts.put(Label.Core_Rollups_ErrorRowLimitNeedsOrder, limitedUnordered);

            RollupBuilderController.Draft emptyCustom = childCount();
            emptyCustom.delimiter = 'Custom';
            drafts.put(Label.Core_Rollups_ErrorCustomDelimiterNeeded, emptyCustom);

            RollupBuilderController.Draft noDate = childCount();
            noDate.fiscalYearAware = true;
            noDate.fiscalYearOffset = 0;
            noDate.fiscalDateField = 'Name';
            drafts.put(Label.Core_RollupBuilder_ErrorWindowNeedsDate, noDate);

            RollupBuilderController.Draft badWindow = childCount();
            badWindow.fiscalYearAware = true;
            badWindow.fiscalYearOffset = 5;
            badWindow.fiscalDateField = 'Anniversary__c';
            drafts.put(Label.Core_RollupBuilder_ErrorWindowInvalid, badWindow);

            RollupBuilderController.Draft unknownFilterField = childCount();
            unknownFilterField.filterJson = nameFilter('equals', 'x')
                .replace('"Name"', '"Nope__c"');
            drafts.put(Label.Core_RollupBuilder_ErrorFieldUnknown, unknownFilterField);

            RollupBuilderController.Draft unreadableFilter = childCount();
            unreadableFilter.filterJson = '{not json';
            drafts.put(Label.Core_Rollups_ErrorInvalidFilter, unreadableFilter);

            for (String expected : drafts.keySet()) {
                System.Assert.areEqual(
                    expected,
                    RollupBuilderController.problemWith(drafts.get(expected)),
                    'Refused with the message that says what to change'
                );
            }
            System.Assert.isNull(RollupBuilderController.problemWith(childCount()), 'A good one');
        }
    }

    /** ADR-0136: the filter offers and accepts a field one lookup away, and no further. */
    @IsTest
    static void aFilterReadsAFieldOneLookupAway() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Map<String, String> labelByPath = new Map<String, String>();
            for (
                RollupBuilderController.FieldOption option : RollupBuilderController.getParentFields(
                    'Account'
                )
            ) {
                labelByPath.put(option.value, option.label);
            }
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_ParentField,
                    new List<String>{
                        Account.ParentId.getDescribe().getLabel().removeEndIgnoreCase(' ID'),
                        Account.Name.getDescribe().getLabel()
                    }
                ),
                labelByPath.get('Parent.Name'),
                'The parent organization\'s name, labelled through its lookup'
            );
            System.Assert.isFalse(
                labelByPath.containsKey('CreatedBy.Name'),
                'Lookups the platform keeps for itself are not offered'
            );

            Map<String, String> expectedByPath = new Map<String, String>{
                'Parent.Name' => null,
                'parent.name' => null,
                'Parent.Nope__c' => Label.Core_RollupBuilder_ErrorFieldUnknown,
                'Nope__r.Name' => Label.Core_RollupBuilder_ErrorFieldUnknown,
                'Parent.Parent.Name' => Label.Core_RollupBuilder_ErrorOneLookup
            };
            for (String path : expectedByPath.keySet()) {
                RollupBuilderController.Draft draft = childCount();
                draft.filterJson = nameFilter('equals', 'Riverbend')
                    .replace('"Name"', '"' + path + '"');
                System.Assert.areEqual(
                    expectedByPath.get(path),
                    RollupBuilderController.problemWith(draft),
                    path
                );
            }
        }
    }

    /** R-R15: FIRST and LAST fill a picklist from a picklist or text, with values it has. */
    @IsTest
    static void aPicklistIsFilledFromAPicklistOrTextWithValuesItHas() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Map<String, String> sourceFieldByExpected = new Map<String, String>{
                'same picklist' => 'Preferred_Email__c',
                'text' => 'Name',
                Label.Core_RollupBuilder_ErrorPicklistSource => 'NumberOfEmployees',
                'missing values' => 'Household_Role__c'
            };
            for (String expected : sourceFieldByExpected.keySet()) {
                RollupBuilderController.Draft draft = childCount();
                draft.targetField = 'Preferred_Email__c';
                draft.aggregate = 'LAST';
                draft.sourceField = sourceFieldByExpected.get(expected);
                draft.orderByField = 'CreatedDate';
                String problem = RollupBuilderController.problemWith(draft);
                if (expected == 'missing values') {
                    System.Assert.isTrue(
                        problem.startsWith(
                            Label.Core_RollupBuilder_ErrorPicklistValues.substringBefore('{0}')
                        ) && problem.contains('Head'),
                        'Names the values the target lacks: ' + problem
                    );
                } else if (expected.startsWith('same') || expected == 'text') {
                    System.Assert.isNull(problem, expected);
                } else {
                    System.Assert.areEqual(expected, problem, 'Only a picklist or text');
                }
            }

            RollupBuilderController.Draft counted = childCount();
            counted.targetField = 'Preferred_Email__c';
            System.Assert.areEqual(
                Label.Core_Rollups_ErrorPicklistTarget,
                RollupBuilderController.problemWith(counted),
                'A count is no picklist value'
            );
            Boolean offered = false;
            for (
                RollupBuilderController.FieldOption option : RollupBuilderController.getTargetFields(
                    'Account'
                )
            ) {
                offered = offered || option.value == 'Preferred_Email__c';
            }
            System.Assert.isTrue(offered, 'A picklist is offered as a target');
        }
    }

    /** ROLLUPS-3: the window's bounds are dates, which SOQL refuses against a date and time. */
    @IsTest
    static void aFiscalWindowIsMeasuredOnADateFieldOnly() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.Draft onDatetime = childCount();
            onDatetime.fiscalYearAware = true;
            onDatetime.fiscalYearOffset = 0;
            onDatetime.fiscalDateField = 'CreatedDate';
            RollupBuilderController.Draft onDate = childCount();
            onDate.fiscalYearAware = true;
            onDate.fiscalYearOffset = 0;
            onDate.fiscalDateField = 'Anniversary__c';

            System.Assert.areEqual(
                Label.Core_RollupBuilder_ErrorWindowNeedsDate,
                RollupBuilderController.problemWith(onDatetime),
                'A date and time field is refused'
            );
            System.Assert.isNull(RollupBuilderController.problemWith(onDate), 'A date field');
        }
    }

    /**
     * ROLLUPS-8: a total that moves with the date is right only when every record is
     * recalculated, which Instantly alone never does.
     */
    @IsTest
    static void anInstantlyTotalThatMovesWithTheDateIsRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.Draft fiscal = childCount();
            fiscal.mode = RollupService.MODE_REAL_TIME;
            fiscal.fiscalYearAware = true;
            fiscal.fiscalYearOffset = 0;
            fiscal.fiscalDateField = 'Anniversary__c';
            RollupBuilderController.Draft recent = childCount();
            recent.mode = RollupService.MODE_REAL_TIME;
            recent.filterJson = JSON.serialize(
                new Map<String, Object>{
                    'version' => 1,
                    'conditions' => new List<Object>{
                        new Map<String, Object>{
                            'id' => 1,
                            'field' => 'Anniversary__c',
                            'operator' => 'last n days',
                            'value' => 30
                        }
                    }
                }
            );
            RollupBuilderController.Draft nightly = childCount();
            nightly.fiscalYearAware = true;
            nightly.fiscalYearOffset = 0;
            nightly.fiscalDateField = 'Anniversary__c';

            String fiscalRefusal;
            String recentRefusal;
            String nightlyRefusal;
            System.runAs(maria()) {
                fiscalRefusal = saveRefusal(fiscal);
                recentRefusal = saveRefusal(recent);
                nightlyRefusal = saveRefusal(nightly);
            }

            System.Assert.areEqual(
                Label.Core_RollupBuilder_ErrorInstantMovesWithDate,
                fiscalRefusal,
                'A fiscal year window'
            );
            System.Assert.areEqual(
                Label.Core_RollupBuilder_ErrorInstantMovesWithDate,
                recentRefusal,
                'A last n days condition'
            );
            System.Assert.isNull(nightlyRefusal, 'Both mode is saved');
            System.Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Definition__c], 'Only that one');
        }
    }

    /** ROLLUPS-14: the preview calculates in system mode, so it needs what a save needs. */
    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotPreview() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String message;
            System.runAs(david) {
                try {
                    RollupBuilderController.preview(childCount(), null);
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
        }
    }

    @IsTest
    static void aSecondRollupOnTheSameFieldForTheSameRecordsIsRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert existing('Child count', null);

            String message = RollupBuilderController.problemWith(childCount());

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_ErrorOverlap,
                    new List<String>{ 'Child count' }
                ),
                message,
                'Two rollups with no target filter fill every record twice (R-R8)'
            );
            RollupBuilderController.Draft inactive = childCount();
            inactive.active = false;
            System.Assert.isNull(
                RollupBuilderController.problemWith(inactive),
                'An inactive rollup overwrites nothing'
            );
        }
    }

    @IsTest
    static void targetFiltersThatShareARecordOverlapAndOnesThatDoNotAreAllowed() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert new Account(Name = 'Alpha Org');
            insert existing('Alpha count', nameFilter('starts with', 'Alpha'));

            RollupBuilderController.Draft overlapping = childCount();
            overlapping.targetFilterJson = nameFilter('contains', 'Org');
            RollupBuilderController.Draft disjoint = childCount();
            disjoint.targetFilterJson = nameFilter('starts with', 'Beta');

            System.Assert.isNotNull(
                RollupBuilderController.problemWith(overlapping),
                'Alpha Org meets both filters, so the two would overwrite each other'
            );
            System.Assert.isNull(
                RollupBuilderController.problemWith(disjoint),
                'No record meets both filters'
            );
        }
    }

    @IsTest
    static void theOverlapCheckStaysWithinLimitsWithTwoHundredRollups() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<Rollup_Definition__c> others = new List<Rollup_Definition__c>();
            for (Integer i = 0; i < 200; i++) {
                Rollup_Definition__c other = existing('Other ' + i, nameFilter('equals', 'X' + i));
                other.Target_Field__c = 'Anniversary__c';
                other.Aggregate__c = 'MAX';
                other.Source_Field__c = 'Anniversary__c';
                others.add(other);
            }
            insert others;

            Test.startTest();
            String problem = RollupBuilderController.problemWith(childCount());
            Integer queries = Limits.getQueries();
            Test.stopTest();

            System.Assert.isNull(problem, 'None of them fills the same field');
            System.Assert.isTrue(queries < 5, 'Rollups on other fields cost no query each');
        }
    }

    // --------------------------------------------------------------------- preview (slice S12)

    /** A parent organization holding a stale count, with this many child organizations. */
    private static Account parentWith(Integer children) {
        Account parent = new Account(Name = 'Parent Org', Member_Count__c = 5);
        insert parent;
        List<Account> kids = new List<Account>();
        for (Integer i = 0; i < children; i++) {
            kids.add(new Account(Name = 'Child ' + i, ParentId = parent.Id));
        }
        insert kids;
        return parent;
    }

    @IsTest
    static void thePreviewShowsTheTotalNextToWhatTheRecordHoldsAndSavesNothing() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User admin = maria();
            RollupBuilderController.PreviewResult preview;
            Account parent;

            Test.startTest();
            System.runAs(admin) {
                parent = parentWith(200);
                RollupBuilderController.Draft draft = childCount();
                draft.name = null;
                preview = RollupBuilderController.preview(draft, parent.Id);
            }
            Test.stopTest();

            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_PreviewResult,
                    new List<String>{ (200).format(), (5).format() }
                ),
                preview.result,
                'Two hundred children counted, next to the five the record holds'
            );
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_Maintains,
                    new List<String>{ (201).format() }
                ),
                preview.maintains,
                'Every account she can see is one the rollup maintains'
            );
            System.Assert.areEqual(
                5,
                [SELECT Member_Count__c FROM Account WHERE Id = :parent.Id].Member_Count__c,
                'A preview writes nothing'
            );
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nor saves it');
        }
    }

    @IsTest
    static void thePreviewSaysWhenTheRecordIsNotOneTheRollupFills() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.PreviewResult preview;
            System.runAs(maria()) {
                Account parent = parentWith(2);
                RollupBuilderController.Draft draft = childCount();
                draft.targetFilterJson = nameFilter('starts with', 'Beta');
                preview = RollupBuilderController.preview(draft, parent.Id);
            }

            System.Assert.areEqual(Label.Core_RollupBuilder_PreviewNotFilled, preview.result);
            System.Assert.areEqual(
                String.format(Label.Core_RollupBuilder_Maintains, new List<String>{ (0).format() }),
                preview.maintains,
                'No account starts with Beta'
            );
        }
    }

    @IsTest
    static void thePreviewWithoutARecordCountsOnlyAndAnUnfinishedDraftIsRefused() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.PreviewResult preview;
            String refusal;
            System.runAs(maria()) {
                preview = RollupBuilderController.preview(childCount(), null);
                RollupBuilderController.Draft unfinished = childCount();
                unfinished.targetField = null;
                try {
                    RollupBuilderController.preview(unfinished, null);
                } catch (AuraHandledException refused) {
                    refusal = refused.getMessage();
                }
            }

            System.Assert.isNull(preview.result, 'No record picked, no total');
            System.Assert.isNotNull(preview.maintains);
            System.Assert.areEqual(Label.Core_RollupBuilder_ErrorTargetNeeded, refusal);
        }
    }

    @IsTest
    static void emptyValuesReadAsEmpty() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.areEqual(
                Label.Core_RollupBuilder_PreviewEmpty,
                RollupBuilderController.display(null)
            );
            System.Assert.areEqual(
                Date.newInstance(2026, 10, 12).format(),
                RollupBuilderController.display(Date.newInstance(2026, 10, 12))
            );
        }
    }
}
