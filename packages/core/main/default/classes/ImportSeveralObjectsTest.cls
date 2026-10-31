/**
 * Several objects in one upload (canonical model R-IT20; ADR-0147
 * `0147-several-objects-in-one-upload.md`): parents first and each record linked to its row's
 * parent, at 260 rows over two chunks with repeated parents; a failed parent rejecting the
 * records that point at it; a failed child leaving its parent; rows of two sheets, one object
 * each, linked by a lookup column; the dry run writing nothing; one undo for every object; an
 * existing link kept; legacy related records running as two steps; and a row loaded again
 * (in place, or as a retry's fixed row at 260 rows) reusing what it created, never a copy, with
 * one undo removing it once. The load order, links
 * and refusals are in `ImportSeveralObjectsSchemaTest`.
 *
 * Organizations stand for the parent (updated by a matching field, their name), people for a
 * second parent (updated by record ID) and affiliations for the child pointing at both, since
 * Core creates no pair of its own objects. Every test runs as a minimal-profile user holding
 * only BarnCRM Admin, since every read and save is in that user's own mode.
 */
@IsTest(testFor='ApexClass:ImportObjectLoader, ApexClass:ImportUndoService')
private class ImportSeveralObjectsTest {
    static {
        // Saved queries are the package's bookkeeping, which an import refuses; here they stand
        // in for an org's own object a row can create that nothing else needs.
        DataProtectedFields.ordinaryForTest.add('saved_query__c');
    }

    private static final Integer MANY = 200;
    private static final Integer REPEATS = 60;

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

    /** Organizations updated by name and affiliations created, listed child first. */
    private static ImportMapping organizationsAndAffiliations() {
        ImportMapping mapping = new ImportMapping();
        mapping.objects = new List<ImportMapping.ObjectStep>{
            new ImportMapping.ObjectStep(
                'Affiliation__c',
                ImportObjectSchema.OPERATION_INSERT,
                null
            ),
            new ImportMapping.ObjectStep(
                'Account',
                ImportObjectSchema.OPERATION_UPDATE_BY_FIELD,
                'Name'
            )
        };
        mapping.columns.add(new ImportMapping.Column('Org', 'Account.Name'));
        mapping.columns.add(new ImportMapping.Column('Phone', 'Account.Phone'));
        mapping.columns.add(new ImportMapping.Column('Person', 'Affiliation__c.Contact__c'));
        mapping.columns.add(new ImportMapping.Column('Role', 'Affiliation__c.Role__c'));
        return mapping;
    }

    private static void given(ImportMapping mapping, List<Map<String, String>> values) {
        ImportEntityProcessors.noneForTest = true;
        template = ImportTestDataFactory.template(mapping.serialize(), null);
        template.Target_Object__c = 'Account';
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
            SELECT Row_Number__c, Status__c, Error_Message__c, Gift_Id__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            WITH SYSTEM_MODE
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
        Id organizationType = AccountKindsTestData.organizationRecordTypeId();
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
        Map<String, String> result = new Map<String, String>{ 'Org' => org };
        if (phone != null) {
            result.put('Phone', phone);
        }
        if (personId != null) {
            result.put('Person', personId);
            result.put('Role', role);
        }
        return result;
    }

    private static String labelOf(Schema.SObjectType type) {
        return type.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel();
    }

    private static String onObject(String objectLabel, String reason) {
        return String.format(
            Label.Core_Import_ErrorOnObject,
            new List<String>{ objectLabel, reason }
        );
    }

