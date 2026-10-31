/**
 * Ask cadence reminders (canonical model Section 25S, G-29): who is owed a reminder, that each
 * date reminds once, that the setting switches the pass off, and that a donor whose reminder
 * could not be made is counted and tried again.
 */
@IsTest(
    testFor='ApexClass:AskReminderBatch, ApexClass:AskReminderSchedulable, ApexClass:AskReminderSelector, ApexClass:AskReminderService, ApexClass:AskReminderWriter'
)
private class AskReminderTest {
    private static final String OWNER_LAST_NAME = 'AskOwner';

    @TestSetup
    static void createUsers() {
        TestUsers.adminWith('Giving_Admin');
        // Created here, in its own transaction, because a user is setup data and each test then
        // inserts donors owned by it without a mixed DML error.
        TestUsers.onRunningProfileWith(
            OWNER_LAST_NAME,
            new List<String>{ TestUsers.CORE_ADMIN, 'Giving_Staff' }
        );
    }

    private static User owner() {
        return [SELECT Id, IsActive FROM User WHERE LastName = :OWNER_LAST_NAME LIMIT 1];
    }

    private static Contact donorContact(Id ownerId, Date nextAsk) {
        Contact person = new Contact(
            FirstName = 'Dana',
            LastName = 'Donor' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            OwnerId = ownerId,
            Next_Ask_Date__c = nextAsk
        );
        insert person;
        return person;
    }

    private static Account donorAccount(Id ownerId, Date nextAsk) {
        Account organization = new Account(
            Name = 'Foundation ' + String.valueOf(Math.abs(Crypto.getRandomInteger())),
            OwnerId = ownerId,
            Next_Ask_Date__c = nextAsk
        );
        insert organization;
        return organization;
    }

    /** Both passes of one run, because the batch only chains to its second pass outside tests. */
    private static void runBothPasses() {
        Test.startTest();
        Database.executeBatch(new AskReminderBatch(), AskReminderBatch.CHUNK_SIZE);
        Database.executeBatch(
            new AskReminderBatch(AskReminderBatch.CONTACTS, System.today(), 0, 0),
            AskReminderBatch.CHUNK_SIZE
        );
        Test.stopTest();
    }

    /**
     * A later run in the same test. A test method may start the platform's batch only once, so a
     * second night is the same decision and write the batch makes, applied to the donors as they
     * stand now.
     */
    private static void runAgain() {
        List<SObject> donors = new List<SObject>();
        donors.addAll(
            [
                SELECT Id, Name, AccountId, OwnerId, Next_Ask_Date__c, Ask_Reminder_For_Date__c
                FROM Contact
                WHERE Next_Ask_Date__c != NULL
            ]
        );
        donors.addAll(
            [
                SELECT Id, Name, OwnerId, Next_Ask_Date__c, Ask_Reminder_For_Date__c
                FROM Account
                WHERE Next_Ask_Date__c != NULL
            ]
        );
        AskReminderService.remindChunk(donors, System.today());
    }

