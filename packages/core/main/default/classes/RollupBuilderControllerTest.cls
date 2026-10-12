/**
 * The Rollup Builder's reads and its save (R-R10, R-R8, slice S11). Core holds no giving objects,
 * so organizations count their child organizations (`ParentId`) into Account fields BarnCRM ships,
 * which the BarnCRM Admin permission set lets Maria edit.
 */
@IsTest
private class RollupBuilderControllerTest {
    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
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
    static void theModelOffersAccountAndCustomObjectsButNotBookkeeping() {
        RollupBuilderController.BuilderModel model = RollupBuilderController.getModel();

        Set<String> targets = new Set<String>();
        for (RollupBuilderController.Option option : model.targets) {
            targets.add(option.value.toLowerCase());
        }
        System.Assert.isTrue(targets.contains('account'), 'Account can show a total');
        for (String target : targets) {
            System.Assert.isFalse(
                target.endsWith('rollup_queue__c') || target.endsWith('error_log__c'),
                'BarnCRM bookkeeping is never offered: ' + target
            );
        }
        System.Assert.isFalse(model.aggregates.isEmpty(), 'Every calculation is offered');
        System.Assert.areEqual(3, model.modes.size(), 'The three modes are offered');
    }

    @IsTest
    static void targetFieldsAreWritableAndShowTheRollupThatFillsThem() {
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
        System.Assert.isTrue(byName.containsKey('deceased__c'), 'A checkbox can hold Any or None');
        System.Assert.isFalse(byName.containsKey('createddate'), 'A system field is never offered');
        System.Assert.isFalse(
            byName.containsKey('rollups_last_calculated__c'),
            'The freshness stamp is the engine own field'
        );
    }

    @IsTest
    static void sourcesOfferEveryLinkAndThePersonsHousehold() {
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

    @IsTest
    static void sourceFieldsCarryTheirTypeAndPicklistValues() {
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

    @IsTest
    static void anUnknownObjectIsRefusedInPlainWords() {
        try {
            RollupBuilderController.getTargetFields('No_Such_Object__c');
            System.Assert.fail('An object the org does not have is refused');
        } catch (AuraHandledException refused) {
            System.Assert.areEqual(Label.Core_Rollups_ErrorUnknownObject, refused.getMessage());
        }
    }

    // ----------------------------------------------------------------------------------- saving

    @IsTest
    static void mariaSavesANewRollupInUserModeWithItsOwnKey() {
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
        System.Assert.isTrue(saved.Definition_Key__c.startsWith('Custom_'), 'A new key is made');
        System.Assert.isFalse(saved.Is_Package_Default__c, 'It is her own rollup');
        System.Assert.areEqual(admin.Id, saved.CreatedById, 'Saved as Maria, not the package');
        System.Assert.areEqual(Label.Core_RollupBuilder_Saved, result.notice);
    }

    @IsTest
    static void editingAShippedRollupKeepsItsKey() {
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

    @IsTest
    static void saveAndCalculateNowStartsItsRecalculation() {
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

    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotSave() {
        User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
        String message;
        System.runAs(david) {
            message = saveRefusal(childCount());
        }
        System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
        System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing saved');
    }

    @IsTest
    static void eachSaveCheckSaysWhatToChange() {
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
        unknownFilterField.filterJson = nameFilter('equals', 'x').replace('"Name"', '"Nope__c"');
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

    @IsTest
    static void aSecondRollupOnTheSameFieldForTheSameRecordsIsRefused() {
        insert existing('Child count', null);

        String message = RollupBuilderController.problemWith(childCount());

        System.Assert.areEqual(
            String.format(Label.Core_RollupBuilder_ErrorOverlap, new List<String>{ 'Child count' }),
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

    @IsTest
    static void targetFiltersThatShareARecordOverlapAndOnesThatDoNotAreAllowed() {
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

    @IsTest
    static void theOverlapCheckStaysWithinLimitsWithTwoHundredRollups() {
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
            String.format(Label.Core_RollupBuilder_Maintains, new List<String>{ (201).format() }),
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

    @IsTest
    static void thePreviewSaysWhenTheRecordIsNotOneTheRollupFills() {
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

    @IsTest
    static void thePreviewWithoutARecordCountsOnlyAndAnUnfinishedDraftIsRefused() {
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

    @IsTest
    static void emptyValuesReadAsEmpty() {
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
