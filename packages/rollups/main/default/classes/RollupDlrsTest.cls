/**
 * DLRS in the same org (canonical model R-R16): without DLRS everything is quietly off; with
 * DLRS-shaped rows handed to the reader seam, the Builder's save, the list's switch and Health
 * Check refuse or report a field both tools fill, and a turn on the admin confirmed is recorded.
 * Organizations count their child organizations into Account's Member Count, as in
 * `RollupBuilderControllerTest`.
 */
@IsTest(testFor='ApexClass:RollupDlrs')
private class RollupDlrsTest {
    private static final String FIELD = 'Member_Count__c';

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

    private static RollupBuilderController.Draft childCount(Boolean active) {
        RollupBuilderController.Draft draft = new RollupBuilderController.Draft();
        draft.name = 'Child organization count';
        draft.targetObject = 'Account';
        draft.targetField = FIELD;
        draft.sourceObject = 'Account';
        draft.relationshipPath = 'ParentId';
        draft.aggregate = 'COUNT';
        draft.mode = RollupService.MODE_BOTH;
        draft.active = active;
        return draft;
    }

    private static Rollup_Definition__c existing(Boolean active) {
        Rollup_Definition__c definition = new Rollup_Definition__c(
            Name = 'Child organization count',
            Definition_Key__c = 'Test_Child_Count',
            Description__c = 'Counts child organizations.',
            Source_Object__c = 'Account',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Field__c = FIELD,
            Mode__c = RollupService.MODE_BOTH,
            Active__c = active
        );
        insert as user definition;
        return definition;
    }

    private static List<Setting_Change__c> changes() {
        return [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c
            FROM Setting_Change__c
            WITH SYSTEM_MODE
        ];
    }

    // --------------------------------------------------------------------------- without DLRS

    @IsTest
    static void withoutDlrsEverythingIsQuietlyOff() {
        System.runAs(maria()) {
            OtherRollupTools.overrideForTest(new Set<String>());

            RollupBuilderController.SaveResult saved = RollupBuilderController.save(
                childCount(true),
                false
            );

            Assert.isTrue(RollupDlrs.definitions().isEmpty(), 'Nothing is read without DLRS');
            Assert.isNull(RollupDlrs.conflict('Account', FIELD), 'No field is shared');
            Assert.isNull(saved.confirmation, 'Nothing is asked');
            Assert.isNotNull(saved.recordId, 'The rollup saves as before');
            Assert.isNull(
                RollupController.getPage().rollups[0].otherToolConflict,
                'The list asks nothing either'
            );
            Assert.isNull(
                new RollupsHealthCheckExtension.SameFieldCheck().run(),
                'Health Check has nothing to say'
            );
            Assert.isTrue(changes().isEmpty(), 'Nothing is recorded');
        }
    }

    @IsTest
    static void aStoreNotInThisOrgReadsNothing() {
        System.runAs(maria()) {
            Assert.isTrue(
                RollupDlrs.readFrom(
                        OtherRollupTools.DLRS_NAMESPACE + '__',
                        'NoSuchStore__c',
                        'Name',
                        'Name',
                        RollupDlrs.SOURCE_OBJECT
                    )
                    .isEmpty(),
                'No rows, and no failure'
            );

            // The org reader with the namespace found: nothing where DLRS's stores are missing,
            // and in an org with DLRS installed only its custom metadata rows, since a test sees
            // no records of DLRS's older object. Either way nothing fails.
            OtherRollupTools.overrideForTest(new Set<String>{ OtherRollupTools.DLRS_NAMESPACE });
            for (RollupDlrs.Definition read : RollupDlrs.definitions()) {
                Assert.areEqual(
                    RollupDlrs.SOURCE_METADATA,
                    read.source,
                    'Only custom metadata is seen'
                );
            }
        }
    }

