/**
 * Import from DLRS (canonical model R-R16): DLRS-shaped rows handed to `RollupDlrs`'s reader
 * seam are mapped one operation at a time, refused with a reason when BarnCRM cannot hold them,
 * copied switched off through the Builder's checks, compared on sample records and turned on
 * only with the administrator's word. Organizations total their child organizations, as in
 * `RollupDlrsTest`.
 */
@IsTest(testFor='ApexClass:RollupDlrsImport')
private class RollupDlrsImportTest {
    private static final String COUNT_FIELD = 'Member_Count__c';
    private static final String TEXT_FIELD = 'Household_Informal_Greeting__c';

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

    /** An active DLRS rollup of child organizations into their parent, with these values. */
    private static RollupDlrs.Definition dlrs(
        String key,
        String operation,
        String field,
        Map<String, Object> extra
    ) {
        Map<String, Object> values = new Map<String, Object>{
            'Active__c' => true,
            'ParentObject__c' => 'Account',
            'ChildObject__c' => 'Account',
            'RelationshipField__c' => 'ParentId',
            'AggregateOperation__c' => operation,
            'AggregateResultField__c' => field,
            'CalculationMode__c' => 'Realtime'
        };
        values.putAll(extra == null ? new Map<String, Object>() : extra);
        return RollupDlrsFake.rollup(key, values);
    }

    private static Map<String, RollupDlrsImport.Candidate> byKey(
        List<RollupDlrsImport.Candidate> candidates
    ) {
        Map<String, RollupDlrsImport.Candidate> found = new Map<String, RollupDlrsImport.Candidate>();
        for (RollupDlrsImport.Candidate candidate : candidates) {
            found.put(candidate.key, candidate);
        }
        return found;
    }

    private static Boolean startsLike(List<String> messages, String template) {
        String start = template.substringBefore('{0}');
        for (String message : messages) {
            if (message.startsWith(start)) {
                return true;
            }
        }
        return false;
    }

    // --------------------------------------------------------------------------- without DLRS

