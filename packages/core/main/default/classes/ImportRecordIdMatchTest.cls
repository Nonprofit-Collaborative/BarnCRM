/**
 * C-32 record ID matching and match only (ADR-0069,
 * `0069-import-record-id-matching-and-match-only.md`): a row giving a Salesforce record ID is
 * loaded into that record whatever the rule says, an ID that is not one, is of the wrong kind
 * or is not found rejects the row and creates nothing (R-IT10), and a file marked Match only
 * rejects every row that matches nobody (R-IB15).
 */
@IsTest(testFor='ApexClass:ImportRowProcessor, ApexClass:ImportMapping')
private class ImportRecordIdMatchTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.admin()) {
            TestDataFactory.defaultSettings();
        }
    }

    private static final List<String> COLUMNS = new List<String>{
        'Contact1.Id',
        'Contact1.FirstName',
        'Contact1.LastName',
        'Contact1.Email',
        'Contact1.MailingCity',
        'Organization.Id',
        'Organization.Name'
    };

    private static Import_Template__c template() {
        ImportMapping mapping = new ImportMapping();
        for (String target : COLUMNS) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        return ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
    }

    private static Map<String, String> row(String personId, String lastName, String email) {
        return new Map<String, String>{
            'Contact1.Id' => personId,
            'Contact1.FirstName' => 'Ana',
            'Contact1.LastName' => lastName,
            'Contact1.Email' => email,
            'Contact1.MailingCity' => 'Bend'
        };
    }

    private static Id recordTypeId(String developerName) {
        return Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName)
            .getRecordTypeId();
    }

    /** Runs one pass the way the platform drives the batch, in chunks of 200. */
    private static Import_Batch__c run(Id batchId, Boolean dryRun) {
        ImportBatchService.beginPass(batchId);
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> chunk = new List<Import_Row__c>();
        Database.QueryLocatorIterator rows = job.start(null).iterator();
        while (rows.hasNext()) {
            chunk.add((Import_Row__c) rows.next());
            if (chunk.size() == 200 || !rows.hasNext()) {
                job.execute(null, chunk);
                chunk = new List<Import_Row__c>();
            }
        }
        job.finish(null);
        return ImportBatchSelector.selectById(batchId);
    }

    /** Dry runs then commits, checking the dry run counted what the commit did. */
    private static Import_Batch__c load(Id batchId) {
        Import_Batch__c dryRun = run(batchId, true);
        Import_Batch__c committed = run(batchId, false);
        Assert.areEqual(dryRun.Rows_Created__c, committed.Rows_Created__c, 'Created as previewed.');
        Assert.areEqual(dryRun.Rows_Updated__c, committed.Rows_Updated__c, 'Updated as previewed.');
        Assert.areEqual(
            dryRun.Rows_Rejected__c,
            committed.Rows_Rejected__c,
            'Rejected as previewed.'
        );
        return committed;
    }

    private static List<Import_Row__c> rowsOf(Id batchId) {
        return [
            SELECT Id, Status__c, Error_Message__c, Contact_1__c, Organization__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batchId
            ORDER BY Row_Number__c ASC
        ];
    }

    private static String format(String label, String value) {
        return String.format(label, new List<String>{ value });
    }

    @IsTest
    static void aRecordIdLoadsThatRecordWhateverTheRuleSays() {
        System.runAs(TestUsers.admin()) {
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Lopez',
                Email = 'ana@old.test'
            );
            insert ana;
            Import_Batch__c batch = ImportTestDataFactory.batch(template());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{ row(ana.Id, 'Lopez', 'ana@new.test') }
            );

            Test.startTest();
            Import_Batch__c committed = load(batch.Id);
            Test.stopTest();

            Import_Row__c staged = rowsOf(batch.Id)[0];
            Assert.areEqual(ana.Id, staged.Contact_1__c, 'Loaded into the record the ID names.');
            Assert.areEqual(1, committed.Rows_Updated__c, 'Updated, not created.');
            Contact stored = [SELECT Email, MailingCity FROM Contact WHERE Id = :ana.Id];
            Assert.areEqual('Bend', stored.MailingCity, 'The row is written to it.');
            Assert.areEqual(
                'ana@new.test',
                stored.Email,
                'Even the email the rule would match on.'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Nobody added.');
            Assert.isFalse(
                String.valueOf(committed.Run_Log__c).contains(Contact.Id.getDescribe().getLabel()),
                'The ID is not reported as a field the user may not write.'
            );
        }
    }

    @IsTest
    static void anIdNotFoundRejectsTheRowAndCreatesNothing() {
        System.runAs(TestUsers.admin()) {
            Contact gone = new Contact(LastName = 'Gone');
            insert gone;
            Id goneId = gone.Id;
            delete gone;
            Import_Batch__c batch = ImportTestDataFactory.batch(template());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{ row(goneId, 'Gone', 'gone@example.test') }
            );

            Test.startTest();
            load(batch.Id);
            Test.stopTest();

            Import_Row__c staged = rowsOf(batch.Id)[0];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, staged.Status__c, 'Rejected.');
            Assert.areEqual(
                format(Label.Core_Import_ErrorRecordIdNotFound, goneId),
                staged.Error_Message__c,
                'Says the ID was not found.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Contact], 'Never created instead.');
        }
    }

    @IsTest
    static void anIdOfTheWrongKindOrNoIdAtAllRejectsTheRow() {
        System.runAs(TestUsers.admin()) {
            Account organization = new Account(
                Name = 'Harbor Trust',
                RecordTypeId = recordTypeId('Organization')
            );
            Account household = new Account(
                Name = 'Lopez Household',
                RecordTypeId = recordTypeId('Household')
            );
            insert new List<Account>{ organization, household };
            Contact ana = new Contact(LastName = 'Lopez');
            insert ana;
            Map<String, String> personIsAnAccount = row(organization.Id, 'Lopez', null);
            Map<String, String> organizationIsAContact = row(null, 'Lopez', null);
            organizationIsAContact.put('Organization.Id', ana.Id);
            Map<String, String> organizationIsAHousehold = row(null, 'Lopez', null);
            organizationIsAHousehold.put('Organization.Id', household.Id);
            Map<String, String> notAnId = row('not-an-id', 'Lopez', null);
            Import_Batch__c batch = ImportTestDataFactory.batch(template());
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    personIsAnAccount,
                    organizationIsAContact,
                    organizationIsAHousehold,
                    notAnId
                }
            );

            Test.startTest();
            Import_Batch__c committed = load(batch.Id);
            Test.stopTest();

            List<Import_Row__c> staged = rowsOf(batch.Id);
            Assert.areEqual(4, committed.Rows_Rejected__c, 'Every row rejected.');
            Assert.areEqual(
                format(Label.Core_Import_ErrorRecordIdNotPerson, organization.Id),
                staged[0].Error_Message__c,
                'An account is not a person here.'
            );
            Assert.areEqual(
                format(Label.Core_Import_ErrorRecordIdNotOrganization, ana.Id),
                staged[1].Error_Message__c,
                'A contact is not an organization.'
            );
            Assert.areEqual(
                format(Label.Core_Import_ErrorRecordIdNotOrganization, household.Id),
                staged[2].Error_Message__c,
                'Nor is a household.'
            );
            Assert.areEqual(
                format(Label.Core_Import_ErrorRecordIdInvalid, 'not-an-id'),
                staged[3].Error_Message__c,
                'Text that is no ID says so.'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void anOrganizationIdMatchesThatOrganizationAndABlankIdUsesTheRule() {
        System.runAs(TestUsers.admin()) {
            Account organization = new Account(
                Name = 'Harbor Trust',
                RecordTypeId = recordTypeId('Organization')
            );
            insert organization;
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Lopez',
                Email = 'ana@example.test'
            );
            insert ana;
            Map<String, String> values = row('  ', 'Lopez', 'ana@example.test');
            values.put('Organization.Id', organization.Id);
            values.put('Organization.Name', 'Another Name');
            Import_Batch__c batch = ImportTestDataFactory.batch(template());
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ values });

            Test.startTest();
            load(batch.Id);
            Test.stopTest();

            Import_Row__c staged = rowsOf(batch.Id)[0];
            Assert.areEqual(
                organization.Id,
                staged.Organization__c,
                'The organization the ID names.'
            );
            Assert.areEqual(ana.Id, staged.Contact_1__c, 'A blank ID: matched by email.');
            Assert.areEqual(
                'Harbor Trust',
                [SELECT Name FROM Account WHERE Id = :organization.Id].Name,
                'Not renamed.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE RecordTypeId = :recordTypeId('Organization')],
                'No organization added.'
            );
        }
    }

    @IsTest
    static void matchOnlyRejectsRowsThatMatchNobody() {
        System.runAs(TestUsers.admin()) {
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Lopez',
                Email = 'ana@example.test'
            );
            insert ana;
            Import_Template__c template = template();
            Import_Batch__c batch = ImportBatchService.create(
                template.Id,
                null,
                'updates.csv',
                null,
                null,
                null,
                true
            );
            Map<String, String> newOrganization = row(null, 'Lopez', 'ana@example.test');
            newOrganization.put('Organization.Name', 'New Trust');
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    row(null, 'Lopez', 'ana@example.test'),
                    row(null, 'Rivera', 'new@example.test'),
                    newOrganization
                }
            );

            Test.startTest();
            Import_Batch__c committed = load(batch.Id);
            Test.stopTest();

            List<Import_Row__c> staged = rowsOf(batch.Id);
            Assert.isTrue(committed.Match_Only__c, 'The batch is marked.');
            Assert.areEqual(ana.Id, staged[0].Contact_1__c, 'A matching row loads.');
            Assert.areEqual(
                Label.Core_Import_ErrorMatchOnlyNoMatch,
                staged[1].Error_Message__c,
                'A new person is rejected.'
            );
            Assert.areEqual(
                Label.Core_Import_ErrorMatchOnlyNoMatch,
                staged[2].Error_Message__c,
                'And a new organization.'
            );
            Assert.areEqual(0, committed.Rows_Created__c, 'Nothing created.');
            Assert.areEqual(1, [SELECT COUNT() FROM Contact], 'Nobody added.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Name = 'New Trust'],
                'No organization added.'
            );
        }
    }

    @IsTest
    static void twoHundredRowsLoadByRecordId() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(new Contact(FirstName = 'Ana', LastName = 'Lopez' + i));
            }
            insert people;
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Contact person : people) {
                values.add(row(person.Id, null, null));
            }
            Import_Batch__c batch = ImportTestDataFactory.batch(template());
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            Import_Batch__c committed = load(batch.Id);
            Test.stopTest();

            Assert.areEqual(200, committed.Rows_Updated__c, 'Every row updated its record.');
            Assert.areEqual(0, committed.Rows_Created__c, 'None created.');
            Assert.areEqual(
                0,
                committed.Rows_Rejected__c,
                'None rejected, though none has a name.'
            );
            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Contact WHERE MailingCity = 'Bend'],
                'Each written.'
            );
            Assert.areEqual(200, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void twoHundredRowsUnderMatchOnlyRejectEveryNewPerson() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 100; i++) {
                people.add(
                    new Contact(
                        FirstName = 'Ana',
                        LastName = 'Lopez',
                        Email = 'ana' + i + '@a.test'
                    )
                );
            }
            insert people;
            List<Map<String, String>> values = new List<Map<String, String>>();
            for (Integer i = 0; i < 200; i++) {
                values.add(row(null, 'Lopez', 'ana' + i + '@a.test'));
            }
            Import_Batch__c batch = ImportBatchService.create(
                template().Id,
                null,
                'updates.csv',
                null,
                null,
                null,
                true
            );
            ImportTestDataFactory.rows(batch, values);

            Test.startTest();
            Import_Batch__c committed = load(batch.Id);
            Test.stopTest();

            Assert.areEqual(100, committed.Rows_Rejected__c, 'The hundred new people rejected.');
            Assert.areEqual(100, committed.Rows_Updated__c, 'The hundred known ones updated.');
            Assert.areEqual(0, committed.Rows_Created__c, 'Nothing created.');
            Assert.areEqual(100, [SELECT COUNT() FROM Contact], 'Nobody added.');
        }
    }

    @IsTest
    static void aValueForEveryRowCannotGiveAPersonId() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(ImportMapping.namesAPerson('Contact1.Id', null), 'Every row one person.');
            Assert.isTrue(ImportMapping.namesAPerson('Contact2.id', null), 'Either person.');
            Assert.isFalse(
                ImportMapping.namesAPerson('Organization.Id', null),
                'Every row one organization is fine.'
            );
        }
    }
}
