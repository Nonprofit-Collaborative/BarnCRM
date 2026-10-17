/**
 * Donation matching (G-24, canonical model R-DM1 to R-DM6): which scheduled payment an
 * imported gift pays, under each of the four behaviours. Run as Maria, who holds the admin
 * permission sets, because the payments are read in her own mode.
 */
@IsTest(testFor='ApexClass:DonationMatcher')
private class DonationMatcherTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static User maria() {
        return TestDataFactory.createUser(
            'Maria',
            new List<String>{ 'BarnCRM_Admin', 'Giving_Admin' }
        );
    }

    /** An active pledge of this person with a payment due on each of these days of March. */
    private static List<Installment__c> pledge(Id personId, Map<Integer, Decimal> dueDays) {
        Commitment__c pledge = new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = personId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.newInstance(2026, 1, 1),
            Expected_Total__c = 1200,
            Installments_Planned__c = 12
        );
        insert pledge;
        // The schedule the pledge generates is replaced by the payments the test names.
        delete [SELECT Id FROM Installment__c WHERE Commitment__c = :pledge.Id];
        List<Installment__c> payments = new List<Installment__c>();
        Integer sequence = 1;
        for (Integer day : dueDays.keySet()) {
            payments.add(
                new Installment__c(
                    Commitment__c = pledge.Id,
                    Sequence__c = sequence++,
                    Due_Date__c = Date.newInstance(2026, 3, day),
                    Expected_Amount__c = dueDays.get(day),
                    Status__c = 'Scheduled'
                )
            );
        }
        insert payments;
        return [
            SELECT Id, Name, Due_Date__c, Commitment__c
            FROM Installment__c
            WHERE Id IN :payments
            ORDER BY Due_Date__c
        ];
    }

    /** A gift of this amount on 15 March, given by this person. */
    private static GiftImportRow gift(Id personId, Id householdId, Decimal amount) {
        GiftImportRow item = new GiftImportRow(
            new Import_Row__c(Household__c = householdId),
            new Map<String, Map<String, String>>{
                'Gift' => new Map<String, String>{
                    'Amount__c' => String.valueOf(amount),
                    'Gift_Date__c' => '2026-03-15',
                    'Type__c' => 'Cash'
                }
            }
        );
        item.donorContactId = personId;
        return item;
    }

    private static Import_Template__c template(String behaviour, Integer days, Decimal allowed) {
        return new Import_Template__c(
            Payment_Matching__c = behaviour,
            Match_Date_Window_Days__c = days,
            Match_Amount_Tolerance__c = allowed
        );
    }

    private static Integer match(Import_Template__c template, List<GiftImportRow> gifts) {
        Integer matched;
        System.runAs(maria()) {
            matched = new DonationMatcher(template).match(gifts);
        }
        return matched;
    }

    @IsTest
    static void theClosestPaymentForTheAmountWinsAndIsClaimedOnce() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(
                ana.Id,
                new Map<Integer, Decimal>{ 11 => 100, 17 => 100, 15 => 95 }
            );
            List<GiftImportRow> gifts = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100),
                gift(ana.Id, ana.AccountId, 100),
                gift(ana.Id, ana.AccountId, 100)
            };

            Integer matched = match(null, gifts);

            Assert.areEqual(2, matched, 'Two payments of 100 fall within the default 7 days.');
            Assert.areEqual(payments[2].Id, gifts[0].installmentId, 'The 17th: two days away.');
            Assert.areEqual(payments[2].Commitment__c, gifts[0].commitmentId, 'With its pledge.');
            Assert.areEqual(payments[0].Id, gifts[1].installmentId, 'Then the 11th, not claimed.');
            Assert.isNull(gifts[2].installmentId, 'The 95 on the 15th is not the amount.');
            Assert.isNull(gifts[2].error, 'Match or create: created on its own.');
        }
    }

    @IsTest
    static void aPaymentAnEarlierChunkClaimedIsNotOfferedAgain() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            List<GiftImportRow> firstChunk = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };
            List<GiftImportRow> secondChunk = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };

            match(null, firstChunk);
            Integer paying = new DonationMatcher(null).carryClaims(firstChunk);
            // The next chunk is a new transaction; Core's batch hands this state back to it.
            Assert.isNotNull(ImportEntityProcessors.carriedState, 'The claim is carried.');
            match(null, secondChunk);

            Assert.areEqual(1, paying, 'The first chunk pays the payment.');
            Assert.areEqual(payments[0].Id, firstChunk[0].installmentId, 'Matched.');
            Assert.isNull(secondChunk[0].installmentId, 'So the dry run agrees with the commit.');
        }
    }

    @IsTest
    static void theTemplateWindowAndToleranceComeBeforeTheSettings() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            settings.Donation_Match_Date_Window_Days__c = 1;
            upsert settings;
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 18 => 95 });
            List<GiftImportRow> bySettings = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 95)
            };
            List<GiftImportRow> byTemplate = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };

            match(null, bySettings);
            match(template(null, 3, 5), byTemplate);

            Assert.isNull(
                bySettings[0].installmentId,
                'Three days is outside the org window of 1.'
            );
            Assert.areEqual(payments[0].Id, byTemplate[0].installmentId, 'Within 3 days and 5.');
        }
    }

    @IsTest
    static void aPaymentOfSomeoneInTheHouseholdIsFound() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            Contact ben = new Contact(
                FirstName = 'Ben',
                LastName = 'Ramirez',
                AccountId = ana.AccountId
            );
            insert ben;
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            Contact stranger = GivingTestDataFactory.insertHouseholdContact('Lee', 'Kim', 'Lee');
            List<GiftImportRow> gifts = new List<GiftImportRow>{
                gift(stranger.Id, stranger.AccountId, 100),
                gift(ben.Id, ana.AccountId, 100)
            };

            match(null, gifts);

            Assert.isNull(gifts[0].installmentId, 'Another household pays nothing of Ana.');
            Assert.areEqual(payments[0].Id, gifts[1].installmentId, 'Ben pays Ana\'s pledge.');
        }
    }

    @IsTest
    static void twoPaymentsEquallyCloseAreATieNamingBoth() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(
                ana.Id,
                new Map<Integer, Decimal>{ 13 => 100, 17 => 100 }
            );
            List<GiftImportRow> gifts = new List<GiftImportRow>{ gift(ana.Id, ana.AccountId, 100) };

            match(null, gifts);

            Assert.isNull(gifts[0].installmentId, 'Not guessed.');
            Assert.isTrue(
                gifts[0].error.contains(payments[0].Name) &&
                gifts[0].error.contains(payments[1].Name),
                'Both are named: ' + gifts[0].error
            );
        }
    }

    @IsTest
    static void eachBehaviourDoesWhatItSays() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            List<GiftImportRow> always = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };
            List<GiftImportRow> never = new List<GiftImportRow>{ gift(ana.Id, ana.AccountId, 100) };
            List<GiftImportRow> only = new List<GiftImportRow>{ gift(ana.Id, ana.AccountId, 50) };
            GiftImportRow loaded = gift(ana.Id, ana.AccountId, 100);
            loaded.externalId = 'TX-1';
            loaded.matchedExisting = true;

            Assert.areEqual(
                0,
                match(template(DonationMatcher.ALWAYS_CREATE, null, null), always),
                'None.'
            );
            match(template(DonationMatcher.NEVER_MATCH, null, null), never);
            match(template(DonationMatcher.MATCH_ONLY, null, null), only);
            new DonationMatcher(template(DonationMatcher.NEVER_MATCH, null, null))
                .refuseExistingUnderNeverMatch(new List<GiftImportRow>{ loaded });

            Assert.isNull(always[0].installmentId, 'Always create does not look.');
            Assert.isNull(always[0].error, 'And creates.');
            Assert.isTrue(never[0].error.contains(payments[0].Name), 'Never match names it.');
            Assert.areEqual(Label.Giving_Import_ErrorMatchOnlyNone, only[0].error, 'Match only.');
            Assert.isTrue(loaded.error.contains('TX-1'), 'A gift already loaded is refused too.');
        }
    }

    @IsTest
    static void anImportedGiftPaysTheScheduledPayment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            GivingTestDataFactory.insertDefaultFund();
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org'
            );
            insert ana;
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 14 => 100 });
            // Paying a payment updates it in the importer's own mode, so Maria, who imports, is
            // the one who can edit this pledge: she owns it.
            User importer = maria();
            update new Commitment__c(Id = payments[0].Commitment__c, OwnerId = importer.Id);
            ImportMapping mapping = new ImportMapping();
            Map<String, String> row = new Map<String, String>{
                'Contact1.Email' => 'ana@example.org',
                'Contact1.LastName' => 'Ramirez',
                'Gift.Amount__c' => '100',
                'Gift.Gift_Date__c' => '2026-03-15',
                'Gift.Type__c' => 'Card'
            };
            for (String target : row.keySet()) {
                mapping.getColumns().add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });

            System.runAs(importer) {
                Test.startTest();
                ImportRowProcessor.process(
                    batch,
                    template,
                    ImportMapping.parse(template.Column_Mapping_JSON__c),
                    ImportTestDataFactory.reload(batch.Id),
                    false
                );
                Test.stopTest();
            }

            Import_Row__c after = [
                SELECT Status__c, Error_Message__c, Gift_Id__c
                FROM Import_Row__c
                WHERE Import_Batch__c = :batch.Id
            ];
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                after.Status__c,
                'Created: ' + after.Error_Message__c
            );
            Gift__c made = [
                SELECT Installment__c, Commitment__c
                FROM Gift__c
                WHERE Id = :after.Gift_Id__c
            ];
            Assert.areEqual(
                payments[0].Id,
                made.Installment__c,
                'The gift pays the 14 March payment.'
            );
            Assert.areEqual(payments[0].Commitment__c, made.Commitment__c, 'Of the pledge.');
            Assert.areEqual(
                'Paid',
                [SELECT Status__c FROM Installment__c WHERE Id = :payments[0].Id].Status__c,
                'And the payment is paid, through the ordinary gift path.'
            );
        }
    }

    @IsTest
    static void undoingAnImportedPaymentReopensThePaymentAndThePledge() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            GivingTestDataFactory.insertDefaultFund();
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org'
            );
            insert ana;
            // One payment of the whole 1200, so the imported gift completes the pledge.
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 14 => 1200 });
            User importer = maria();
            update new Commitment__c(Id = payments[0].Commitment__c, OwnerId = importer.Id);
            ImportMapping mapping = new ImportMapping();
            Map<String, String> row = new Map<String, String>{
                'Contact1.Email' => 'ana@example.org',
                'Contact1.LastName' => 'Ramirez',
                'Gift.Amount__c' => '1200',
                'Gift.Gift_Date__c' => '2026-03-15',
                'Gift.Type__c' => 'Card'
            };
            for (String target : row.keySet()) {
                mapping.getColumns().add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
            Map<Id, String> kept;

            System.runAs(importer) {
                Test.startTest();
                ImportRowProcessor.process(
                    batch,
                    template,
                    ImportMapping.parse(template.Column_Mapping_JSON__c),
                    ImportTestDataFactory.reload(batch.Id),
                    false
                );
                Gift__c made = [SELECT Id FROM Gift__c WHERE Installment__c = :payments[0].Id];
                Assert.areEqual(
                    'Completed',
                    [SELECT Status__c FROM Commitment__c WHERE Id = :payments[0].Commitment__c]
                    .Status__c,
                    'The imported payment completed the pledge.'
                );
                // The undo asks the module what to keep, then deletes the rest as the importer.
                kept = new GiftImportProcessor()
                    .reasonsToKeep(batch.Id, Gift__c.SObjectType, new Set<Id>{ made.Id });
                if (!kept.containsKey(made.Id)) {
                    Database.delete(made, true, AccessLevel.USER_MODE);
                }
                Test.stopTest();
            }

            Assert.isTrue(kept.isEmpty(), 'Nothing keeps the matched gift: ' + kept);
            Assert.areNotEqual(
                'Paid',
                [SELECT Status__c FROM Installment__c WHERE Id = :payments[0].Id].Status__c,
                'The payment is owed again.'
            );
            Assert.areEqual(
                'Active',
                [SELECT Status__c FROM Commitment__c WHERE Id = :payments[0].Commitment__c]
                .Status__c,
                'And the pledge is open again.'
            );
        }
    }

    @IsTest
    static void aCommitMatchesUnderTheValuesItsDryRunRecorded() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact ana = GivingTestDataFactory.insertHouseholdContact('Ramirez', 'Ana', 'Ramirez');
            pledge(ana.Id, new Map<Integer, Decimal>{ 15 => 100 });
            Import_Batch__c recorded = new Import_Batch__c(
                Processor_Settings_JSON__c = new DonationMatcher(
                        template(DonationMatcher.MATCH_OR_CREATE, 3, 0)
                    )
                    .record()
            );
            List<GiftImportRow> heldToTheRecord = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };
            List<GiftImportRow> noRecord = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };
            List<GiftImportRow> unreadable = new List<GiftImportRow>{
                gift(ana.Id, ana.AccountId, 100)
            };
            // The template was changed to Always create after the dry run.
            Import_Template__c now = template(DonationMatcher.ALWAYS_CREATE, null, null);

            System.runAs(maria()) {
                DonationMatcher.forRun(recorded, now, false).match(heldToTheRecord);
                DonationMatcher.forRun(new Import_Batch__c(), now, false).match(noRecord);
                DonationMatcher.forRun(
                        new Import_Batch__c(Processor_Settings_JSON__c = 'not a record'),
                        now,
                        false
                    )
                    .match(unreadable);
            }

            Assert.isNotNull(heldToTheRecord[0].installmentId, 'The commit does what was shown.');
            Assert.isNull(
                noRecord[0].installmentId,
                'A batch dry run before records follows the template.'
            );
            Assert.isNull(
                unreadable[0].installmentId,
                'And so does one whose record cannot be read.'
            );
        }
    }

    /** Runs one pass of an import the way the platform drives the batch, a chunk per row. */
    private static void runPass(Id batchId, Boolean dryRun) {
        ImportBatchService.beginPass(batchId);
        ImportProcessorBatch job = new ImportProcessorBatch(batchId, dryRun);
        List<Import_Row__c> rows = new List<Import_Row__c>();
        Database.QueryLocatorIterator staged = job.start(null).iterator();
        while (staged.hasNext()) {
            rows.add((Import_Row__c) staged.next());
        }
        for (Import_Row__c row : rows) {
            job.execute(null, new List<Import_Row__c>{ row });
        }
        job.finish(null);
    }

    @IsTest
    static void aTemplateEditedAfterTheDryRunDoesNotChangeTheCommit() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            GivingTestDataFactory.insertDefaultFund();
            Contact ana = new Contact(
                FirstName = 'Ana',
                LastName = 'Ramirez',
                Email = 'ana@example.org'
            );
            insert ana;
            List<Installment__c> payments = pledge(ana.Id, new Map<Integer, Decimal>{ 14 => 100 });
            User importer = maria();
            update new Commitment__c(Id = payments[0].Commitment__c, OwnerId = importer.Id);
            ImportMapping mapping = new ImportMapping();
            Map<String, String> row = new Map<String, String>{
                'Contact1.Email' => 'ana@example.org',
                'Contact1.LastName' => 'Ramirez',
                'Gift.Amount__c' => '100',
                'Gift.Gift_Date__c' => '2026-03-15',
                'Gift.Type__c' => 'Card'
            };
            for (String target : row.keySet()) {
                mapping.getColumns().add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
            Import_Batch__c afterDryRun;

            System.runAs(importer) {
                Test.startTest();
                runPass(batch.Id, true);
                afterDryRun = ImportBatchSelector.selectById(batch.Id);
                // Between the preview and the commit, somebody says nothing may match.
                update new Import_Template__c(
                    Id = template.Id,
                    Payment_Matching__c = DonationMatcher.NEVER_MATCH
                );
                runPass(batch.Id, false);
                Test.stopTest();
            }

            Assert.isNotNull(
                afterDryRun.Processor_Settings_JSON__c,
                'The dry run recorded its values.'
            );
            Assert.areEqual(
                1,
                afterDryRun.Rows_Created__c,
                'It showed the gift paying the payment.'
            );
            Import_Row__c after = [
                SELECT Status__c, Error_Message__c, Gift_Id__c
                FROM Import_Row__c
                WHERE Import_Batch__c = :batch.Id
            ];
            Assert.areEqual(
                ImportRowProcessor.STATUS_CREATED,
                after.Status__c,
                'Never match would have refused it: ' + after.Error_Message__c
            );
            Assert.areEqual(
                payments[0].Id,
                [SELECT Installment__c FROM Gift__c WHERE Id = :after.Gift_Id__c].Installment__c,
                'The commit matched as the dry run showed.'
            );
        }
    }

    @IsTest
    static void aSecondDryRunAfterATemplateEditReplacesTheRecordedValues() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            TestDataFactory.defaultSettings();
            GivingTestDataFactory.insertDefaultFund();
            insert new Contact(FirstName = 'Ana', LastName = 'Ramirez', Email = 'ana@example.org');
            ImportMapping mapping = new ImportMapping();
            Map<String, String> row = new Map<String, String>{
                'Contact1.Email' => 'ana@example.org',
                'Contact1.LastName' => 'Ramirez',
                'Gift.Amount__c' => '100',
                'Gift.Gift_Date__c' => '2026-03-15',
                'Gift.Type__c' => 'Card'
            };
            for (String target : row.keySet()) {
                mapping.getColumns().add(new ImportMapping.Column(target, target));
            }
            Import_Template__c template = ImportTestDataFactory.template(
                mapping.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Import_Batch__c batch = ImportTestDataFactory.batch(template);
            ImportTestDataFactory.rows(batch, new List<Map<String, String>>{ row });
            String first;
            String second;

            System.runAs(maria()) {
                Test.startTest();
                runPass(batch.Id, true);
                first = ImportBatchSelector.selectById(batch.Id).Processor_Settings_JSON__c;
                update new Import_Template__c(
                    Id = template.Id,
                    Payment_Matching__c = DonationMatcher.MATCH_ONLY,
                    Match_Date_Window_Days__c = 3
                );
                runPass(batch.Id, true);
                second = ImportBatchSelector.selectById(batch.Id).Processor_Settings_JSON__c;
                Test.stopTest();
            }

            Assert.isTrue(
                first.contains(DonationMatcher.MATCH_OR_CREATE),
                'The first dry run: ' + first
            );
            Assert.isTrue(
                second.contains(DonationMatcher.MATCH_ONLY),
                'The second replaced it: ' + second
            );
            Assert.isTrue(second.contains('"matchDateWindowDays":3'), 'Window and all: ' + second);
            Assert.areEqual(
                ImportRowProcessor.STATUS_REJECTED,
                [SELECT Status__c FROM Import_Row__c WHERE Import_Batch__c = :batch.Id].Status__c,
                'And the second dry run showed Match only refusing the gift with no payment.'
            );
        }
    }
}
