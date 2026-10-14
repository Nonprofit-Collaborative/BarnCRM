/**
 * Gift import through Core's importer (G-23, canonical model Section 25N), run as Maria, who
 * holds the admin permission sets an import needs, so the tests also prove those sets carry
 * everything a gift import writes.
 *
 * Each test drives Core's row processor, which finds this package's processor by name, the
 * way a real import does.
 */
@IsTest(testFor='ApexClass:GiftImportProcessor')
private class GiftImportProcessorTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static Import_Template__c template;
    private static Import_Batch__c batch;

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    private static Fund__c fund(String name, String code, Boolean isDefault) {
        Fund__c fund = new Fund__c(
            Name = name,
            Accounting_Code__c = code,
            Active__c = true,
            Is_Default__c = isDefault
        );
        insert fund;
        return fund;
    }

    /**
     * A gift file: email and last name for the donor, then the given gift columns, and a
     * payment method of cash when the test names none.
     */
    private static void given(List<String> giftTargets, List<List<String>> values) {
        TestDataFactory.defaultSettings();
        ImportMapping mapping = new ImportMapping();
        mapping.columns.add(new ImportMapping.Column('Email', 'Contact1.Email'));
        mapping.columns.add(new ImportMapping.Column('Last Name', 'Contact1.LastName'));
        Boolean typed = giftTargets.contains('Gift.Type__c');
        if (!typed) {
            mapping.columns.add(new ImportMapping.Column('Payment Method', 'Gift.Type__c'));
        }
        for (String target : giftTargets) {
            mapping.columns.add(new ImportMapping.Column(target, target));
        }
        template = ImportTestDataFactory.template(
            mapping.serialize(),
            ImportTemplateService.RULE_EMAIL
        );
        batch = ImportTestDataFactory.batch(template);
        List<Map<String, String>> rows = new List<Map<String, String>>();
        for (Integer index = 0; index < values.size(); index++) {
            Map<String, String> row = new Map<String, String>{
                'Email' => 'donor' +
                index +
                '@example.org',
                'Last Name' => 'Donor' + index
            };
            if (!typed) {
                row.put('Payment Method', 'cash');
            }
            for (Integer column = 0; column < giftTargets.size(); column++) {
                row.put(giftTargets[column], values[index][column]);
            }
            rows.add(row);
        }
        ImportTestDataFactory.rows(batch, rows);
    }

    private static ImportRowProcessor.Outcome run(Boolean dryRun) {
        return ImportRowProcessor.process(
            batch,
            template,
            ImportMapping.parse(template.Column_Mapping_JSON__c),
            ImportTestDataFactory.reload(batch.Id),
            dryRun
        );
    }

    private static List<Import_Row__c> rows() {
        return [
            SELECT Row_Number__c, Status__c, Error_Message__c, Gift_Id__c, Contact_1__c
            FROM Import_Row__c
            WHERE Import_Batch__c = :batch.Id
            ORDER BY Row_Number__c
        ];
    }

    @IsTest
    static void aRowBecomesAnOrdinaryGiftForItsDonor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Fund__c scholarships = fund('Scholarships', 'SCH-1', false);
            given(
                new List<String>{
                    'Gift.Amount__c',
                    'Gift.Gift_Date__c',
                    'Gift.Type__c',
                    'Allocation.Fund'
                },
                new List<List<String>>{
                    new List<String>{ '250.00', '2026-03-15', 'cheque', 'sch-1' }
                }
            );
            ImportRowProcessor.Outcome outcome;

            System.runAs(maria()) {
                Test.startTest();
                outcome = run(false);
                Test.stopTest();
            }

            Import_Row__c row = rows()[0];
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                row.Status__c,
                'Created: ' + row.Error_Message__c + ' ' + outcome.notes
            );
            Gift__c gift = [
                SELECT
                    Donor_Contact__c,
                    Amount__c,
                    Gift_Date__c,
                    Type__c,
                    Status__c,
                    Created_By_Import_Batch__c,
                    (SELECT Fund__c, Amount__c FROM Gift_Allocations__r)
                FROM Gift__c
            ];
            Assert.areEqual(String.valueOf(gift.Id), row.Gift_Id__c, 'The row points at its gift.');
            Assert.areEqual(row.Contact_1__c, gift.Donor_Contact__c, 'Given by the row\'s person.');
            Assert.areEqual('Check', gift.Type__c, 'Cheque is Check.');
            Assert.areEqual('Received', gift.Status__c, 'Every imported gift is Received.');
            Assert.areEqual(batch.Id, gift.Created_By_Import_Batch__c, 'Tagged for undo (R-IB3).');
            Assert.areEqual(1, gift.Gift_Allocations__r.size(), 'One allocation, not two.');
            Assert.areEqual(
                scholarships.Id,
                gift.Gift_Allocations__r[0].Fund__c,
                'By accounting code.'
            );
            Assert.isTrue(outcome.fileAmount == 250, 'The amount read is handed back.');
        }
    }

    @IsTest
    static void aDryRunDecidesEverythingAndSavesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c', 'Allocation.Fund' },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15', 'General' },
                    new List<String>{ '20', '2026-03-15', 'Nowhere' }
                }
            );
            ImportRowProcessor.Outcome outcome;

            System.runAs(maria()) {
                Test.startTest();
                outcome = run(true);
                Test.stopTest();
            }

            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'A dry run writes nothing.');
            List<Import_Row__c> after = rows();
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                after[0].Status__c,
                'Would be created.'
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                after[1].Status__c,
                'Refused now: ' + outcome.notes
            );
            Assert.isTrue(
                after[1].Error_Message__c.contains('Nowhere'),
                'Naming the fund: ' + after[1].Error_Message__c
            );
            Assert.isTrue(outcome.fileAmount == 30, 'Both amounts count toward the control total.');
        }
    }

    @IsTest
    static void anExternalIdLoadsOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            // The first row's donor already exists too, so nothing on that row is new.
            Contact existingDonor = new Contact(LastName = 'Donor0', Email = 'donor0@example.org');
            insert existingDonor;
            Gift__c earlier = GivingTestDataFactory.buildGift(existingDonor.Id, 5);
            earlier.External_Id__c = 'stripe-1';
            insert earlier;
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c', 'Gift.External_Id__c' },
                new List<List<String>>{
                    new List<String>{ '5', '2026-03-15', 'STRIPE-1' },
                    new List<String>{ '7', '2026-03-15', 'stripe-2' },
                    new List<String>{ '7', '2026-03-15', 'stripe-2' }
                }
            );

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            List<Import_Row__c> after = rows();
            Assert.areEqual(
                ImportRowProcessor.STATUS_MATCHED,
                after[0].Status__c,
                'Loaded before: ' + after[0].Error_Message__c
            );
            Assert.areEqual(
                String.valueOf(earlier.Id),
                after[0].Gift_Id__c,
                'And points at that gift.'
            );
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, after[1].Status__c, 'New.');
            Assert.areEqual(
                after[1].Gift_Id__c,
                after[2].Gift_Id__c,
                'A repeat in the file shares it.'
            );
            Assert.areEqual(2, [SELECT COUNT() FROM Gift__c], 'One new gift, not two.');
        }
    }

    @IsTest
    static void aSplitIsSavedWhole() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Fund__c building = fund('Building', null, false);
            Fund__c scholarships = fund('Scholarships', null, false);
            given(
                new List<String>{
                    'Gift.Amount__c',
                    'Gift.Gift_Date__c',
                    'Allocation.Fund1',
                    'Allocation.Percent1',
                    'Allocation.Fund2',
                    'Allocation.Percent2'
                },
                new List<List<String>>{
                    new List<String>{
                        '100',
                        '2026-03-15',
                        'Building',
                        '33.33',
                        'Scholarships',
                        '66.67'
                    }
                }
            );

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                rows()[0].Status__c,
                'Created: ' + rows()[0].Error_Message__c
            );
            Map<Id, Decimal> byFund = new Map<Id, Decimal>();
            for (Gift_Allocation__c allocation : [
                SELECT Fund__c, Amount__c
                FROM Gift_Allocation__c
            ]) {
                byFund.put(allocation.Fund__c, allocation.Amount__c);
            }
            Assert.areEqual(2, byFund.size(), 'Two parts and no default allocation.');
            Assert.isTrue(
                byFund.get(building.Id) + byFund.get(scholarships.Id) == 100,
                'Exact total.'
            );
        }
    }

    @IsTest
    static void aRowThePlatformRefusesLeavesNoGift() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            // An in-kind gift with no description saves nowhere (R-G12): the dry run cannot know.
            given(
                new List<String>{ 'Gift.Gift_Date__c', 'Gift.Type__c', 'Allocation.Fund' },
                new List<List<String>>{ new List<String>{ '2026-03-15', 'in kind', 'General' } }
            );

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            Import_Row__c row = rows()[0];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Refused.');
            Assert.isNotNull(row.Error_Message__c, 'With the platform\'s reason.');
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift left behind.');
        }
    }

    @IsTest
    static void oneGiftWhoseFundIsRefusedCostsOnlyItsOwnRow() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Fund__c refused = fund('Roof', 'R-1', false);
            fund('Library', 'L-1', false);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c', 'Allocation.Fund' },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15', 'R-1' },
                    new List<String>{ '20', '2026-03-15', 'L-1' }
                }
            );
            GiftImportProcessor.fundsRefusedForTest.add(refused.Id);

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            List<Import_Row__c> after = rows();
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                after[0].Status__c,
                'The refused one.'
            );
            Assert.isTrue(
                after[0].Error_Message__c.contains('Refused for the test.'),
                'With why: ' + after[0].Error_Message__c
            );
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                after[1].Status__c,
                'Created: ' + after[1].Error_Message__c
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'Only the second row left a gift.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Gift_Allocation__c WHERE Fund__c != :refused.Id],
                'Designated to its own fund.'
            );
        }
    }

    @IsTest
    static void aRefusedDesignationLeavesNothingItWrote() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Fund__c refused = fund('Roof', 'R-1', false);
            fund('Library', 'L-1', false);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c', 'Allocation.Fund' },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15', 'R-1' },
                    new List<String>{ '20', '2026-03-15', 'L-1' }
                }
            );
            // The refusal comes after the designation and a record of its own were written, once
            // in the attempt for the whole chunk and once in the refused gift's own attempt.
            GiftImportProcessor.fundsRefusedForTest.add(refused.Id);

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Fund__c
                    WHERE Name = :GiftImportProcessor.WRITTEN_BEFORE_REFUSAL
                ],
                'Both failed attempts were undone.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Gift_Allocation__c WHERE Fund__c = :refused.Id],
                'The refused designation left no allocation.'
            );
            List<Import_Row__c> after = rows();
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                after[0].Status__c,
                'The refused one.'
            );
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, after[1].Status__c, 'The other.');
        }
    }

    @IsTest
    static void aChunkWithNoRoomLeftSaysTheRowWasNotAttempted() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Fund__c refused = fund('Roof', 'R-1', false);
            fund('Library', 'L-1', false);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c', 'Allocation.Fund' },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15', 'R-1' },
                    new List<String>{ '20', '2026-03-15', 'L-1' }
                }
            );
            GiftImportProcessor.fundsRefusedForTest.add(refused.Id);
            // More kept free than a transaction has: no gift is tried on its own.
            GiftImportProcessor.queriesKeptFree = 100000;

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            for (Import_Row__c row : rows()) {
                Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Not saved.');
                Assert.areEqual(
                    Label.Giving_Import_ErrorNotAttempted,
                    row.Error_Message__c,
                    'Saying why, and not blaming the row.'
                );
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift left behind.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Fund__c
                    WHERE Name = :GiftImportProcessor.WRITTEN_BEFORE_REFUSAL
                ],
                'The chunk\'s attempt was undone.'
            );
        }
    }

    @IsTest
    static void anImporterWhoCannotDeleteGiftsIsRefusedBeforeAnythingIsWritten() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c' },
                new List<List<String>>{ new List<String>{ '10', '2026-03-15' } }
            );
            User staff = TestDataFactory.createUser(
                'Staff',
                new List<String>{ 'BarnCRM_Admin', 'Giving_Staff' }
            );
            ImportRowProcessor.Outcome outcome;

            System.runAs(staff) {
                Test.startTest();
                outcome = run(false);
                Test.stopTest();
            }

            Import_Row__c row = rows()[0];
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, row.Status__c, 'Refused.');
            Assert.areEqual(
                Label.Giving_Import_ErrorCannotDeleteGifts,
                row.Error_Message__c,
                'Saying which permission is missing.'
            );
            Assert.isTrue(
                outcome.notes.contains(Label.Giving_Import_ErrorCannotDeleteGifts),
                'And once in the run log: ' + outcome.notes
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'No gift written.');
        }
    }

    @IsTest
    static void aRepeatSharesItsEarlierRowsRefusalInTheDryRunAsInTheCommit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            given(
                new List<String>{
                    'Gift.Amount__c',
                    'Gift.Gift_Date__c',
                    'Gift.External_Id__c',
                    'Allocation.Fund'
                },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15', 'stripe-9', 'Nowhere' },
                    new List<String>{ '10', '2026-03-15', 'STRIPE-9', 'Nowhere' }
                }
            );
            List<Import_Row__c> dryRun;

            System.runAs(maria()) {
                Test.startTest();
                run(true);
                dryRun = rows();
                run(false);
                Test.stopTest();
            }

            List<Import_Row__c> committed = rows();
            for (Integer index = 0; index < 2; index++) {
                Assert.areEqual(
                    ImportRowProcessor.STATUS_REJECTED,
                    dryRun[index].Status__c,
                    'Dry run, row ' + index + ': ' + dryRun[index].Error_Message__c
                );
                Assert.areEqual(
                    dryRun[index].Status__c,
                    committed[index].Status__c,
                    'The commit agrees on row ' + index
                );
                Assert.areEqual(
                    dryRun[index].Error_Message__c,
                    committed[index].Error_Message__c,
                    'For the same reason, row ' + index
                );
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Gift__c], 'Nothing saved.');
        }
    }

    @IsTest
    static void theDonorCanBeTheOrganization() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            TestDataFactory.defaultSettings();
            ImportMapping mapping = new ImportMapping();
            mapping.columns.add(new ImportMapping.Column('Contact', 'Contact1.LastName'));
            mapping.columns.add(new ImportMapping.Column('Company', 'Organization.Name'));
            mapping.columns.add(new ImportMapping.Column('Amount', 'Gift.Amount__c'));
            mapping.columns.add(new ImportMapping.Column('Date', 'Gift.Gift_Date__c'));
            mapping.defaults.add(new ImportMapping.Assignment('Gift.Donor', 'Organization'));
            mapping.defaults.add(new ImportMapping.Assignment('Gift.Type__c', 'Check'));
            template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(
                batch,
                new List<Map<String, String>>{
                    new Map<String, String>{
                        'Contact' => 'Okafor',
                        'Company' => 'Riverside Foundation',
                        'Amount' => '1000',
                        'Date' => '2026-03-15'
                    }
                }
            );

            System.runAs(maria()) {
                Test.startTest();
                run(false);
                Test.stopTest();
            }

            Import_Row__c row = rows()[0];
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                row.Status__c,
                'Created: ' + row.Error_Message__c
            );
            Gift__c gift = [SELECT Donor_Contact__c, Donor_Account__r.Name FROM Gift__c];
            Assert.isNull(gift.Donor_Contact__c, 'Not the contact person.');
            Assert.areEqual(
                'Riverside Foundation',
                gift.Donor_Account__r.Name,
                'The organization gave.'
            );
        }
    }

    // -------------------------------------------------------------------------------------
    // The posting lock (G-20, ADR-0053)
    // -------------------------------------------------------------------------------------

    @IsTest
    static void aRowDatedInAClosedPeriodIsRefusedInTheDryRunAndTheCommit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            Date closed = Date.today().toStartOfMonth().addDays(-1);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c' },
                new List<List<String>>{
                    new List<String>{ '10', String.valueOf(closed.addDays(-3)) },
                    new List<String>{ '20', String.valueOf(Date.today()) }
                }
            );
            GivingTestDataFactory.closeBooksThrough(closed);

            User maria = maria();
            System.runAs(maria) {
                Test.startTest();
                run(true);
                List<Import_Row__c> dry = rows();
                Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, dry[0].Status__c);
                Assert.isTrue(
                    dry[0].Error_Message__c.startsWith('The books are closed through'),
                    dry[0].Error_Message__c
                );
                Assert.areEqual(ImportRowProcessor.STATUS_CREATED, dry[1].Status__c);
                run(false);
                Test.stopTest();
            }

            List<Import_Row__c> committed = rows();
            Assert.areEqual(ImportRowProcessor.STATUS_REJECTED, committed[0].Status__c);
            Assert.areEqual(ImportRowProcessor.STATUS_CREATED, committed[1].Status__c);
            // Only the gift is refused: the person on the row is the person processor's, as for any
            // other gift refusal (R-IR7).
            Assert.areEqual(1, [SELECT COUNT() FROM Gift__c], 'Only the gift dated today');
        }
    }

    @IsTest
    static void anUndoKeepsPostedAndClosedPeriodGifts() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            fund('General', null, true);
            given(
                new List<String>{ 'Gift.Amount__c', 'Gift.Gift_Date__c' },
                new List<List<String>>{
                    new List<String>{ '10', '2026-03-15' },
                    new List<String>{ '20', String.valueOf(Date.today()) },
                    new List<String>{ '30', String.valueOf(Date.today()) }
                }
            );
            System.runAs(maria()) {
                run(false);
            }
            // Keyed by whole amount: a Decimal read back as 10.00 is not the key 10.
            Map<Integer, Id> giftIds = new Map<Integer, Id>();
            for (Gift__c gift : [SELECT Id, Amount__c FROM Gift__c]) {
                giftIds.put(gift.Amount__c.intValue(), gift.Id);
            }
            Assert.areEqual(3, giftIds.size(), 'All three imported');
            GivingTestDataFactory.closeBooksThrough(Date.newInstance(2026, 6, 30));
            GiftPostingService.postPermission = true;
            GiftPostingService.markPosted(new Set<Id>{ giftIds.get(20) });

            Map<Id, String> keep = new GiftImportProcessor()
                .reasonsToKeep(batch.Id, Gift__c.SObjectType, new Set<Id>(giftIds.values()));

            Assert.areEqual(Label.Giving_Import_UndoKeptClosedPeriod, keep.get(giftIds.get(10)));
            Assert.areEqual(Label.Giving_Import_UndoKeptPosted, keep.get(giftIds.get(20)));
            Assert.isFalse(keep.containsKey(giftIds.get(30)), 'An open, unposted gift can go');
        }
    }
}
