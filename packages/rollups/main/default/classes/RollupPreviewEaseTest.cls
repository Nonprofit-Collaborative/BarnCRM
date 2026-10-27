/**
 * The Builder's live preview with sample records (Rollup Builder ease of use U4, ADR-0136):
 * samples picked for the administrator, and the records read for one record, each counted or
 * left out with the reason. Core holds no giving objects, so organizations count their child
 * organizations (`ParentId`), as in `RollupBuilderControllerTest`.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest(testFor='ApexClass:RollupPreviewRows, ApexClass:RollupBuilderController')
private class RollupPreviewEaseTest {
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
        draft.targetObject = 'Account';
        draft.targetField = 'Member_Count__c';
        draft.sourceObject = 'Account';
        draft.relationshipPath = 'ParentId';
        draft.aggregate = 'COUNT';
        draft.mode = RollupService.MODE_BOTH;
        return draft;
    }

    private static String nameStartsWith(String value) {
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'conditions' => new List<Object>{
                    new Map<String, Object>{
                        'id' => 1,
                        'field' => 'Name',
                        'operator' => 'starts with',
                        'value' => value
                    }
                }
            }
        );
    }

    private static Account parentWith(String name, List<String> children) {
        Account parent = new Account(Name = name);
        insert parent;
        List<Account> kids = new List<Account>();
        for (String child : children) {
            kids.add(new Account(Name = child, ParentId = parent.Id));
        }
        insert kids;
        return parent;
    }

    @IsTest
    static void eachRecordReadIsCountedOrLeftOutWithTheConditionItFails() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.PreviewResult preview;
            System.runAs(maria()) {
                Account parent = parentWith(
                    'Parent Org',
                    new List<String>{ 'Kid One', 'Kid Two', 'Other' }
                );
                RollupBuilderController.Draft draft = childCount();
                draft.filterJson = nameStartsWith('Kid');
                preview = RollupBuilderController.preview(draft, parent.Id);
            }

            System.Assert.areEqual(3, preview.rows.total, 'Every child is read');
            System.Assert.areEqual(3, preview.rows.rows.size());
            Map<String, RollupPreviewRows.Row> byName = new Map<String, RollupPreviewRows.Row>();
            for (RollupPreviewRows.Row row : preview.rows.rows) {
                byName.put(row.name, row);
            }
            System.Assert.isTrue(byName.get('Kid One').counted);
            System.Assert.areEqual(Label.Core_RollupEase_RowCounted, byName.get('Kid One').reason);
            System.Assert.isFalse(byName.get('Other').counted);
            System.Assert.areEqual(
                String.format(Label.Core_RollupEase_RowFails, new List<String>{ '1' }),
                byName.get('Other').reason,
                'Condition 1 is the one it does not meet'
            );
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupEase_RowsShown,
                    new List<String>{ (3).format(), (3).format() }
                ),
                preview.rows.summary
            );
        }
    }

    @IsTest
    static void atMostTenRecordsAreListedAndTheTotalIsSaid() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.PreviewResult preview;
            System.runAs(maria()) {
                List<String> names = new List<String>();
                for (Integer i = 0; i < 12; i++) {
                    names.add('Kid ' + i);
                }
                Account parent = parentWith('Parent Org', names);
                preview = RollupBuilderController.preview(childCount(), parent.Id);
            }

            System.Assert.areEqual(12, preview.rows.total);
            System.Assert.areEqual(RollupPreviewRows.MAX_SHOWN, preview.rows.rows.size());
            System.Assert.isNull(preview.rows.note);
        }
    }

    @IsTest
    static void aRecordWithNothingReadSaysSo() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupBuilderController.PreviewResult preview;
            System.runAs(maria()) {
                Account lonely = parentWith('Lonely Org', new List<String>());
                preview = RollupBuilderController.preview(childCount(), lonely.Id);
            }

            System.Assert.areEqual(0, preview.rows.total);
            System.Assert.areEqual(Label.Core_RollupEase_RowsNone, preview.rows.note);
            System.Assert.isNull(preview.rows.summary);
        }
    }

    @IsTest
    static void samplesComeFirstFromRecordsThatHaveRecordsToCount() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupPreviewRows.Sample> samples;
            Account first;
            Account second;
            System.runAs(maria()) {
                first = parentWith('First Org', new List<String>{ 'Kid A', 'Kid B' });
                second = parentWith('Second Org', new List<String>{ 'Kid C' });
                samples = RollupBuilderController.previewSamples(childCount());
            }

            System.Assert.areEqual(RollupPreviewRows.MAX_SAMPLES, samples.size(), 'Five, as asked');
            Map<String, RollupPreviewRows.Sample> byId = new Map<String, RollupPreviewRows.Sample>();
            for (RollupPreviewRows.Sample sample : samples) {
                byId.put(sample.recordId, sample);
            }
            System.Assert.isTrue(byId.containsKey(first.Id), 'A record with children is sampled');
            System.Assert.isTrue(byId.containsKey(second.Id));
            System.Assert.areEqual('First Org', byId.get(first.Id).name);
            System.Assert.areEqual(
                String.format(
                    Label.Core_RollupBuilder_PreviewResult,
                    new List<String>{ (2).format(), Label.Core_RollupBuilder_PreviewEmpty }
                ),
                byId.get(first.Id).result,
                'Two children counted, next to the empty field'
            );
            System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing saved');
        }
    }

    @IsTest
    static void samplesMeetTheTargetConditionsOrThereAreNone() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<RollupPreviewRows.Sample> samples;
            System.runAs(maria()) {
                parentWith('First Org', new List<String>{ 'Kid A' });
                RollupBuilderController.Draft draft = childCount();
                draft.targetFilterJson = nameStartsWith('Beta');
                samples = RollupBuilderController.previewSamples(draft);
            }

            System.Assert.isTrue(samples.isEmpty(), 'No organization starts with Beta');
        }
    }

    @IsTest
    static void someoneWithoutTheSettingsPermissionCannotPickSamples() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String message;
            System.runAs(david) {
                try {
                    RollupBuilderController.previewSamples(childCount());
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }
            System.Assert.areEqual(Label.Core_Rollups_ErrorNoPermission, message);
        }
    }

    @IsTest
    static void theNameFieldIsTheOneTheEntityNames() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            System.Assert.areEqual('Name', RollupPreviewRows.nameFieldOf(Account.SObjectType));
        }
    }
}
