/**
 * Related records in one file (canonical model R-IT17; ADR-0111 `0111-load-related-records.md`):
 * parents first and each related record linked to its row's parent, at 200 parents over two
 * chunks; a failed parent rejecting its related rows in its chunk and later ones; a related
 * record that fails leaving its parent; a row with only a key and related columns; the dry run
 * writing nothing; and one undo for both. The template's choices and refusals are in
 * `ImportRelatedSchemaTest`.
 *
 * Organizations stand for the parent (updated by a matching field, their name) and affiliations
 * for the related object pointing at them, since Core has no pair of its own objects where the
 * parent carries an External ID. Every test runs as a minimal-profile user holding only BarnCRM
 * Admin, since every read and save is in that user's own mode.
 */
@IsTest(testFor='ApexClass:ImportObjectLoader, ApexClass:ImportUndoService')
private class ImportRelatedRecordsTest {
    private static final Integer MANY = 200;

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static User admin() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    /** Organizations updated by name, each row also creating an affiliation of a person. */
    private static void given(List<Map<String, String>> values) {
        ImportEntityProcessors.noneForTest = true;
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Org', 'Record.Name'));
        mapping.columns.add(new ImportMapping.Column('Phone', 'Record.Phone'));
        mapping.columns.add(new ImportMapping.Column('Person', 'Related.Contact__c'));
        mapping.columns.add(new ImportMapping.Column('Role', 'Related.Role__c'));
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Account';
        template.Load_Operation__c = ImportObjectSchema.OPERATION_UPDATE_BY_FIELD;
        template.Load_Match_Field__c = 'Name';
        template.Related_Object__c = 'Affiliation__c';
        template.Related_Parent_Field__c = 'Organization__c';
        update template;
        template = ImportTemplateSelector.selectById(template.Id);
        batch = ImportTestDataFactory.batch(template);
        ImportTestDataFactory.rows(batch, values);
        ImportBatchService.beginPass(batch.Id);
        batch = ImportBatchSelector.selectById(batch.Id);
    }