    @IsTest
    static void twoHundredSixtyRowsLoadParentsFirstAndLinkEachChildToItsRowsParent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(MANY);
                Contact ana = person();
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < MANY; i++) {
                    values.add(row('Org ' + i, '555-1111', ana.Id, 'Member'));
                }
                // Later rows of the first keys, in the next chunk: a child each, and the
                // parent's columns of a later row are not loaded.
                for (Integer i = 0; i < REPEATS; i++) {
                    values.add(row('org ' + i, '555-9999', ana.Id, 'Volunteer'));
                }
                given(organizationsAndAffiliations(), values);

                Test.startTest();
                ImportRowProcessor.Outcome first = chunk(2, MANY + 1, false);
                ImportRowProcessor.Outcome second = chunk(MANY + 2, MANY + REPEATS + 1, false);
                Test.stopTest();

                Assert.areEqual(0, first.rejected + second.rejected, rowErrors());
                Assert.areEqual(MANY + REPEATS, first.created + second.created, rowErrors());
                Assert.areEqual(
                    MANY,
                    [SELECT COUNT() FROM Account WHERE Id IN :orgs AND Phone = '555-1111'],
                    'Each parent from its first row only.'
                );
                Map<Id, Integer> perOrg = new Map<Id, Integer>();
                for (Affiliation__c made : [
                    SELECT Organization__c
                    FROM Affiliation__c
                    WHERE Contact__c = :ana.Id
                ]) {
                    Integer seen = perOrg.get(made.Organization__c);
                    perOrg.put(made.Organization__c, seen == null ? 1 : seen + 1);
                }
                Assert.areEqual(MANY, perOrg.size(), 'Every parent has its child.');
                Assert.areEqual(2, perOrg.get(orgs[0].Id), 'A later chunk links to its parent.');
                Assert.areEqual(1, perOrg.get(orgs[MANY - 1].Id), 'One for a one-row parent.');
                for (Import_Row__c staged : rows()) {
                    Assert.isNotNull(staged.Gift_Id__c, 'The first object as the record.');
                }
            }
        }
    }

    @IsTest
    static void aFailedParentRejectsTheRecordsThatPointAtIt() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organizations(1);
                Contact ana = person();
                given(
                    organizationsAndAffiliations(),
                    new List<Map<String, String>>{
                        row('Nobody', '555-1111', ana.Id, 'Member'),
                        row('Nobody', null, ana.Id, 'Member'),
                        row('Org 0', null, ana.Id, 'Member')
                    }
                );

                Test.startTest();
                chunk(2, 3, false);
                chunk(4, 4, false);
                Test.stopTest();

                List<Import_Row__c> staged = rows();
                String account = labelOf(Account.SObjectType);
                Assert.areEqual('Rejected', staged[0].Status__c, 'The parent found nothing.');
                Assert.isTrue(
                    staged[0].Error_Message__c.startsWith(account + ': '),
                    'The reason names the object: ' + staged[0].Error_Message__c
                );
                Assert.areEqual(
                    onObject(account, Label.Core_Import_ErrorKeyFirstRowFailed),
                    staged[1].Error_Message__c,
                    'A later row of a failed key.'
                );
                Assert.areEqual('Created', staged[2].Status__c, rowErrors());
                Assert.areEqual(
                    1,
                    [SELECT COUNT() FROM Affiliation__c WHERE Contact__c = :ana.Id],
                    'Only the child of the parent that loaded.'
                );
            }
        }
    }

    @IsTest
    static void aFailedChildRejectsItsRowAndLeavesItsParent() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Account org = organizations(1)[0];
                Contact ana = person();
                given(
                    organizationsAndAffiliations(),
                    new List<Map<String, String>>{
                        row('Org 0', '555-1111', ana.Id, 'R'.repeat(300))
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = chunk(2, 2, false);
                Test.stopTest();

                Import_Row__c staged = rows()[0];
                String affiliation = labelOf(Affiliation__c.SObjectType);
                Assert.areEqual(1, committed.rejected, 'The row is rejected.');
                Assert.isTrue(
                    staged.Error_Message__c.startsWith(affiliation + ': '),
                    'For its child: ' + staged.Error_Message__c
                );
                Assert.areEqual(
                    '555-1111',
                    [SELECT Phone FROM Account WHERE Id = :org.Id].Phone,
                    'The parent stays.'
                );
                Assert.areEqual(String.valueOf(org.Id), staged.Gift_Id__c, 'As its record.');
                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'No child.');
            }
        }
    }

    @IsTest
    static void rowsOfTwoSheetsLoadOneObjectEachAndLinkByALookupColumn() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Account org = organizations(1)[0];
                Contact ana = person();
                ImportMapping mapping = organizationsAndAffiliations();
                ImportMapping.Column byName = new ImportMapping.Column(
                    'Organization',
                    'Affiliation__c.Organization__c'
                );
                byName.lookupField = 'Name';
                mapping.columns.add(byName);
                given(
                    mapping,
                    new List<Map<String, String>>{
                        // The organizations sheet, staged first.
                        new Map<String, String>{ 'Org' => 'Org 0', 'Phone' => '555-1111' },
                        // The affiliations sheet, naming its organization by name.
                        new Map<String, String>{
                            'Organization' => 'Org 0',
                            'Person' => ana.Id,
                            'Role' => 'Member'
                        }
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome committed = chunk(2, 3, false);
                Test.stopTest();

                Assert.areEqual(1, committed.updated, 'The organization row: ' + rowErrors());
                Assert.areEqual(1, committed.created, 'The affiliation row: ' + rowErrors());
                Affiliation__c made = [SELECT Organization__c, Role__c FROM Affiliation__c];
                Assert.areEqual(org.Id, made.Organization__c, 'Linked by the lookup column.');
                Assert.areEqual(
                    String.valueOf(made.Id),
                    rows()[1].Gift_Id__c,
                    'The sheet row loads no organization of its own.'
                );
            }
        }
    }

    @IsTest
    static void theDryRunDecidesEveryObjectAndWritesNothing() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organizations(1);
                Contact ana = person();
                given(
                    organizationsAndAffiliations(),
                    new List<Map<String, String>>{
                        row('Org 0', '555-1111', ana.Id, 'Member'),
                        row('Org 0', null, ana.Id, 'Volunteer'),
                        row('Nobody', null, ana.Id, 'Member')
                    }
                );

                Test.startTest();
                ImportRowProcessor.Outcome preview = chunk(2, 4, true);
                Test.stopTest();

                Assert.areEqual(2, preview.created, 'Both children would be created.');
                Assert.areEqual(1, preview.rejected, 'The row whose parent finds nothing.');
                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'No child written.');
                Assert.areEqual(
                    '555-0000',
                    [SELECT Phone FROM Account WHERE Name = 'Org 0'].Phone,
                    'No parent changed.'
                );
                Assert.areEqual(
                    0,
                    [SELECT COUNT() FROM Import_Journal__c WHERE Import_Batch__c = :batch.Id],
                    'Nothing is journaled.'
                );
            }
        }
    }

    @IsTest
    static void anExistingRecordKeepsItsParentAndANewOneTakesTheRows() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(2);
                Contact ana = new Contact(
                    FirstName = 'Ana',
                    LastName = 'Ramirez',
                    AccountId = orgs[1].Id
                );
                insert ana;
                ImportMapping mapping = organizationsAndAffiliations();
                mapping.objects.add(
                    new ImportMapping.ObjectStep(
                        'Contact',
                        ImportObjectSchema.OPERATION_UPDATE,
                        null
                    )
                );
                mapping.columns.add(new ImportMapping.Column('Person Id', 'Contact.Id'));
                mapping.columns.add(new ImportMapping.Column('Title', 'Contact.Title'));
                Map<String, String> values = row('Org 0', null, ana.Id, 'Member');
                values.put('Person Id', ana.Id);
                values.put('Title', 'Volunteer Captain');
                given(mapping, new List<Map<String, String>>{ values });

                Test.startTest();
                ImportRowProcessor.Outcome committed = chunk(2, 2, false);
                Test.stopTest();

                Assert.areEqual(1, committed.created, rowErrors());
                Contact after = [SELECT AccountId, Title FROM Contact WHERE Id = :ana.Id];
                Assert.areEqual('Volunteer Captain', after.Title, 'The person is updated.');
                Assert.areEqual(orgs[1].Id, after.AccountId, 'And keeps the account it had.');
                Affiliation__c made = [SELECT Organization__c, Contact__c FROM Affiliation__c];
                Assert.areEqual(orgs[0].Id, made.Organization__c, 'The new child takes both.');
                Assert.areEqual(ana.Id, made.Contact__c, 'Its row.');
            }
        }
    }

    @IsTest
    static void oneUndoRemovesTheChildrenAndPutsBackTheParents() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                List<Account> orgs = organizations(2);
                Contact ana = person();
                given(
                    organizationsAndAffiliations(),
                    new List<Map<String, String>>{
                        row('Org 0', '555-1111', ana.Id, 'Member'),
                        row('Org 1', '555-1111', ana.Id, 'Member'),
                        row('Org 1', null, ana.Id, 'Volunteer')
                    }
                );
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

                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'Every child deleted.');
                Assert.areEqual(
                    2,
                    [SELECT COUNT() FROM Account WHERE Id IN :orgs AND Phone = '555-0000'],
                    'And each parent holds its value from before.'
                );
            }
        }
    }

    // -------------------------------------------------------------------------------------
    // Loading a row again (R-IT20): what a row created is reused, never copied
    // -------------------------------------------------------------------------------------

    /**
     * Saved queries created (standing in for an org's own object; see the static block),
     * organizations updated by name and affiliations created pointing at them, listed in that
     * order: a saved query is created before its row's affiliation can fail.
     */
    private static ImportMapping queriesAndAffiliations() {
        ImportMapping mapping = organizationsAndAffiliations();
        mapping.objects.add(
            0,
            new ImportMapping.ObjectStep(
                'Saved_Query__c',
                ImportObjectSchema.OPERATION_INSERT,
                null
            )
        );
        mapping.columns.add(new ImportMapping.Column('Query', 'Saved_Query__c.Name'));
        mapping.columns.add(new ImportMapping.Column('About', 'Saved_Query__c.Object_Name__c'));
        mapping.columns.add(new ImportMapping.Column('Json', 'Saved_Query__c.Query_JSON__c'));
        return mapping;
    }

    private static Map<String, String> queryRow(Integer index, Id personId, String role) {
        Map<String, String> result = row('Org 0', null, personId, role);
        result.put('Query', 'Zzretry ' + index);
        result.put('About', 'Contact');
        result.put('Json', '{}');
        return result;
    }

    private static final String TOO_LONG = 'R'.repeat(300);

    /** The batch as a commit sees it, so its undo can run. */
    private static void committing() {
        update new Import_Batch__c(
            Id = batch.Id,
            Is_Dry_Run__c = false,
            Status__c = ImportBatchService.STATUS_COMMITTING,
            Started_At__c = Datetime.now().addMinutes(-1),
            Committed_By__c = UserInfo.getUserId(),
            Undo_Deadline__c = Datetime.now().addDays(30)
        );
        batch = ImportBatchSelector.selectById(batch.Id);
    }

    private static void undo() {
        update new Import_Batch__c(
            Id = batch.Id,
            Status__c = ImportBatchService.STATUS_COMPLETE,
            Completed_At__c = Datetime.now()
        );
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
            List<SObject> scope = new List<SObject>();
            while (records.hasNext()) {
                scope.add(records.next());
            }
            if (!scope.isEmpty()) {
                job.execute(null, scope);
            }
        }
    }

    private static Integer savedQueries() {
        return [SELECT COUNT() FROM Saved_Query__c WHERE Name LIKE 'Zzretry %'];
    }

    @IsTest
    static void aRowLoadedAgainReusesWhatItCreatedAndCreatesOnlyWhatIsMissing() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                Account org = organizations(1)[0];
                Contact ana = person();
                given(
                    queriesAndAffiliations(),
                    new List<Map<String, String>>{ queryRow(0, ana.Id, TOO_LONG) }
                );
                committing();
                chunk(2, 2, false);
                Import_Row__c failed = [
                    SELECT Id, Status__c, Loaded_Records_JSON__c
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id
                    WITH SYSTEM_MODE
                ];
                Assert.areEqual('Rejected', failed.Status__c, 'The affiliation failed.');
                Assert.areEqual(1, savedQueries(), 'Its saved query was created.');
                Assert.isTrue(
                    failed.Loaded_Records_JSON__c.contains('saved_query__c'),
                    'And kept on the row: ' + failed.Loaded_Records_JSON__c
                );

                // The row fixed and loaded again, as a retry of the same row does.
                update as system new Import_Row__c(
                    Id = failed.Id,
                    Raw_Values_JSON__c = JSON.serialize(queryRow(0, ana.Id, 'Member'))
                );
                ImportRowProcessor.Outcome again = chunk(2, 2, false);

                Assert.areEqual(1, again.created, rowErrors());
                Assert.areEqual(1, savedQueries(), 'One saved query, reused, never a copy.');
                Affiliation__c made = [SELECT Organization__c, Contact__c FROM Affiliation__c];
                Assert.areEqual(org.Id, made.Organization__c, 'The missing child, linked.');
                Saved_Query__c kept = [SELECT Id FROM Saved_Query__c WHERE Name = 'Zzretry 0'];
                Assert.areEqual(String.valueOf(kept.Id), rows()[0].Gift_Id__c, 'Its record.');

                // The undo is a job of its own, with its own query budget for the checks it
                // makes before deleting.
                Test.startTest();
                undo();
                Test.stopTest();
                Assert.areEqual(0, savedQueries(), 'Undo removes the reused record once.');
                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'And the child.');
            }
        }
    }

    @IsTest
    static void aRetrysFixedRowsReuseTheRecordsTheirRejectedRowsCreatedAtTwoHundredSixtyRows() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organizations(1);
                Contact ana = person();
                Integer count = MANY + REPEATS;
                List<Map<String, String>> values = new List<Map<String, String>>();
                for (Integer i = 0; i < count; i++) {
                    values.add(queryRow(i, ana.Id, TOO_LONG));
                }
                given(queriesAndAffiliations(), values);
                committing();
                chunk(2, MANY + 1, false);
                chunk(MANY + 2, count + 1, false);
                Assert.areEqual(count, savedQueries(), 'Every saved query was created.');
                Assert.areEqual(0, [SELECT COUNT() FROM Affiliation__c], 'No child loaded.');

                // A retry's fixed rows, numbered after the import's own, each naming its
                // rejected row in the exceptions file's Row column (R-IB17).
                Decimal after = count + 1;
                update as system new Import_Batch__c(Id = batch.Id, Retry_After_Row__c = after);
                List<Import_Row__c> fixedRows = new List<Import_Row__c>();
                for (Integer i = 0; i < count; i++) {
                    // A role each: the affiliation guard refuses two that overlap for the same
                    // person, organization and role.
                    Map<String, String> fixedRow = queryRow(i, ana.Id, 'Member ' + i);
                    fixedRow.put(Label.Core_Import_ResultsRow, String.valueOf(i + 2));
                    fixedRows.add(
                        new Import_Row__c(
                            Import_Batch__c = batch.Id,
                            Row_Number__c = after + i + 1,
                            Raw_Values_JSON__c = JSON.serialize(fixedRow),
                            Status__c = ImportRowProcessor.STATUS_PENDING
                        )
                    );
                }
                insert as system fixedRows;
                batch = ImportBatchSelector.selectById(batch.Id);
                Integer first = after.intValue() + 1;

                Test.startTest();
                ImportRowProcessor.Outcome preview = chunk(first, first + MANY - 1, true);
                Assert.areEqual(count, savedQueries(), 'The dry run writes nothing.');
                // The commit is a pass of its own, as after any dry run.
                ImportBatchService.beginPass(batch.Id);
                batch = ImportBatchSelector.selectById(batch.Id);
                ImportRowProcessor.Outcome one = chunk(first, first + MANY - 1, false);
                ImportRowProcessor.Outcome two = chunk(first + MANY, first + count - 1, false);
                Test.stopTest();

                Assert.areEqual(MANY, preview.created, 'Each would create its child only.');
                List<String> fixedErrors = new List<String>();
                for (Import_Row__c r : [
                    SELECT Row_Number__c, Status__c, Error_Message__c
                    FROM Import_Row__c
                    WHERE Import_Batch__c = :batch.Id AND Row_Number__c > :after
                    WITH SYSTEM_MODE
                    ORDER BY Row_Number__c
                    LIMIT 4
                ]) {
                    fixedErrors.add(r.Row_Number__c + ' ' + r.Status__c + ' ' + r.Error_Message__c);
                }
                Assert.areEqual(
                    0,
                    one.rejected + two.rejected,
                    one.rejected + '/' + two.rejected + ' ' + String.join(fixedErrors, ' | ')
                );
                Assert.areEqual(count, one.created + two.created, String.join(fixedErrors, ' | '));
                Assert.areEqual(count, savedQueries(), 'Not one saved query copied.');
                Assert.areEqual(
                    count,
                    [SELECT COUNT() FROM Affiliation__c WHERE Contact__c = :ana.Id],
                    'Every missing child created.'
                );
            }
        }
    }

    @IsTest
    static void aReusedRecordDeletedSinceIsCreatedAgain() {
        System.runAs(TestUsers.admin()) {
            System.runAs(admin()) {
                organizations(1);
                Contact ana = person();
                given(
                    queriesAndAffiliations(),
                    new List<Map<String, String>>{ queryRow(0, ana.Id, TOO_LONG) }
                );
                chunk(2, 2, false);
                delete [SELECT Id FROM Saved_Query__c WHERE Name = 'Zzretry 0'];
                Import_Row__c failed = rows()[0];

                Test.startTest();
                update as system new Import_Row__c(
                    Id = [SELECT Id FROM Import_Row__c WHERE Import_Batch__c = :batch.Id]
                    .Id,
                    Raw_Values_JSON__c = JSON.serialize(queryRow(0, ana.Id, 'Member'))
                );
                ImportRowProcessor.Outcome again = chunk(2, 2, false);
                Test.stopTest();

                Assert.areEqual('Rejected', failed.Status__c, 'It failed the first time.');
                Assert.areEqual(1, again.created, rowErrors());
                Assert.areEqual(1, savedQueries(), 'The gone record is made again, once.');
                Assert.areEqual(1, [SELECT COUNT() FROM Affiliation__c], 'With its child.');
            }
        }
    }
}