    @IsTest
    static void aStoreIsReadThroughDescribeAndOnlyTheFieldsItHas() {
        System.runAs(maria()) {
            existing(true);

            // Rollup_Definition__c has two of the DLRS field names, Active and Description, so the
            // org reader's own code reads it with no prefix.
            List<RollupDlrs.Definition> read = RollupDlrs.readFrom(
                '',
                'Rollup_Definition__c',
                'Name',
                'Name',
                RollupDlrs.SOURCE_OBJECT
            );

            Assert.areEqual(1, read.size(), 'One row');
            Assert.areEqual('Child organization count', read[0].key, 'Keyed by the name field');
            Assert.isTrue(read[0].active, 'Active is read');
            Assert.areEqual('Counts child organizations.', read[0].description, 'And Description');
            Assert.isNull(read[0].parentObject, 'A field the store lacks is left blank');
            Assert.areEqual(RollupDlrs.SOURCE_OBJECT, read[0].source, 'Where it came from');
        }
    }

    // ------------------------------------------------------------------------- reading values

    @IsTest
    static void dlrsValuesAreReadInAnyCase() {
        // runs-as: deploying user (pure logic: builds a definition from a map, no DML or SOQL)
        RollupDlrs.Definition read = RollupDlrs.fromValues(
            'Gift_List',
            'Gift list',
            RollupDlrs.SOURCE_METADATA,
            new Map<String, Object>{
                'ACTIVE__C' => true,
                'rowlimit__c' => 5.0,
                'AggregateAllRows__c' => true,
                'ConcatenateDelimiter__c' => ' ',
                'AggregateOperation__c' => '  Concatenate ',
                'UniqueName__c' => 'GiftList'
            }
        );

        Assert.isTrue(read.active, 'Active in capitals');
        Assert.areEqual(5, read.rowLimit, 'A number row limit');
        Assert.isTrue(read.allRows, 'ALL ROWS');
        Assert.areEqual(' ', read.concatenateDelimiter, 'A space delimiter is kept');
        Assert.areEqual('Concatenate', read.aggregateOperation, 'Text is trimmed');
        Assert.areEqual('GiftList', read.key, 'The older object keys by its Unique Name');
        Assert.areEqual('Gift list', read.label, 'The label');
    }