    /** One chunk: the staged rows from this file row to that one, inclusive. */
    private static ImportRowProcessor.Outcome chunk(Integer first, Integer last, Boolean dryRun) {
        List<Import_Row__c> scope = new List<Import_Row__c>();
        for (Import_Row__c row : ImportTestDataFactory.reload(batch.Id)) {
            if (row.Row_Number__c >= first && row.Row_Number__c <= last) {
                scope.add(row);
            }
        }
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c, template.Default_Values_JSON__c),
            scope,
            dryRun
        );
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT
                Row_Number__c,
                Status__c,
                Error_Message__c,
                Gift_Id__c,
                Soft_Credit_Id__c,
                Related_Status__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    private static String rowErrors() {
        List<String> errors = new List<String>();
        for (Import_Row__c row : rows()) {
            if (row.Error_Message__c != null) {
                errors.add(row.Row_Number__c + ': ' + row.Error_Message__c);
            }
        }
        return String.join(errors, '; ');
    }

    private static List<Account> organizations(Integer count) {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        List<Account> result = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            result.add(
                new Account(Name = 'Org ' + i, Phone = '555-0000', RecordTypeId = organizationType)
            );
        }
        insert result;
        return result;
    }

    private static Contact person() {
        Contact created = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        insert created;
        return created;
    }

    private static Map<String, String> row(String org, String phone, Id personId, String role) {
        Map<String, String> result = new Map<String, String>{ 'Org' => org, 'Phone' => phone };
        if (personId != null) {
            result.put('Person', personId);
            result.put('Role', role);
        }
        return result;
    }

    @IsTest
    static void twoHundredParentsLoadFirstAndEachRelatedRecordPointsAtItsRowsParent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(MANY);
                Contact ana = person();
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(row('Org ' + i, '555-1111', ana.Id, 'Member'));
                }
                // Later rows of the first 20 keys, in the next chunk: a related record each, and
                // their parent columns are not loaded.
                for (Integer i = 0; i < 20; i++) {
                    values.add(row('org ' + i, '555-9999', ana.Id, 'Volunteer'));
                }
                given(values);

                Test.startTest();
                ImportRowProcessor.Outcome first = chunk(2, MANY + 1, false);
                ImportRowProcessor.Outcome second = chunk(MANY + 2, MANY + 21, false);
                Test.stopTest();

                Assert.areEqual(MANY, first.updated, 'Every parent: ' + rowErrors());
                Assert.areEqual(20, second.matched, 'Later rows add only: ' + rowErrors());
                Assert.areEqual(0, first.rejected + second.rejected, rowErrors());
                Assert.areEqual(
                    MANY,
                    [SELECT COUNT() FROM Account WHERE Id IN :orgs AND Phone = '555-1111'],
                    'Each parent from its first row only.'
                );
                Map<Id, Integer> perOrg = new Map<Id, Integer>();
                for (Affiliation__c made : [
                    SELECT Organization__c, Contact__c
                    FROM Affiliation__c
                    WHERE Contact__c = :ana.Id
                ]) {
                    Integer seen = perOrg.get(made.Organization__c);
                    perOrg.put(made.Organization__c, seen == null ? 1 : seen + 1);
                }
                Assert.areEqual(MANY, perOrg.size(), 'Every parent has its related record.');
                Assert.areEqual(2, perOrg.get(orgs[0].Id), 'A later chunk links to its parent.');
                Assert.areEqual(1, perOrg.get(orgs[MANY - 1].Id), 'One for a one-row parent.');
                for (Import_Row__c staged : rows()) {
                    Assert.areEqual('Created', staged.Related_Status__c, 'Each related record.');
                    Assert.isNotNull(staged.Soft_Credit_Id__c, 'Kept as the second record.');
                    Assert.isNotNull(staged.Gift_Id__c, 'The parent as the resulting record.');
                }
                Assert.areEqual(
                    String.format(
                        Label.Core_Import_LogRelatedCommit,
                        new List<String>{ String.valueOf(MANY + 20), '0' }
                    ),
                    ImportObjectLoader.relatedLines(batch.Id, false)[0],
                    'The run log counts the related records.'
                );
            }
        }
    }

    @IsTest
    static void aFailedParentRejectsItsRelatedRowsInItsChunkAndLaterOnes() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(2);
                Contact ana = person();
                given(
                    new List<Map<String, String>>{
                        row('Nobody', '555-1111', ana.Id, 'Member'),
                        row('Nobody', null, ana.Id, 'Member'),
                        row('Org 0', '555-1111', ana.Id, 'Member'),
                        // Its related record is refused: a role longer than the field.
                        row('Org 1', null, ana.Id, 'R'.repeat(300)),
                        row('Nobody', null, ana.Id, 'Member')
                    }
                );

                Test.startTest();
                chunk(2, 5, false);
                chunk(6, 6, false);
                Test.stopTest();

                List<Import_Row__c> staged = rows();
                Assert.areEqual('Rejected', staged[0].Status__c, 'The parent found nothing.');
                Assert.areEqual(
                    Label.Core_Import_ErrorRelatedParentFailed,
                    staged[1].Error_Message__c,
                    'A later row of its key in the same chunk.'
                );
                Assert.areEqual(
                    Label.Core_Import_ErrorRelatedParentFailed,
                    staged[4].Error_Message__c,
                    'And in a later chunk.'
                );
                Assert.areEqual('Updated', staged[2].Status__c, 'Other parents load.');
                Assert.areEqual('Rejected', staged[3].Status__c, 'Its related record failed.');
                Assert.isTrue(
                    staged[3]
                        .Error_Message__c.startsWith(
                            Label.Core_Import_ErrorRelatedRecord.substringBefore('{0}')
                        ),
                    'Said to be the related record: ' + staged[3].Error_Message__c
                );
                Assert.areEqual(
                    String.valueOf(orgs[1].Id),
                    staged[3].Gift_Id__c,
                    'Its parent stays.'
                );
                Assert.areEqual(
                    '555-0000',
                    [SELECT Phone FROM Account WHERE Id = :orgs[1].Id].Phone,
                    'Org 1 had no new value on that row.'
                );
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Affiliation__c WHERE Contact__c = :ana.Id],
                    'Only the related record of the parent that loaded: ' + rowErrors()
                );
            }
        }
    }

    @IsTest
    static void aRowWithOnlyAKeyAddsARelatedRecordToTheExistingParent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Account org = organizations(1)[0];
                Contact ana = person();
                Map<String, String> keyOnly = row('Org 0', null, ana.Id, 'Member');
                keyOnly.remove('Phone');
                given(new List<Map<String, String>>{ keyOnly });

                Test.startTest();
                ImportRowProcessor.Outcome committed = chunk(2, 2, false);
                Test.stopTest();

                Assert.areEqual(1, committed.matched, 'The parent is unchanged: ' + rowErrors());
                Affiliation__c made = [
                    SELECT Organization__c, Role__c
                    FROM Affiliation__c
                    WHERE Contact__c = :ana.Id
                ];
                Assert.areEqual(org.Id, made.Organization__c, 'Linked to the parent by key.');
                Assert.areEqual('Member', made.Role__c, 'With its own values.');
            }
        }
    }

    @IsTest
    static void theDryRunDecidesBothAndWritesNeither() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organizations(1);
                Contact ana = person();
                given(
                    new List<Map<String, String>>{
                        row('Org 0', '555-1111', ana.Id, 'Member'),
                        row('Org 0', null, ana.Id, 'Volunteer'),
                        row('Nobody', null, ana.Id, 'Member')
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome preview = chunk(2, 4, true);
                Test.stopTest();

                Assert.areEqual(1, preview.updated, 'The parent would change.');
                Assert.areEqual(1, preview.matched, 'The later row would only add.');
                Assert.areEqual(1, preview.rejected, 'The row whose parent finds nothing.');
                Assert.areEqual(
                    0,
                    [SELECT COUNT() FROM Affiliation__c],
                    'No related record is written.'
                );
                Assert.areEqual(
                    '555-0000',
                    [SELECT Phone FROM Account WHERE Name = 'Org 0'].Phone,
                    'No parent is changed.'
                );
                Assert.areEqual(
                    0,
                    [SELECT COUNT() FROM Import_Journal__c WHERE Import_Batch__c = :batch.Id],
                    'Nothing is journaled.'
                );
                Assert.areEqual(
                    String.format(Label.Core_Import_LogRelatedDryRun, new List<String>{ '2', '1' }),
                    ImportObjectLoader.relatedLines(batch.Id, true)[0],
                    'The run log says what would be created.'
                );
            }
        }
    }

    @IsTest
    static void oneUndoRemovesTheRelatedRecordsAndPutsBackTheParents() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(2);
                Contact ana = person();
                given(
                    new List<Map<String, String>>{
                        row('Org 0', '555-1111', ana.Id, 'Member'),
                        row('Org 1', '555-1111', ana.Id, 'Member'),
                        row('Org 1', null, ana.Id, 'Volunteer')
                    }
                );
                // A fresh record: the read one holds Operation__c, which BarnCRM Admin may not edit.
                update new Import_Batch__c(
                    Id = batch.Id,
                    Is_Dry_Run__c = false,
                    Status__c = ImportBatchService.STATUS_COMMITTING,
                    Started_At__c = Datetime.now().addMinutes(-1),
                    Committed_By__c = UserInfo.getUserId(),
                    Undo_Deadline__c = Datetime.now().addDays(30)
                );
                batch = ImportBatchSelector.selectById(batch.Id);
                chunk(2, 4, false);
                update new Import_Batch__c(
                    Id = batch.Id,
                    Status__c = ImportBatchService.STATUS_COMPLETE,
                    Completed_At__c = Datetime.now()
                );
                Assert.areEqual(3, [SELECT COUNT() FROM Affiliation__c], rowErrors());

                Test.startTest();
                ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);
                Datetime undoStartedAt = Datetime.now();
                for (String pass : ImportUndoBatch.passes()) {
                    ImportUndoBatch job = new ImportUndoBatch(
                        batch.Id,
                        view.total,
                        pass,
                        0,
                        false,
                        undoStartedAt
                    );
                    Database.QueryLocatorIterator records = job.start(null).iterator();
                    while (records.hasNext()) {
                        job.execute(null, new List<SObject>{ records.next() });
                    }
                }
                Test.stopTest();

                Assert.areEqual(3, view.total, 'The related records it created are confirmed.');
                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'Every one deleted.');
                Assert.areEqual(
                    2,
                    [SELECT COUNT() FROM Account WHERE Id IN :orgs AND Phone = '555-0000'],
                    'And each parent holds its value from before.'
                );
            }
        }
    }
}
