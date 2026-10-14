/**
 * Undoing a gift import that created people (canonical model R-IB9, R-GI9, ADR-NEXT).
 *
 * Deleting the imported gifts sets off the donors' rollups. In an org the Rollup Queue saves
 * them, started by its platform event as the Automated Process user: somebody other than the
 * person undoing. Here the gift pass runs as a second user, so the totals it sets off are saved
 * by somebody who is not the undo, as they are in an org. Those saves are not edits, and the
 * people go; a person somebody edited after the import stays.
 */
@IsTest(testFor='ApexClass:GiftImportProcessor')
private class GiftImportUndoTest {
    private static final Integer DONORS = 3;

    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith('Giving_Admin');
        TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'Giving_Staff' }
        );
        TestUsers.admin();
    }

    /** The second user the gift pass runs as: it deletes gifts, so it holds Giving Admin. */
    private static User rollupQueue() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Admin', 'Giving_Staff' }
        );
    }

    private static Import_Batch__c batch;

    /**
     * Imports one gift from each of three new donors, with the shipped rollups recalculated in
     * the save, and marks the batch committed by the running user five minutes ago.
     */
    private static void imported(String personMode) {
        TestDataFactory.defaultSettings();
        GivingTestDataFactory.insertDefaultFund();
        GivingRollupTestData.installShippedRollups();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        mapping.columns.add(new ImportMapping.Column('Payment Method', 'Gift.Type__c'));
        mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
        mapping.columns.add(new ImportMapping.Column('Date', 'Gift.Gift_Date__c'));
        Import_Template__c template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        if (personMode != null) {
            template.Person_Mode__c = personMode;
            update template;
        }
        batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer index = 0; index < DONORS; index++) {
            rows.add(
                new Map<String, String>{
                    'Email' => 'donor' +
                    index +
                    '@example.org',
                    'Last Name' => 'Donor' + index,
                    'Payment Method' => 'cash',
                    'Amount' => '100.00',
                    'Date' => '2026-03-15'
                }
            );
        }
        ImportTestDataFactory.rows(batch, rows);
        batch.Started_At__c = Datetime.now().addMinutes(-5);
        update batch;
        ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            false
        );
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMPLETE;
        batch.Completed_At__c = Datetime.now().addMinutes(1);
        batch.Committed_By__c = UserInfo.getUserId();
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
        Assert.areEqual(
            DONORS,
            [SELECT COUNT() FROM Gift__c WHERE Created_By_Import_Batch__c = :batch.Id],
            'One gift a donor was imported.'
        );
    }

    /** The people and accounts the batch created that are still there. */
    private static Integer taggedLeft() {
        return [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id] +
            [SELECT COUNT() FROM Account WHERE Created_By_Import_Batch__c = :batch.Id];
    }

    /** The imported people: contacts, or person accounts in that mode. */
    private static List<SObject> people(Boolean personAccounts) {
        Id owner = batch.Id;
        Set<Id> personTypes = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (personAccounts) {
            return [
                SELECT Id
                FROM Account
                WHERE Created_By_Import_Batch__c = :owner AND RecordTypeId IN :personTypes
                ORDER BY Id
            ];
        }
        return [SELECT Id FROM Contact WHERE Created_By_Import_Batch__c = :owner ORDER BY Id];
    }

    /**
     * Undoes the batch as the running user, its gifts deleted by the second user, so the
     * totals they set off are saved by somebody who is not the undo.
     */
    private static void undo() {
        GivingRollupTestData.nextSave();
        Integer total = ImportUndoService.preview(batch.Id).total;
        // Latched only: the passes below are the only ones that run.
        System.abortJob(ImportUndoService.start(batch.Id, total));
        ImportUndoTestSupport.Run run = new ImportUndoTestSupport.Run(
            batch.Id,
            total,
            Datetime.newInstance((Datetime.now().getTime() / 1000) * 1000)
        );
        System.runAs(rollupQueue()) {
            run.beforePeople();
        }
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Gift__c WHERE Created_By_Import_Batch__c = :batch.Id],
            'The gifts are gone first.'
        );
        run.rest();
    }

    @IsTest
    static void undoingRemovesThePeopleWhoseTotalsTheUndoRecalculated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            imported(null);
            Assert.areEqual(DONORS, people(false).size(), 'Three people were imported.');

            undo();

            Assert.areEqual(0, taggedLeft(), 'Every person and household the import made goes.');
        }
    }

    @IsTest
    static void aPersonEditedAfterTheImportIsKept() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            imported(null);
            Contact edited = (Contact) people(false)[0];
            System.runAs(TestUsers.admin()) {
                // Somebody else's edit to a field no rollup writes. A test runs within a
                // second, so the totals are dated an hour earlier, as they would be.
                Database.update(
                    new Contact(
                        Id = edited.Id,
                        Title = 'Board chair',
                        Rollups_Last_Calculated__c = Datetime.now().addHours(-1)
                    ),
                    AccessLevel.SYSTEM_MODE
                );
            }

            undo();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id],
                'Only the edited person stays.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Id = :edited.Id],
                'And it is the one edited.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Account WHERE Created_By_Import_Batch__c = :batch.Id],
                'With the household they are still on.'
            );
        }
    }

    /**
     * The same undo where people are stored as person accounts. A Platform only org has none
     * (ADR-0013), so there the test returns at once: the contact shape is covered above.
     */
    @IsTest
    static void undoingRemovesPersonAccountsWhoseTotalsTheUndoRecalculated() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            if (
                OrgShapeDetector.detect().hasPersonAccounts != true ||
                OrgShapeDetector.creatablePersonRecordTypeId() == null
            ) {
                return;
            }
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            imported(ImportTemplateService.PERSON_MODE_PERSON_ACCOUNTS);
            Assert.areEqual(DONORS, people(true).size(), 'Three person accounts were imported.');

            undo();

            Assert.areEqual(0, taggedLeft(), 'Every person and household the import made goes.');
        }
    }
}
