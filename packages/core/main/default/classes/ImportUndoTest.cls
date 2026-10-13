/**
 * Undoing an import (canonical model R-IB7 to R-IB9): what it counts, what it refuses, what
 * it deletes and what it keeps.
 *
 * The job's passes chain from one another's finish, which a test runs only once, so the
 * delete passes are driven here through the job's own start query, one pass after another.
 */
@IsTest
private class ImportUndoTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Import_Batch__c committedBatch() {
        // Core's undo is tested on its own: a module installed in the test org is not asked.
        ImportEntityProcessors.noneForTest = true;
        TestDataFactory.defaultSettings();
        Import_Batch__c batch = ImportTestDataFactory.batch(
            ImportTestDataFactory.template(
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            )
        );
        batch.Is_Dry_Run__c = false;
        batch.Status__c = ImportBatchService.STATUS_COMPLETE;
        batch.Started_At__c = Datetime.now().addMinutes(-5);
        batch.Completed_At__c = Datetime.now().addMinutes(1);
        batch.Committed_By__c = UserInfo.getUserId();
        batch.Undo_Deadline__c = Datetime.now().addDays(30);
        update batch;
        return batch;
    }

    @IsTest
    static void aCommitThePlatformAbortedIsUndone() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            // Left Committing, never finished, with no job running for it (R-IB13).
            batch.Status__c = ImportBatchService.STATUS_COMMITTING;
            batch.Completed_At__c = null;
            update batch;
            ImportBatchService.jobRunningForTest = false;
            Contact ana = importedPerson(batch, 'Ramirez');

            undo(batch);

            Assert.areEqual(0, [SELECT COUNT() FROM Contact WHERE Id = :ana.Id], 'Ana is removed.');
            Assert.areNotEqual(
                ImportBatchService.STATUS_COMMITTING,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
                'The batch is no longer stuck.'
            );
        }
    }

    @IsTest
    static void anAbortedCommitKeepsWhatChangedAfterItsJobEnded() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            batch.Status__c = ImportBatchService.STATUS_COMMITTING;
            batch.Completed_At__c = null;
            update batch;
            ImportBatchService.jobRunningForTest = false;
            // The job ended twenty minutes ago; Ana's record was changed after it, by the
            // committer, which the commit itself cannot have done (R-IB9, R-IB13).
            ImportBatchService.jobEndedForTest = Datetime.now().addMinutes(-20);
            Contact ana = importedPerson(batch, 'Ramirez');

            // Undo pressed a second later: in the same second her change would read as the undo's.
            undo(batch, Datetime.now().addSeconds(1));

            Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Id = :ana.Id], 'Ana is kept.');
        }
    }

    /** A person the import created, and the household it created for them, both tagged. */
    private static Contact importedPerson(Import_Batch__c batch, String lastName) {
        Contact person = new Contact(
            FirstName = 'Ana',
            LastName = lastName,
            Created_By_Import_Batch__c = batch.Id
        );
        insert person;
        person = [SELECT Id, AccountId FROM Contact WHERE Id = :person.Id];
        update new Account(Id = person.AccountId, Created_By_Import_Batch__c = batch.Id);
        return person;
    }

    private static Account importedOrganization(Import_Batch__c batch) {
        Account organization = new Account(
            Name = 'Rose City Rotary',
            RecordTypeId = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .getRecordTypeInfosByDeveloperName()
                .get('Organization')
                .getRecordTypeId(),
            Created_By_Import_Batch__c = batch.Id
        );
        insert organization;
        return organization;
    }

    /** Starts the undo and runs its job, then the delete passes once more over what is left. */
    private static void undo(Import_Batch__c batch) {
        Integer total = ImportUndoService.preview(batch.Id).total;
        Test.startTest();
        ImportUndoService.start(batch.Id, total);
        Test.stopTest();
        runDeletePasses(batch, total, Datetime.now());
    }

    /**
     * The same, with the moment the undo started given, so a test can tell what the undo did
     * apart from what the test itself did a moment before.
     */
    private static void undo(Import_Batch__c batch, Datetime undoStartedAt) {
        Integer total = ImportUndoService.preview(batch.Id).total;
        // Latched only: a job still queued when the test method ends runs then, and would
        // repeat these passes with its own start, so it is aborted. The passes below are the
        // only ones that run, each with this start.
        System.abortJob(ImportUndoService.start(batch.Id, total));
        runDeletePasses(batch, total, undoStartedAt, true);
    }

    /** More records than any test here imports, so a pass given this is one chunk. */
    private static final Integer MAX_ONE_CHUNK = 10000;

    private static void runDeletePasses(
        Import_Batch__c batch,
        Integer total,
        Datetime undoStartedAt
    ) {
        runDeletePasses(batch, total, undoStartedAt, false);
    }

    /**
     * Runs every delete pass in this one test transaction. `accountsPassAlone` gives the last
     * pass its own governor limits, as the platform does for every chunk: its checks keep
     * what they cannot afford to ask about, so a budget the earlier passes spent here would
     * keep records the job itself deletes. Only for a caller that has not used Test.startTest.
     *
     * In that mode the earlier passes are each handed their records as one chunk. A chunk's
     * checks cost about the same whatever its size, and the platform gives every chunk its own
     * limits, so two chunks sharing this one transaction would spend a budget the job never
     * shares. An org with many relationships on Contact (Nonprofit Cloud: about 18 queries a
     * chunk) otherwise leaves the second chunk unchecked and kept, which the job would not do.
     */
    private static void runDeletePasses(
        Import_Batch__c batch,
        Integer total,
        Datetime undoStartedAt,
        Boolean accountsPassAlone
    ) {
        List<String> passes = ImportUndoBatch.passes();
        passes.remove(passes.indexOf(ImportUndoBatch.PASS_RESTORE));
        for (String pass : passes) {
            ImportUndoBatch job = new ImportUndoBatch(
                batch.Id,
                total,
                pass,
                0,
                false,
                undoStartedAt
            );
            Boolean alone = accountsPassAlone && pass == ImportUndoBatch.PASS_ACCOUNTS;
            if (alone) {
                Test.startTest();
            }
            // Otherwise as the platform does: one chunk at a time, 100 at most.
            Integer chunkSize = accountsPassAlone && !alone ? MAX_ONE_CHUNK : 100;
            Database.QueryLocatorIterator records = job.start(null).iterator();
            List<SObject> scope = new List<SObject>();
            while (records.hasNext()) {
                scope.add(records.next());
                if (scope.size() == chunkSize) {
                    job.execute(null, scope);
                    scope = new List<SObject>();
                }
            }
            if (!scope.isEmpty()) {
                job.execute(null, scope);
            }
            if (pass == ImportUndoBatch.PASS_ACCOUNTS) {
                job.finish(null);
            }
            if (alone) {
                Test.stopTest();
            }
        }
    }

    private static String undoJournal(Import_Batch__c batch) {
        String text = '';
        for (Import_Journal__c page : [
            SELECT Entries_JSON__c
            FROM Import_Journal__c
            WHERE Import_Batch__c = :batch.Id AND Phase__c = :ImportJournalService.PHASE_UNDO
        ]) {
            text += page.Entries_JSON__c;
        }
        return text;
    }

    private static Boolean exists(Id recordId) {
        return [SELECT COUNT() FROM Account WHERE Id = :recordId] +
            [SELECT COUNT() FROM Contact WHERE Id = :recordId] > 0;
    }

    @IsTest
    static void thePreviewCountsWhatCarriesTheTagByKind() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            importedPerson(batch, 'Ramirez');
            importedPerson(batch, 'Lee');
            importedOrganization(batch);
            insert new Contact(FirstName = 'Sam', LastName = 'Okafor');

            ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);

            Assert.isTrue(view.allowed, 'A committed import inside its window can be undone.');
            Assert.areEqual(2, view.people, 'Two people carry the tag.');
            Assert.areEqual(2, view.households, 'And the two households made for them.');
            Assert.areEqual(1, view.organizations, 'And one organization.');
            Assert.areEqual(5, view.total, 'A person the import did not create is not counted.');
        }
    }

    @IsTest
    static void undoDeletesWhatTheImportCreatedAndNothingElse() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            Account organization = importedOrganization(batch);
            Contact existing = new Contact(FirstName = 'Sam', LastName = 'Okafor');
            insert existing;

            undo(batch);

            Assert.isFalse(exists(imported.Id), 'The person the import created is gone.');
            Assert.isFalse(exists(imported.AccountId), 'So is the household made for them.');
            Assert.isFalse(exists(organization.Id), 'And the organization.');
            Assert.isTrue(exists(existing.Id), 'A person the import did not create is untouched.');
            Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'Every guard could run.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Contact WHERE Id = :imported.Id AND IsDeleted = TRUE ALL ROWS],
                'Deleted to the recycle bin, not destroyed (R-IB8).'
            );
            Import_Batch__c after = [
                SELECT Status__c, Run_Log__c
                FROM Import_Batch__c
                WHERE Id = :batch.Id
            ];
            Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                after.Status__c,
                'The batch is Undone.'
            );
            Assert.isTrue(
                after.Run_Log__c.contains(UserInfo.getName()),
                'And the run log says who undid it (R-IB9).'
            );
        }
    }

    @IsTest
    static void aRecordThatGainedSomethingSinceIsKept() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            Account organization = importedOrganization(batch);
            Affiliation__c later = new Affiliation__c(
                Contact__c = imported.Id,
                Organization__c = organization.Id,
                Status__c = 'Current'
            );
            insert later;
            Test.setCreatedDate(later.Id, Datetime.now().addHours(1));

            undo(batch);

            Assert.isTrue(
                exists(imported.Id),
                'Somebody recorded an affiliation for this person since.'
            );
            Assert.isTrue(exists(organization.Id), 'And for this organization.');
            Assert.isTrue(exists(imported.AccountId), 'The kept person keeps their household.');
            Assert.isTrue(
                ImportJournalService.entryCount(batch.Id, ImportJournalService.PHASE_UNDO) >= 3,
                'Each kept record is journaled with its reason (R-IJ3).'
            );
        }
    }

    @IsTest
    static void anOrganizationAnotherAccountNamedSinceIsKept() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Account organization = importedOrganization(batch);
            Account later = new Account(Name = 'Okafor', Primary_Affiliation__c = organization.Id);
            insert later;
            Test.setCreatedDate(later.Id, Datetime.now().addHours(1));

            undo(batch);

            Assert.isTrue(exists(organization.Id), 'An account created since names it.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c],
                'A reference from the same object is checked without a semi-join SOQL refuses.'
            );
        }
    }

    @IsTest
    static void aRecordSomebodyEditedSinceIsKept() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            batch.Started_At__c = Datetime.now().addHours(-3);
            batch.Completed_At__c = Datetime.now().addHours(-2);
            update batch;
            Contact imported = importedPerson(batch, 'Ramirez');

            // The person was saved just now, long after the commit settled, by somebody who is
            // not the undo: an edit since.
            undo(batch, Datetime.now().addHours(1));

            Assert.isTrue(
                exists(imported.Id),
                'An edit since the import keeps the record (R-IB9).'
            );
            Assert.isTrue(
                undoJournal(batch).contains(Label.Core_Import_UndoKeptEdited),
                'And the journal says why.'
            );
        }
    }

    @IsTest
    static void anActivityRecordedSinceKeepsThePerson() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            // An activity is a standard object Core never names: it is found through the
            // person's child relationships, the same way a gift is (R-IB9).
            Task call = new Task(Subject = 'Thank-you call', WhoId = imported.Id);
            insert call;
            Test.setCreatedDate(call.Id, Datetime.now().addHours(1));

            undo(batch);

            Assert.isTrue(exists(imported.Id), 'An activity logged since keeps the person.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'ImportUndoBatch.guardQuery'],
                'Every relationship could be checked.'
            );
        }
    }

    @IsTest
    static void anUndoThePlatformStoppedEndsUndoFailedAndCanRunAgain() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            Integer total = ImportUndoService.preview(batch.Id).total;
            // Latched and queued, never run: where a chunk the platform stopped leaves things,
            // with its delete rolled back and the records still there.
            ImportUndoService.start(batch.Id, total);
            ImportUndoBatch.jobErrorsForTest = 1;
            // The last pass finishing: the state execute would have set is lost with the chunk,
            // and only the job's error count says what happened.
            new ImportUndoBatch(batch.Id, total, ImportUndoBatch.PASS_ACCOUNTS, 0, false)
                .finish(null);

            Assert.areEqual(
                ImportBatchService.STATUS_UNDO_FAILED,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
                'A chunk the platform stopped is a failure, not a success (R-IB8).'
            );
            ImportUndoService.Preview again = ImportUndoService.preview(batch.Id);
            Assert.isTrue(again.allowed, 'And the undo can be run again.');

            ImportUndoBatch.jobErrorsForTest = null;
            runDeletePasses(batch, again.total, Datetime.now());

            Assert.isFalse(exists(imported.Id), 'The second run finishes the work.');
            Assert.areEqual(
                ImportBatchService.STATUS_UNDONE,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
                'And ends Undone.'
            );
            Assert.isTrue(total > 0, 'There was something to undo.');
        }
    }

    @IsTest
    static void anUndoWhoseJobWasAbortedCanRunAgain() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            importedPerson(batch, 'Ramirez');
            batch.Status__c = ImportBatchService.STATUS_UNDOING;
            update batch;

            ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);

            Assert.isTrue(
                view.allowed,
                'Undoing with no undo job queued or running is an aborted undo, not a running one.'
            );
            Assert.areEqual(
                ImportBatchService.STATUS_UNDO_FAILED,
                ImportUndoService.effectiveStatus(
                    [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id]
                ),
                'And it is shown as Undo failed (R-IB8).'
            );
        }
    }

    @IsTest
    static void aHouseholdSomebodyElseHasJoinedIsKept() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            Contact joined = new Contact(
                FirstName = 'Luis',
                LastName = 'Ramirez',
                AccountId = imported.AccountId
            );
            insert joined;

            undo(batch);

            Assert.isFalse(exists(imported.Id), 'The imported person is gone.');
            Assert.isTrue(
                exists(imported.AccountId),
                'Their household is kept for the person in it.'
            );
            Assert.isTrue(exists(joined.Id), 'Who is untouched.');
        }
    }

    /** Answers that every household in `credited` still has records credited to it. */
    private class CreditedHouseholds implements HouseholdDependentsExtension {
        private final Set<Id> credited;
        private final Boolean fail;
        CreditedHouseholds(Set<Id> credited, Boolean fail) {
            this.credited = credited;
            this.fail = fail;
        }
        public Set<Id> householdsWithDependents(Set<Id> householdIds) {
            if (fail) {
                throw new System.QueryException('The extension could not answer');
            }
            Set<Id> answer = new Set<Id>(householdIds);
            answer.retainAll(credited);
            return answer;
        }
    }

    private static void installDependents(Set<Id> credited, Boolean fail) {
        HouseholdDependentsExtensions.noneForTest = true;
        HouseholdDependentsExtensions.overrides.put(
            'GivingHouseholdDependentsExtension',
            new CreditedHouseholds(credited, fail)
        );
    }

    /** People the import created, one household each, both tagged, in two bulk writes. */
    private static List<Contact> importedPeople(Import_Batch__c batch, Integer howMany) {
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            people.add(
                new Contact(
                    FirstName = 'Ana',
                    LastName = 'Bulk' + i,
                    Created_By_Import_Batch__c = batch.Id
                )
            );
        }
        insert people;
        people = [SELECT Id, AccountId FROM Contact WHERE Id IN :people];
        List<Account> households = new List<Account>();
        for (Contact person : people) {
            households.add(
                new Account(Id = person.AccountId, Created_By_Import_Batch__c = batch.Id)
            );
        }
        update households;
        return people;
    }

    @IsTest
    static void aHouseholdAModuleStillCreditsRecordsToIsKept() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact credited = importedPerson(batch, 'Ramirez');
            Contact other = importedPerson(batch, 'Lee');
            // A gift made before the commit and edited onto this household since: nothing was
            // created after the import, so only the module can say it is still credited.
            installDependents(new Set<Id>{ credited.AccountId }, false);

            undo(batch, Datetime.now());

            Assert.isFalse(exists(credited.Id), 'The person goes.');
            Assert.isTrue(
                exists(credited.AccountId),
                'The household its gifts are credited to stays.'
            );
            Assert.isFalse(exists(other.AccountId), 'A household nothing is credited to goes.');
            Assert.isTrue(
                undoJournal(batch).contains(Label.Core_Import_UndoKeptCredited),
                'The reason is journaled (R-IB9).'
            );
        }
    }

    @IsTest
    static void aModuleThatCannotSayWhatIsCreditedKeepsEveryHousehold() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            installDependents(new Set<Id>(), true);

            undo(batch, Datetime.now());

            Assert.isTrue(exists(imported.AccountId), 'Not answering is not answering no.');
        }
    }

    @IsTest
    static void twoHundredHouseholdsKeepOnlyTheOnesModuleRecordsAreCreditedTo() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            List<Contact> people = importedPeople(batch, 200);
            Set<Id> credited = new Set<Id>();
            for (Integer i = 0; i < 150; i++) {
                credited.add(people[i].AccountId);
            }
            installDependents(credited, false);

            undo(batch, Datetime.now());

            Assert.areEqual(
                150,
                [SELECT COUNT() FROM Account WHERE Id IN :credited],
                'Each credited household is kept.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Contact WHERE Created_By_Import_Batch__c = :batch.Id],
                'Every imported person goes.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Created_By_Import_Batch__c = :batch.Id AND Id NOT IN :credited
                ],
                'The other fifty households go.'
            );
        }
    }

    @IsTest
    static void undoIsRefusedForADryRunAClosedWindowOrAChangedCount() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            importedPerson(batch, 'Ramirez');

            batch.Is_Dry_Run__c = true;
            update batch;
            Assert.areEqual(
                Label.Core_Import_UndoErrorDryRun,
                ImportUndoService.preview(batch.Id).reason,
                'A dry run wrote nothing to undo.'
            );

            batch.Is_Dry_Run__c = false;
            batch.Undo_Deadline__c = Datetime.now().addDays(-1);
            update batch;
            Assert.isFalse(ImportUndoService.preview(batch.Id).allowed, 'The window has closed.');

            batch.Undo_Deadline__c = Datetime.now().addDays(1);
            update batch;
            try {
                ImportUndoService.start(batch.Id, 99);
                Assert.fail('A count that is not the count shown is refused.');
            } catch (ImportException expected) {
                Assert.isTrue(expected.getMessage().contains('99'), 'Naming the number confirmed.');
            }
            Assert.areEqual(
                ImportBatchService.STATUS_COMPLETE,
                [SELECT Status__c FROM Import_Batch__c WHERE Id = :batch.Id].Status__c,
                'And nothing was started.'
            );
        }
    }

    @IsTest
    static void undoRunsOnce() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            importedPerson(batch, 'Ramirez');
            Test.startTest();
            ImportUndoService.start(batch.Id, 2);
            try {
                ImportUndoService.start(batch.Id, 2);
                Assert.fail('A second undo of the same import is refused, not queued.');
            } catch (ImportException expected) {
                Assert.areEqual(
                    Label.Core_Import_UndoErrorAlreadyUndone,
                    expected.getMessage(),
                    'Saying why.'
                );
            }
            Test.stopTest();
        }
    }

    @IsTest
    static void anImportThatCreatedNothingHasNothingToUndo() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);
            Assert.isFalse(view.allowed, 'There is nothing to undo.');
            Assert.areEqual(
                Label.Core_Import_UndoErrorNothingToUndo,
                view.reason,
                'And it says so.'
            );
        }
    }

    private static Map<String, Object> cityWas(Contact person, String before, String after) {
        return ImportJournalService.updated(
            'Contact',
            person.Id,
            2,
            new Map<String, Object>{ 'MailingCity' => before },
            new Map<String, Object>{ 'MailingCity' => after }
        );
    }

    /**
     * A value the import wrote is put back where nobody has changed it since, left alone where
     * somebody has, and passed over silently where it is already back, which is what makes a
     * second run of a failed undo safe (R-IB8, R-IB9).
     */
    @IsTest
    static void undoPutsBackOnlyTheValuesNobodyHasChangedSince() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact untouched = new Contact(LastName = 'Ramirez', MailingCity = 'Portland');
            Contact corrected = new Contact(LastName = 'Lee', MailingCity = 'Eugene');
            Contact alreadyBack = new Contact(LastName = 'Okafor', MailingCity = 'Salem');
            insert new List<Contact>{ untouched, corrected, alreadyBack };
            ImportJournalService.write(
                batch.Id,
                ImportJournalService.PHASE_COMMIT,
                new List<Map<String, Object>>{
                    cityWas(untouched, 'Salem', 'Portland'),
                    cityWas(corrected, 'Salem', 'Portland'),
                    cityWas(alreadyBack, 'Salem', 'Portland')
                }
            );
            Assert.areEqual(
                3,
                ImportUndoService.preview(batch.Id).updates,
                'The preview counts them.'
            );

            Test.startTest();
            ImportUndoService.start(batch.Id, 0);
            Test.stopTest();

            Map<Id, Contact> after = new Map<Id, Contact>([SELECT MailingCity FROM Contact]);
            Assert.areEqual('Salem', after.get(untouched.Id).MailingCity, 'Put back.');
            Assert.areEqual('Eugene', after.get(corrected.Id).MailingCity, 'A correction is kept.');
            Assert.areEqual('Salem', after.get(alreadyBack.Id).MailingCity, 'Left as it is.');
            List<Map<String, Object>> journal = ImportJournalService.entries(
                ImportJournalService.pages(batch.Id, ImportJournalService.PHASE_UNDO, 10)[0]
            );
            Assert.areEqual(1, journal.size(), 'Only the correction is journaled as not put back.');
            Assert.areEqual(
                ImportJournalService.ACTION_NOT_RESTORED,
                journal[0].get('action'),
                'With its reason.'
            );
        }
    }

    /** Values come back as the field's own type, and compare as values, not as text. */
    @IsTest
    static void journaledValuesCompareAndComeBackTyped() {
        System.runAs(TestUsers.admin()) {
            Date birthday = Date.newInstance(1970, 5, 17);
            Assert.isTrue(
                ImportUndoBatch.same(birthday, '1970-05-17'),
                'A date by its written form.'
            );
            Assert.isTrue(ImportUndoBatch.same(5, 5.0), 'A number as a number.');
            Assert.isFalse(ImportUndoBatch.same('Salem', 'salem'), 'Text exactly.');
            Assert.isTrue(ImportUndoBatch.same(null, null), 'Nothing is nothing.');
            Assert.areEqual(
                birthday,
                ImportUndoBatch.typed('1970-05-17', Contact.Birthdate.getDescribe()),
                'A date comes back a date.'
            );
            Assert.areEqual(
                false,
                ImportUndoBatch.typed(false, Account.Custom_Name__c.getDescribe()),
                'And a checkbox a checkbox.'
            );
        }
    }

    // -------------------------------------------------------------------------------------
    // An installed module's part in an undo (R-IB9, R-IR6)
    // -------------------------------------------------------------------------------------

    /**
     * Stands in for a module's entity processor. It says it tags the given objects, and keeps
     * the records named in `keep` with their reason. Core has no module object of its own to
     * lend it, so the tests hand it Contact, which Core then deletes in the module's pass.
     */
    private class StubProcessor implements ImportEntityProcessor {
        List<Schema.SObjectType> tagged = new List<Schema.SObjectType>();
        Map<Id, String> keep = new Map<Id, String>();
        Boolean throwOnKeep = false;
        Set<Schema.SObjectType> askedAbout = new Set<Schema.SObjectType>();

        public List<ImportMapping.Target> targets() {
            return new List<ImportMapping.Target>();
        }

        public ImportEntityResult resolve(
            Import_Batch__c batch,
            Import_Template__c template,
            List<Import_Row__c> rows,
            Map<Id, Map<String, Map<String, String>>> entitiesByRowId,
            Boolean dryRun
        ) {
            return new ImportEntityResult();
        }

        public List<Schema.SObjectType> taggedObjects() {
            return tagged;
        }

        public Map<Id, String> reasonsToKeep(
            Id batchId,
            Schema.SObjectType type,
            Set<Id> recordIds
        ) {
            askedAbout.add(type);
            if (throwOnKeep) {
                throw new IllegalArgumentException('stub cannot tell');
            }
            return keep;
        }
    }

    private static StubProcessor installStub(List<Schema.SObjectType> tagged) {
        StubProcessor stub = new StubProcessor();
        stub.tagged = tagged;
        ImportEntityProcessors.processorOverride = stub;
        return stub;
    }

    @IsTest
    static void aModulesOwnRecordsAreCountedAndGoFirst() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            importedPerson(batch, 'Ramirez');
            installStub(new List<Schema.SObjectType>{ Contact.SObjectType });

            ImportUndoService.Preview view = ImportUndoService.preview(batch.Id);

            Assert.areEqual(1, view.others.size(), 'One module object is counted.');
            Assert.areEqual('Contact', view.others[0].objectName, 'Named by its API name.');
            Assert.areEqual(1, view.others[0].count, 'With what carries the tag.');
            Assert.areEqual(
                Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabelPlural(),
                view.others[0].label,
                'And labelled as the org labels it.'
            );
            Assert.areEqual(3, view.total, 'The module records are in the total confirmed.');
            Assert.areEqual(
                new List<String>{
                    ImportUndoBatch.PASS_RESTORE,
                    ImportUndoBatch.PASS_CREATED,
                    ImportUndoBatch.PASS_TAGGED_PREFIX + 'Contact',
                    ImportUndoBatch.PASS_CONTACTS,
                    ImportUndoBatch.PASS_PERSON_ACCOUNTS,
                    ImportUndoBatch.PASS_ACCOUNTS
                },
                ImportUndoBatch.passes(),
                'The module pass runs after the restore and before the people.'
            );
        }
    }

    @IsTest
    static void aModuleObjectWithoutTheTagIsNeverQueried() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            installStub(new List<Schema.SObjectType>{ Import_Template__c.SObjectType });

            Assert.isTrue(
                ImportEntityProcessors.taggedTypes().isEmpty(),
                'An object that does not name the import is left out.'
            );
            Assert.areEqual(
                0,
                ImportUndoService.preview(batch.Id).others.size(),
                'And not counted.'
            );
        }
    }

    @IsTest
    static void theModulePassDeletesWhatTheModuleTagged() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            StubProcessor stub = installStub(new List<Schema.SObjectType>{ Contact.SObjectType });

            undo(batch, Datetime.now());

            Assert.isFalse(exists(imported.Id), 'The tagged record went in the module pass.');
            Assert.isFalse(exists(imported.AccountId), 'And its household after it.');
            Assert.isTrue(
                stub.askedAbout.contains(Contact.SObjectType),
                'The module was asked before its tagged records went.'
            );
        }
    }

    @IsTest
    static void aRecordTheModuleKeepsIsKeptWithItsReason() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact kept = importedPerson(batch, 'Ramirez');
            Contact gone = importedPerson(batch, 'Lee');
            StubProcessor stub = installStub(new List<Schema.SObjectType>());
            stub.keep.put(kept.Id, 'A gift with a receipt still names this person.');

            undo(batch, Datetime.now());

            Assert.isTrue(exists(kept.Id), 'The module said this one stays.');
            Assert.isTrue(exists(kept.AccountId), 'So does the household they are still on.');
            Assert.isFalse(exists(gone.Id), 'The other went.');
            Assert.isTrue(
                undoJournal(batch).contains('A gift with a receipt still names this person.'),
                'The reason is journaled (R-IB9).'
            );
        }
    }

    @IsTest
    static void aModuleThatCannotAnswerKeepsEverything() {
        System.runAs(TestUsers.admin()) {
            Import_Batch__c batch = committedBatch();
            Contact imported = importedPerson(batch, 'Ramirez');
            StubProcessor stub = installStub(new List<Schema.SObjectType>());
            stub.throwOnKeep = true;

            undo(batch, Datetime.now());

            Assert.isTrue(exists(imported.Id), 'Not knowing is not knowing nothing depends on it.');
            Assert.isTrue(
                undoJournal(batch).contains(Label.Core_Import_UndoKeptNotChecked),
                'And the journal says it could not be checked.'
            );
        }
    }

    /**
     * The restore loop asks for an object's field map once per journal entry; it is described
     * once and kept, whatever case the journal wrote the object name in.
     */
    @IsTest
    static void theFieldMapIsDescribedOncePerObject() {
        System.runAs(TestUsers.admin()) {
            Map<String, Schema.SObjectField> first = ImportUndoBatch.fieldMap('Contact');

            Assert.isTrue(first.containsKey('lastname'), 'The map is the object\'s own fields.');
            Assert.isTrue(
                first === ImportUndoBatch.fieldMap('contact'),
                'The second entry for the same object reuses the first describe.'
            );
        }
    }
}