    private static void setRemindersEnabled(Boolean enabled) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Ask_Reminders_Enabled__c = enabled;
        upsert settings;
        SettingsService.clearCaches();
    }

    private static List<Task> remindersFor(Id donorId) {
        return [
            SELECT Id, Subject, OwnerId, ActivityDate, Status, WhoId, WhatId
            FROM Task
            WHERE WhoId = :donorId OR WhatId = :donorId
        ];
    }

    @IsTest
    static void aDonorWhoseDateHasArrivedGetsATaskForTheirOwner() {
        User owner = owner();
        Date today = System.today();
        Contact person;
        Account organization;
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            person = donorContact(owner.Id, today);
            organization = donorAccount(owner.Id, today.addDays(-3));
            runBothPasses();

            List<Task> forPerson = remindersFor(person.Id);
            Assert.areEqual(1, forPerson.size(), 'A person whose date is today is reminded.');
            Assert.areEqual(owner.Id, forPerson[0].OwnerId, 'The reminder is the owner\'s task.');
            Assert.areEqual(today, forPerson[0].ActivityDate, 'It is due on the ask date.');
            Assert.areEqual(person.Id, forPerson[0].WhoId, 'It hangs off the person.');
            Assert.isTrue(forPerson[0].Subject.contains('Donor'), 'It names the donor.');

            List<Task> forOrganization = remindersFor(organization.Id);
            Assert.areEqual(
                1,
                forOrganization.size(),
                'An organization three days overdue is reminded.'
            );
            Assert.areEqual(
                today.addDays(-3),
                forOrganization[0].ActivityDate,
                'The task is dated the ask date, not the night it was made.'
            );

            Assert.areEqual(
                today,
                [SELECT Ask_Reminder_For_Date__c FROM Contact WHERE Id = :person.Id]
                .Ask_Reminder_For_Date__c,
                'The donor is stamped with the date it was reminded for.'
            );
            Assert.areNotEqual(
                null,
                Giving_Settings__c.getOrgDefaults().Ask_Reminders_Last_Run__c,
                'The run records that it finished, which the Nightly Jobs page shows.'
            );
        }
    }

    @IsTest
    static void runningTwiceCreatesNoSecondReminderForTheSameDate() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donorContact(owner.Id, System.today());
            runBothPasses();
            runAgain();
            runAgain();

            Assert.areEqual(
                1,
                remindersFor(person.Id).size(),
                'A date reminds once however many times the job runs.'
            );
        }
    }

    @IsTest
    static void aTaskTheOwnerDeletedIsNotMadeAgain() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donorContact(owner.Id, System.today());
            runBothPasses();
            delete remindersFor(person.Id);
            runAgain();

            Assert.areEqual(
                0,
                remindersFor(person.Id).size(),
                'The stamp, not the task list, is the record of the reminder, so a deleted task stays deleted.'
            );
        }
    }

    @IsTest
    static void aNewNextAskDateIsANewAskAndGetsANewReminder() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact person = donorContact(owner.Id, System.today().addDays(-2));
            runBothPasses();
            person.Next_Ask_Date__c = System.today().addDays(-1);
            update person;
            runAgain();

            Assert.areEqual(
                2,
                remindersFor(person.Id).size(),
                'Moving the date to another arrived date asks again.'
            );
        }
    }

    @IsTest
    static void futureAndStaleDatesAreLeftAlone() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact future = donorContact(owner.Id, System.today().addDays(1));
            Contact stale = donorContact(
                owner.Id,
                System.today().addDays(-AskReminderService.CATCH_UP_DAYS - 1)
            );
            Contact edge = donorContact(
                owner.Id,
                System.today().addDays(-AskReminderService.CATCH_UP_DAYS)
            );
            Contact noDate = donorContact(owner.Id, null);
            runBothPasses();

            Assert.areEqual(0, remindersFor(future.Id).size(), 'Tomorrow has not arrived.');
            Assert.areEqual(
                0,
                remindersFor(stale.Id).size(),
                'A date older than the catch up window is not turned into a task.'
            );
            Assert.areEqual(
                1,
                remindersFor(edge.Id).size(),
                'The last day of the window is still caught up.'
            );
            Assert.areEqual(0, remindersFor(noDate.Id).size(), 'No date, no reminder.');
        }
    }

    @IsTest
    static void switchingTheSettingOffStopsTheTasks() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isTrue(
                AskReminderService.isEnabled(),
                'The shipped default is on, so an org that never opens the console is reminded.'
            );
            setRemindersEnabled(false);
            Assert.isFalse(AskReminderService.isEnabled(), 'The setting turns it off.');
            Contact person = donorContact(owner.Id, System.today());

            Test.startTest();
            new AskReminderSchedulable().execute(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                remindersFor(person.Id).size(),
                'Off means the nightly job creates nothing.'
            );
        }
    }

    @IsTest
    static void aSecondStartWhileAPassIsWaitingStartsNothing() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account organization = donorAccount(owner.Id, System.today());
            Test.startTest();
            new AskReminderSchedulable().execute(null);
            Assert.isTrue(AskReminderService.isRunning(), 'The first start queues a pass.');
            // Run now pressed again while the first pass waits.
            new AskReminderSchedulable().execute(null);
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE JobType = 'BatchApex' AND ApexClass.Name = 'AskReminderBatch'
                ],
                'Two passes at once could both remind a donor before either stamps it.'
            );
            Test.stopTest();

            Assert.areEqual(1, remindersFor(organization.Id).size());
        }
    }

    @IsTest
    static void aRunQueuedBeforeTheSettingWentOffMakesNothing() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account organization = donorAccount(owner.Id, System.today());
            Test.startTest();
            Database.executeBatch(new AskReminderBatch(), AskReminderBatch.CHUNK_SIZE);
            setRemindersEnabled(false);
            Test.stopTest();

            Assert.areEqual(
                0,
                remindersFor(organization.Id).size(),
                'R-AC2: the switch is read again when the queued run reaches its chunks.'
            );
        }
    }

    @IsTest
    static void aFailedStartIsLoggedNotThrown() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AskReminderSchedulable.failStartForTest = true;
            Test.startTest();
            new AskReminderSchedulable().execute(null);
            Test.stopTest();

            Assert.isFalse(AskReminderService.isRunning(), 'A failed start queues no pass.');
        }
    }

    @IsTest
    static void theSchedulableStartsTheBatchWhenOn() {
        User owner = owner();
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Account organization = donorAccount(owner.Id, System.today());
            Test.startTest();
            new AskReminderSchedulable().execute(null);
            Test.stopTest();

            Assert.areEqual(
                1,
                remindersFor(organization.Id).size(),
                'On, the nightly job reminds the accounts pass of the run.'
            );
        }
    }

    @IsTest
    static void anOwnerWhoCannotTakeATaskIsCountedAndTriedAgain() {
        User owner = owner();
        Contact person;
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            person = donorContact(owner.Id, System.today());
        }
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            owner.IsActive = false;
            update owner;
        }
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Contact queried = [
                SELECT Id, Name, AccountId, OwnerId, Next_Ask_Date__c, Ask_Reminder_For_Date__c
                FROM Contact
                WHERE Id = :person.Id
            ];
            Test.startTest();
            AskReminderService.Outcome outcome = AskReminderService.remindChunk(
                new List<SObject>{ queried },
                System.today()
            );
            Test.stopTest();

            Assert.areEqual(0, outcome.created, 'No task was made for an inactive owner.');
            Assert.areEqual(1, outcome.failed, 'The donor is counted as not reminded.');
            Assert.areEqual(
                null,
                [SELECT Ask_Reminder_For_Date__c FROM Contact WHERE Id = :person.Id]
                .Ask_Reminder_For_Date__c,
                'An unreminded donor is left unstamped so the next night tries again.'
            );
            Assert.isTrue(
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'Ask reminders'] > 0,
                'The reason is in the Error Log.'
            );
        }
    }

    @IsTest
    static void theDecisionAppliesTheWindowAndTheStamp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Date today = System.today();
            Contact arrived = new Contact(Next_Ask_Date__c = today);
            Contact stamped = new Contact(
                Next_Ask_Date__c = today,
                Ask_Reminder_For_Date__c = today
            );
            Contact restamped = new Contact(
                Next_Ask_Date__c = today,
                Ask_Reminder_For_Date__c = today.addDays(-5)
            );
            Assert.isTrue(AskReminderService.isDue(arrived, today));
            Assert.isFalse(
                AskReminderService.isDue(stamped, today),
                'Already reminded for this date.'
            );
            Assert.isTrue(
                AskReminderService.isDue(restamped, today),
                'Reminded for an older date.'
            );
            Assert.isFalse(AskReminderService.isDue(new Contact(), today));
            Assert.areEqual(
                0,
                AskReminderService.remindersFor(null, today, new List<SObject>()).size()
            );
        }
    }

    @IsTest
    static void aWriteWithMismatchedListsDoesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(0, AskReminderWriter.save(new List<Task>(), new List<SObject>()));
            Assert.areEqual(
                0,
                AskReminderWriter.save(new List<Task>{ new Task() }, new List<SObject>())
            );
        }
    }

    @IsTest
    static void staffEditTheDatesButNotTheReminderStamp() {
        User staff = TestUsers.standardUserWith('AskStaff', new List<String>{ 'Giving_Staff' });
        System.runAs(staff) {
            Assert.isTrue(
                Contact.Next_Ask_Date__c.getDescribe().isUpdateable(),
                'Staff set the next ask.'
            );
            Assert.isTrue(Account.Last_Touch_Date__c.getDescribe().isUpdateable());
            Assert.isFalse(
                Contact.Ask_Reminder_For_Date__c.getDescribe().isUpdateable(),
                'The stamp belongs to the job.'
            );
            Assert.isTrue(Contact.Ask_Reminder_For_Date__c.getDescribe().isAccessible());
        }
    }

    @IsTest
    static void theJobIsOneOfTheModulesNightlyJobs() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.clearOrgGivingJobs();
            Assert.isFalse(GivingScheduler.statuses().get(GivingScheduler.ASK_JOB_NAME).scheduled);
            GivingScheduler.scheduleJobNamed(GivingScheduler.ASK_JOB_NAME);
            Assert.isTrue(GivingScheduler.isJobScheduled(GivingScheduler.ASK_JOB_NAME));
        }
    }
}