    @IsTest
    static void onlyAnActiveDlrsRollupOnTheSameFieldCounts() {
        System.runAs(maria()) {
            RollupDlrs.Definition inactive = RollupDlrsFake.activeOn('Account', FIELD);
            inactive.active = false;
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    inactive,
                    RollupDlrsFake.activeOn('Account', 'NumberOfEmployees')
                }
            );
            Assert.isNull(RollupDlrs.activeOn('Account', FIELD), 'Inactive, or another field');

            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{
                    RollupDlrsFake.activeOn('account', 'MEMBER_COUNT__C')
                }
            );
            Assert.isNotNull(RollupDlrs.activeOn('Account', FIELD), 'Names match in any case');
            Assert.isTrue(
                RollupDlrs.conflict('Account', FIELD).contains('Child Count'),
                'The guard names the DLRS rollup'
            );
        }
    }

    // ------------------------------------------------------------------------------- the guard

    @IsTest
    static void theBuilderAsksFirstThenSavesAndRecordsTheAnswer() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', FIELD) }
            );

            RollupBuilderController.SaveResult asked = RollupBuilderController.save(
                childCount(true),
                false
            );
            Integer savedAfterAsking = [SELECT COUNT() FROM Rollup_Definition__c WITH USER_MODE];
            RollupBuilderController.SaveResult saved = RollupBuilderController.saveSwitchingOffDlrs(
                childCount(true),
                false
            );

            Assert.isTrue(asked.confirmation.contains('Child Count'), 'Asked, naming DLRS');
            Assert.isNull(asked.recordId, 'Nothing saved before the answer');
            Assert.areEqual(0, savedAfterAsking, 'No rollup was written');
            Assert.isNotNull(saved.recordId, 'Saved on her word');
            List<Setting_Change__c> recorded = changes();
            Assert.areEqual(1, recorded.size(), 'One change history row');
            Assert.areEqual(
                'Rollup Builder: Child organization count',
                recorded[0].Setting_Name__c,
                'Filed under the rollup'
            );
            Assert.areEqual(
                System.Label.Core_RollupBuilder_DlrsHistoryConfirmed,
                recorded[0].New_Value__c,
                'Says she confirmed DLRS will be switched off'
            );
        }
    }

    @IsTest
    static void aRollupSavedOffIsNotAsked() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', FIELD) }
            );

            RollupBuilderController.SaveResult saved = RollupBuilderController.save(
                childCount(false),
                false
            );

            Assert.isNull(saved.confirmation, 'Off fills nothing, so nothing is asked');
            Assert.isNotNull(saved.recordId, 'Saved');
            Assert.isTrue(changes().isEmpty(), 'Nothing to record');
        }
    }

    @IsTest
    static void theSharedChecksRefuseWithoutAnAnswer() {
        System.runAs(maria()) {
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', FIELD) }
            );

            // What a file import calls: it cannot ask, so it refuses with the reason.
            try {
                RollupBuilderController.checkedRecord(childCount(true));
                Assert.fail('An active rollup on a field DLRS fills is refused');
            } catch (RollupService.RollupServiceException refused) {
                Assert.isTrue(refused.getMessage().contains('Child Count'), 'Naming DLRS');
            }
            Assert.isNotNull(
                RollupBuilderController.checkedRecord(childCount(true), true),
                'With her word it passes'
            );
        }
    }

    @IsTest
    static void theListRefusesTheSwitchUntilTheAdminConfirms() {
        System.runAs(maria()) {
            Rollup_Definition__c definition = existing(false);
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', FIELD) }
            );

            Assert.isNotNull(
                RollupController.getPage().rollups[0].otherToolConflict,
                'The list knows to ask'
            );
            try {
                RollupController.setActive(definition.Id, true);
                Assert.fail('Turning it on without an answer is refused');
            } catch (AuraHandledException refused) {
                Assert.isTrue(refused.getMessage().contains('Child Count'), 'Naming DLRS');
            }
            RollupController.turnOnSwitchingOffDlrs(definition.Id);
            RollupController.setActive(definition.Id, false);

            Assert.areEqual(1, changes().size(), 'The answer is recorded once');
            Assert.isFalse(
                [SELECT Active__c FROM Rollup_Definition__c WITH USER_MODE][0].Active__c,
                'Turning off is never asked'
            );
        }
    }

    @IsTest
    static void healthCheckNamesAFieldBothToolsFill() {
        System.runAs(maria()) {
            existing(true);
            RollupDlrsFake.use(
                new List<RollupDlrs.Definition>{ RollupDlrsFake.activeOn('Account', FIELD) }
            );

            HealthCheckService.Finding finding = new RollupsHealthCheckExtension.SameFieldCheck()
                .run();

            Assert.areEqual('rollup_two_tools_same_field', finding.getKey(), 'Reported');
            Assert.isTrue(finding.getDetail().contains('Account.' + FIELD), 'Names the field');
            Assert.isTrue(finding.getDetail().contains('Child Count'), 'And the DLRS rollup');
        }
    }

    @IsTest
    static void aReaderThatFailsIsLoggedAndReadsNothing() {
        System.runAs(maria()) {
            RollupDlrs.reader = new Failing();
            RollupDlrs.reset();

            Assert.isTrue(RollupDlrs.definitions().isEmpty(), 'Nothing, and no failure');
            Assert.isNull(RollupDlrs.activeOn(null, FIELD), 'A blank object matches nothing');
        }
    }

    private class Failing implements RollupDlrs.Reader {
        public List<RollupDlrs.Definition> read() {
            throw new RollupService.RollupServiceException('DLRS could not be read.');
        }
    }
}