    @IsTest
    static void withoutDlrsThereIsNothingToImport() {
        System.runAs(maria()) {
            OtherRollupTools.overrideForTest(new Set<String>());

            Assert.isTrue(RollupDlrsImport.getCandidates().isEmpty(), 'Nothing to import');
            Assert.isTrue(
                RollupDlrsImport.importRollups(new List<String>{ 'Anything' }).isEmpty(),
                'Nothing copied'
            );
        }
    }

    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotImport() {
        // An administrator creates David: a user on the standard profile cannot insert a user.
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ dlrs('Child_Total', 'Count', COUNT_FIELD, null) }
            );
            String message;
            System.runAs(david) {
                try {
                    RollupDlrsImport.getCandidates();
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }
            Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message, 'Refused');
        }
    }

    // -------------------------------------------------------------------------------- mapping

    @IsTest
    static void eachDlrsOperationMapsToItsBarnCrmTotal() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    dlrs(
                        'R_Sum',
                        'Sum',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    ),
                    dlrs(
                        'R_Max',
                        'Max',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    ),
                    dlrs(
                        'R_Min',
                        'min',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    ),
                    dlrs(
                        'R_Avg',
                        'Avg',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    ),
                    dlrs(
                        'R_Count',
                        'Count',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'Id' }
                    ),
                    dlrs(
                        'R_Distinct',
                        'Count Distinct',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    ),
                    dlrs(
                        'R_List',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'ConcatenateDelimiter__c' => ', '
                        }
                    ),
                    dlrs(
                        'R_List_Distinct',
                        'Concatenate  Distinct',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'ConcatenateDelimiter__c' => '; '
                        }
                    ),
                    dlrs(
                        'R_First',
                        'First',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'CreatedDate ASC NULLS LAST'
                        }
                    ),
                    dlrs(
                        'R_Last',
                        'Last',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'CreatedDate ASC NULLS LAST'
                        }
                    ),
                    dlrs(
                        'R_Inactive',
                        'Sum',
                        COUNT_FIELD,
                        new Map<String, Object>{ 'Active__c' => false }
                    )
                }
            );

            Map<String, RollupDlrsImport.Candidate> found = byKey(RollupDlrsImport.getCandidates());

            Map<String, String> aggregateByKey = new Map<String, String>{
                'R_Sum' => 'SUM',
                'R_Max' => 'MAX',
                'R_Min' => 'MIN',
                'R_Avg' => 'AVG',
                'R_Count' => 'COUNT',
                'R_Distinct' => 'COUNT_DISTINCT',
                'R_List' => 'TEXT_LIST',
                'R_List_Distinct' => 'TEXT_LIST_DISTINCT',
                'R_First' => 'FIRST',
                'R_Last' => 'LAST'
            };
            Assert.areEqual(aggregateByKey.size(), found.size(), 'Active DLRS rollups only');
            for (String key : aggregateByKey.keySet()) {
                RollupDlrsImport.Candidate candidate = found.get(key);
                Assert.areEqual(aggregateByKey.get(key), candidate.draft.aggregate, key);
                Assert.isTrue(candidate.importable, key + ': ' + candidate.reasons);
                Assert.isFalse(candidate.draft.active, key + ' is copied switched off');
                Assert.areEqual(RollupService.MODE_BOTH, candidate.draft.mode, key + ' realtime');
                Assert.areEqual('Account', candidate.draft.sourceObject, key);
                Assert.areEqual('ParentId', candidate.draft.relationshipPath, key);
            }
            Assert.isNull(found.get('R_Count').draft.sourceField, 'A count reads no field');
            Assert.isNull(found.get('R_Count').draft.filterJson, 'Counting Id is no filter');
            Assert.areEqual('Comma', found.get('R_List').draft.delimiter, 'Comma');
            Assert.areEqual('Semicolon', found.get('R_List_Distinct').draft.delimiter, 'Semicolon');
            Assert.areEqual('CreatedDate', found.get('R_First').draft.orderByField, 'Order');
            Assert.isFalse(
                found.get('R_First').notes.contains(Label.Core_RollupBuilder_DlrsNoteBlanksLast),
                'NULLS LAST is how BarnCRM orders already'
            );
            Assert.isTrue(
                found.get('R_Sum')
                    .draft.description.startsWith(
                        String.format(
                            Label.Core_RollupBuilder_DlrsImportedFrom,
                            new List<String>{ 'R_Sum' }
                        )
                    ),
                'The description names the DLRS rollup'
            );
        }
    }

    @IsTest
    static void whatChangesInTheCopyIsSaidAsANote() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    dlrs(
                        'Counted_Field',
                        'Count',
                        COUNT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'NumberOfEmployees',
                            'RelationshipCriteria__c' => 'Name != null',
                            'AggregateAllRows__c' => true
                        }
                    ),
                    dlrs(
                        'Newest_Name',
                        'First',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'CreatedDate DESC',
                            'RowLimit__c' => 1,
                            'CalculationMode__c' => 'Process Builder',
                            'CalculationSharingMode__c' => 'User'
                        }
                    ),
                    dlrs(
                        'Unordered_Name',
                        'Last',
                        TEXT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'Name' }
                    ),
                    dlrs(
                        'Names_Down',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name DESC',
                            // As DLRS stores "; ": Salesforce trims the space on save.
                            'ConcatenateDelimiter__c' => ';SP()'
                        }
                    ),
                    dlrs(
                        'Names_Slash',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name',
                            'ConcatenateDelimiter__c' => '/SP()TB()x'
                        }
                    ),
                    dlrs(
                        'Names_Plain',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name',
                            'CalculationMode__c' => 'Scheduled'
                        }
                    ),
                    dlrs(
                        'Top_Three',
                        'Sum',
                        COUNT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'NumberOfEmployees',
                            'FieldToOrderBy__c' => 'NumberOfEmployees DESC NULLS LAST',
                            'RowLimit__c' => 3
                        }
                    )
                }
            );

            Map<String, RollupDlrsImport.Candidate> found = byKey(RollupDlrsImport.getCandidates());

            RollupDlrsImport.Candidate counted = found.get('Counted_Field');
            Assert.isTrue(counted.importable, String.valueOf(counted.reasons));
            Map<String, Object> filter = (Map<String, Object>) JSON.deserializeUntyped(
                counted.draft.filterJson
            );
            Assert.areEqual('(1) AND 2', filter.get('logic'), 'The criteria and the counted field');
            Assert.isTrue(
                startsLike(counted.notes, Label.Core_RollupBuilder_DlrsNoteCountField),
                'Said'
            );
            Assert.isTrue(counted.draft.includeDeleted, 'All rows include deleted records');

            RollupDlrsImport.Candidate newest = found.get('Newest_Name');
            Assert.isTrue(newest.importable, String.valueOf(newest.reasons));
            Assert.areEqual('LAST', newest.draft.aggregate, 'A descending First is a Last');
            Assert.isNull(newest.draft.rowLimit, 'No row limit on a single value');
            Assert.isTrue(
                newest.notes.contains(Label.Core_RollupBuilder_DlrsNoteRowLimitFirst),
                'Said'
            );
            Assert.isTrue(
                newest.notes.contains(Label.Core_RollupBuilder_DlrsNoteSystemMode),
                'Said'
            );
            Assert.isTrue(
                startsLike(newest.notes, Label.Core_RollupBuilder_DlrsNoteCalledByCode),
                'Said'
            );
            Assert.areEqual(
                RollupService.MODE_BOTH,
                newest.draft.mode,
                'Updated as records change'
            );

            RollupDlrsImport.Candidate unordered = found.get('Unordered_Name');
            Assert.areEqual('Name', unordered.draft.orderByField, 'Ordered by the field itself');
            Assert.isTrue(
                startsLike(unordered.notes, Label.Core_RollupBuilder_DlrsNoteNoOrder),
                'Said'
            );

            RollupDlrsImport.Candidate down = found.get('Names_Down');
            Assert.areEqual('Descending', down.draft.orderDirection, 'A list keeps its direction');
            Assert.areEqual('Semicolon', down.draft.delimiter, 'SP() is a space: Semicolon');
            Assert.isNull(down.draft.customDelimiter, 'Nothing custom');

            RollupDlrsImport.Candidate slash = found.get('Names_Slash');
            Assert.isTrue(slash.importable, 'Copied');
            Assert.areEqual(RollupPlanner.CUSTOM_DELIMITER, slash.draft.delimiter, 'Custom');
            Assert.areEqual('/ \tx', slash.draft.customDelimiter, 'SP() a space, TB() a tab');

            RollupDlrsImport.Candidate plain = found.get('Names_Plain');
            Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                plain.draft.mode,
                'Nightly stays nightly'
            );
            Assert.areEqual('Comma', plain.draft.delimiter, 'No delimiter is a comma');
            Assert.isTrue(
                plain.notes.contains(Label.Core_RollupBuilder_DlrsNoteNoDelimiter),
                'Said'
            );
            Assert.isTrue(
                plain.notes.contains(Label.Core_RollupBuilder_DlrsNoteBlanksLast),
                'Said'
            );

            RollupDlrsImport.Candidate topThree = found.get('Top_Three');
            Assert.isTrue(topThree.importable, String.valueOf(topThree.reasons));
            Assert.areEqual(3, topThree.draft.rowLimit, 'The row limit is kept');
            Assert.areEqual('Descending', topThree.draft.orderDirection, 'Largest first');
        }
    }

    @IsTest
    static void whatBarnCrmCannotHoldStaysInDlrsWithAReason() {
        System.runAs(maria()) {
            Rollup_Definition__c otherRollup = new Rollup_Definition__c(
                Name = 'Our own count',
                Definition_Key__c = 'Test_Own_Count',
                Source_Object__c = 'Account',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'ParentId',
                Aggregate__c = 'COUNT',
                Target_Field__c = COUNT_FIELD,
                Mode__c = RollupService.MODE_BOTH,
                Active__c = true
            );
            insert as user otherRollup;
            Map<String, Object> name = new Map<String, Object>{ 'FieldToAggregate__c' => 'Name' };
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    dlrs('Median', 'Median', TEXT_FIELD, name),
                    dlrs(
                        'Subquery',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'RelationshipCriteria__c' => 'Id IN (SELECT ParentId FROM Account)'
                        }
                    ),
                    dlrs(
                        'Two_Orders',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name, CreatedDate'
                        }
                    ),
                    dlrs(
                        'Blanks_First',
                        'First',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name ASC NULLS FIRST'
                        }
                    ),
                    dlrs(
                        'Limited_Last',
                        'Last',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'FieldToOrderBy__c' => 'Name',
                            'RowLimit__c' => 2
                        }
                    ),
                    dlrs(
                        'Long_Delimiter',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'ConcatenateDelimiter__c' => ' and also then '
                        }
                    ),
                    dlrs(
                        'Spaced_Delimiter',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            // " - ": the Custom Delimiter would be trimmed to "-" on save.
                            'ConcatenateDelimiter__c' => 'SP()-SP()'
                        }
                    ),
                    dlrs(
                        'No_Path',
                        'Concatenate',
                        TEXT_FIELD,
                        new Map<String, Object>{
                            'FieldToAggregate__c' => 'Name',
                            'RelationshipField__c' => 'No_Such_Lookup__c'
                        }
                    ),
                    dlrs('Filled', 'Count', COUNT_FIELD, null),
                    dlrs(
                        'Wrong_Type',
                        'Sum',
                        TEXT_FIELD,
                        new Map<String, Object>{ 'FieldToAggregate__c' => 'NumberOfEmployees' }
                    )
                }
            );

            Map<String, RollupDlrsImport.Candidate> found = byKey(RollupDlrsImport.getCandidates());

            Map<String, String> templateByKey = new Map<String, String>{
                'Median' => Label.Core_RollupBuilder_DlrsReasonOperation,
                'Subquery' => Label.Core_RollupBuilder_DlrsReasonCriteria,
                'Two_Orders' => Label.Core_RollupBuilder_DlrsReasonOrder,
                'Blanks_First' => Label.Core_RollupBuilder_DlrsReasonOrder,
                'Limited_Last' => Label.Core_RollupBuilder_DlrsReasonRowLimit,
                'Long_Delimiter' => Label.Core_RollupBuilder_DlrsReasonDelimiter,
                'Spaced_Delimiter' => Label.Core_RollupBuilder_DlrsReasonDelimiter,
                'No_Path' => Label.Core_RollupBuilder_DlrsReasonPath,
                'Filled' => Label.Core_RollupBuilder_DlrsReasonFilled,
                'Wrong_Type' => Label.Core_Rollups_ErrorTextTarget
            };
            for (String key : templateByKey.keySet()) {
                RollupDlrsImport.Candidate candidate = found.get(key);
                Assert.isFalse(candidate.importable, key + ' stays in DLRS');
                Assert.isTrue(
                    startsLike(candidate.reasons, templateByKey.get(key)),
                    key + ' says why: ' + candidate.reasons
                );
            }

            List<RollupDlrsImport.ImportRow> rows = RollupDlrsImport.importRollups(
                new List<String>(templateByKey.keySet())
            );
            Assert.areEqual(templateByKey.size(), rows.size(), 'Each one answered');
            for (RollupDlrsImport.ImportRow row : rows) {
                Assert.areEqual(RollupDlrsImport.REFUSED, row.outcome, row.key);
                Assert.isNotNull(row.reason, row.key + ' says why');
            }
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Rollup_Definition__c WITH USER_MODE],
                'Nothing copied'
            );
        }
    }

    // -------------------------------------------------------------------- copy, compare, on

    @IsTest
    static void aCopyIsSavedSwitchedOffAndUpdatedWhenImportedAgain() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    dlrs('Child_Total', 'Count', COUNT_FIELD, null),
                    dlrs('Not_Chosen', 'Count', COUNT_FIELD, null)
                }
            );

            List<RollupDlrsImport.ImportRow> first = RollupDlrsImport.importRollups(
                new List<String>{ 'child_total' }
            );
            List<RollupDlrsImport.ImportRow> again = RollupDlrsImport.importRollups(
                new List<String>{ 'Child_Total' }
            );

            Assert.areEqual(1, first.size(), 'Only the chosen one');
            Assert.areEqual(RollupDlrsImport.CREATED, first[0].outcome, String.valueOf(first[0]));
            Assert.areEqual(RollupDlrsImport.UPDATED, again[0].outcome, 'The same copy');
            Assert.areEqual(first[0].recordId, again[0].recordId, 'Not a second one');
            Rollup_Definition__c copy = [
                SELECT Name, Definition_Key__c, Active__c, Aggregate__c
                FROM Rollup_Definition__c
                WITH USER_MODE
            ];
            Assert.areEqual('DLRS_Child_Total', copy.Definition_Key__c, 'Keyed by the DLRS name');
            Assert.areEqual('Child Total', copy.Name, 'Named as in DLRS');
            Assert.isFalse(copy.Active__c, 'Switched off');
            Assert.isTrue(RollupDlrs.definitions()[0].active, 'DLRS is never changed');
        }
    }

    @IsTest
    static void theCompareStepShowsBothValuesAndSavesNothing() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ dlrs('Child_Total', 'Count', COUNT_FIELD, null) }
            );
            Account parent = new Account(Name = 'Parent Org', Member_Count__c = 2);
            Account stale = new Account(Name = 'Stale Org', Member_Count__c = 7);
            insert new List<Account>{ parent, stale };
            insert new List<Account>{
                new Account(Name = 'Child 1', ParentId = parent.Id),
                new Account(Name = 'Child 2', ParentId = parent.Id)
            };
            Id copyId = RollupDlrsImport.importRollups(new List<String>{ 'Child_Total' })[0]
                .recordId;

            Test.startTest();
            List<RollupDlrsImport.Comparison> compared = RollupDlrsImport.compare(copyId);
            Test.stopTest();

            Assert.isTrue(compared.size() <= RollupDlrsImport.SAMPLE_SIZE, 'A few records');
            Map<Id, RollupDlrsImport.Comparison> byRecord = new Map<Id, RollupDlrsImport.Comparison>();
            for (RollupDlrsImport.Comparison comparison : compared) {
                byRecord.put(comparison.recordId, comparison);
            }
            Assert.isTrue(byRecord.get(parent.Id).agree, 'Two children, two counted');
            Assert.areEqual('Parent Org', byRecord.get(parent.Id).recordName, 'Named');
            Assert.isFalse(byRecord.get(stale.Id).agree, 'Seven written, none counted');
            Assert.isNotNull(byRecord.get(stale.Id).difference, 'Says how');
            Assert.areEqual(
                7,
                [SELECT Member_Count__c FROM Account WHERE Id = :stale.Id WITH USER_MODE]
                .Member_Count__c,
                'Nothing written'
            );
        }
    }

    @IsTest
    static void aCopyIsTurnedOnOnlyWithTheConfirmationWhichIsRecorded() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ dlrs('Child_Total', 'Count', COUNT_FIELD, null) }
            );
            Id copyId = RollupDlrsImport.importRollups(new List<String>{ 'Child_Total' })[0]
                .recordId;

            String refusal;
            try {
                RollupDlrsImport.turnOn(copyId, false);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Assert.areEqual(Label.Core_RollupBuilder_DlrsActivateNeedsConfirm, refusal, 'Asks');
            Assert.isFalse(
                [SELECT Active__c FROM Rollup_Definition__c WHERE Id = :copyId WITH USER_MODE]
                .Active__c,
                'Still off'
            );

            RollupDlrsImport.ImportRow turnedOn = RollupDlrsImport.turnOn(copyId, true);

            Assert.areEqual(RollupDlrsImport.ACTIVE, turnedOn.outcome, 'Turned on');
            Assert.isTrue(
                [SELECT Active__c FROM Rollup_Definition__c WHERE Id = :copyId WITH USER_MODE]
                .Active__c,
                'On'
            );
            List<Setting_Change__c> changes = [
                SELECT New_Value__c
                FROM Setting_Change__c
                WITH SYSTEM_MODE
            ];
            Assert.areEqual(1, changes.size(), 'The answer is recorded');
            Assert.areEqual(
                Label.Core_RollupBuilder_DlrsHistoryConfirmed,
                changes[0].New_Value__c,
                'As confirmed'
            );
            RollupDlrsImport.Candidate again = RollupDlrsImport.getCandidates()[0];
            Assert.isFalse(again.importable, 'Not copied twice');
            Assert.isTrue(
                again.reasons.contains(Label.Core_RollupBuilder_DlrsReasonAlreadyOn),
                'Already on'
            );
        }
    }

    // runs-as: deploying user (pure logic, no records and no sharing)
    @IsTest
    static void theDifferenceIsSaidInWords() {
        Map<String, List<Object>> valuesByExpected = new Map<String, List<Object>>{
            'same number' => new List<Object>{ 2, 2.0 },
            'same text' => new List<Object>{ 'a, b', 'a, b' },
            'blank text' => new List<Object>{ '', null },
            Label.Core_RollupBuilder_DlrsCompareBlankZero => new List<Object>{ 0, null },
            Label.Core_RollupBuilder_DlrsCompareDiffer => new List<Object>{ 'a', 'b' }
        };
        for (String expected : valuesByExpected.keySet()) {
            RollupEngine.Preview preview = new RollupEngine.Preview();
            preview.planned = true;
            preview.calculated = valuesByExpected.get(expected)[0];
            preview.current = valuesByExpected.get(expected)[1];
            String difference = RollupDlrsImport.differenceOf(preview);
            if (expected.startsWith('same') || expected.startsWith('blank')) {
                Assert.isNull(difference, expected);
            } else {
                Assert.areEqual(expected, difference, expected);
            }
        }
        Assert.areEqual(
            Label.Core_RollupBuilder_DlrsCompareNotCalculated,
            RollupDlrsImport.differenceOf(new RollupEngine.Preview()),
            'Not planned'
        );
    }
}
