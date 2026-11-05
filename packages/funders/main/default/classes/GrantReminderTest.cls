/**
 * Grant requirement reminders (F-02, R-GQ3, R-GQ4, R-FS1): who is reminded, once per due date,
 * by task and email as the settings say, and the morning job that runs it.
 *
 * The platform's email call is replaced by a stub that records the messages, so the tests prove
 * what would be sent without depending on the org's email deliverability setting.
 */
@IsTest(
    testFor='ApexClass:GrantReminderService, ApexClass:GrantReminderSelector, ApexClass:GrantReminderBatch, ApexClass:GrantReminderScheduler, ApexClass:FundersNightlyJobProvider, ApexClass:FundersSettings'
)
private class GrantReminderTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(GrantTestData.ADMIN);
        TestUsers.standardUserWith(
            'Grstaff',
            new List<String>{ 'BarnCRM_Read_Only', 'Funders_Staff' }
        );
    }

    private static User staff() {
        return [SELECT Id FROM User WHERE LastName = 'Grstaff' WITH SYSTEM_MODE LIMIT 1];
    }

    private static void settings(Boolean tasks, Boolean emails, Integer leadDays) {
        OrgSettingsSystemWriter.save(
            Funders_Settings__c.SObjectType,
            new Map<Schema.SObjectField, Object>{
                Funders_Settings__c.Reminder_Tasks_Enabled__c => tasks,
                Funders_Settings__c.Reminder_Emails_Enabled__c => emails,
                Funders_Settings__c.Reminder_Lead_Days__c => leadDays
            }
        );
        SettingsService.clearCaches();
    }

    private static Grant__c awardedGrant() {
        Account funder = GrantTestData.funder('Lakeside Foundation');
        Grant__c grant = GrantTestData.grant('Literacy', funder.Id, GrantService.STAGE_AWARDED);
        insert grant;
        return grant;
    }

    /** What the morning run's chunk would be given. */
    private static List<Grant_Requirement__c> due(Date today) {
        List<Grant_Requirement__c> found = new List<Grant_Requirement__c>();
        Database.QueryLocatorIterator rows = GrantReminderSelector.dueLocator(
                GrantReminderService.oldestDue(today),
                GrantReminderService.windowEnd(today, FundersSettings.reminderLeadDays())
            )
            .iterator();
        while (rows.hasNext()) {
            found.add((Grant_Requirement__c) rows.next());
        }
        return found;
    }

    private static List<Task> tasks() {
        return [
            SELECT OwnerId, WhatId, ActivityDate, Subject, Status
            FROM Task
            WITH SYSTEM_MODE
            ORDER BY CreatedDate
        ];
    }

    private static Grant_Requirement__c reread(Id requirementId) {
        return [
            SELECT Reminder_Sent_For__c, Due_Date__c
            FROM Grant_Requirement__c
            WHERE Id = :requirementId
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void aRequirementComingDueGetsOneTaskAndOneEmailOnce() {
        Id staffId = staff().Id;
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            settings(true, true, 14);
            Date today = Date.today();
            RecordingEmailSender stub = new RecordingEmailSender();
            GrantReminderService.emailSender = stub;
            Grant__c grant = awardedGrant();
            Grant_Requirement__c report = GrantTestData.requirement(
                'Year 1 report',
                grant.Id,
                today.addDays(5)
            );
            report.Assigned_To__c = staffId;
            insert report;

            Test.startTest();
            Integer first = GrantReminderService.remind(due(today), today);
            Integer second = GrantReminderService.remind(due(today), today);
            Test.stopTest();

            Assert.areEqual(1, first, 'Reminded once');
            Assert.areEqual(0, second, 'Never twice for the same due date');
            List<Task> made = tasks();
            Assert.areEqual(1, made.size(), 'One task');
            Assert.areEqual(staffId, made[0].OwnerId, 'For the person assigned');
            Assert.areEqual(grant.Id, made[0].WhatId, 'On the grant');
            Assert.areEqual(today.addDays(5), made[0].ActivityDate, 'Due on the due date');
            Assert.areEqual(
                String.format(
                    Label.Funders_Reminder_TaskSubject,
                    new List<Object>{ 'Year 1 report', 'Literacy' }
                ),
                made[0].Subject,
                'Named for the requirement and grant'
            );
            Assert.areEqual(1, stub.received.size(), 'One email');
            Assert.areEqual(staffId, stub.received[0].getTargetObjectId(), 'To the same person');
            Assert.isFalse(stub.received[0].getSaveAsActivity(), 'The task is the activity');
            Assert.areEqual(
                today.addDays(5),
                reread(report.Id).Reminder_Sent_For__c,
                'Stamped with the due date'
            );
        }
    }

    @IsTest
    static void aMovedDueDateIsRemindedAgainAndTheWindowHolds() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Date today = Date.today();
            GrantReminderService.emailSender = new RecordingEmailSender();
            settings(true, false, 10);
            Grant__c grant = awardedGrant();
            Grant_Requirement__c moved = GrantTestData.requirement('Moved', grant.Id, today);
            moved.Reminder_Sent_For__c = today.addDays(-7);
            Grant_Requirement__c tooFar = GrantTestData.requirement(
                'Too far',
                grant.Id,
                today.addDays(11)
            );
            Grant_Requirement__c overdue = GrantTestData.requirement(
                'Overdue',
                grant.Id,
                today.addDays(-30)
            );
            Grant_Requirement__c tooOld = GrantTestData.requirement(
                'Too old',
                grant.Id,
                today.addDays(-31)
            );
            Grant_Requirement__c done = GrantTestData.requirement(
                'Done',
                grant.Id,
                today.addDays(2)
            );
            done.Status__c = GrantRequirementService.STATUS_SUBMITTED;
            insert new List<Grant_Requirement__c>{ moved, tooFar, overdue, tooOld, done };

            Test.startTest();
            Integer reminded = GrantReminderService.remind(due(today), today);
            Test.stopTest();

            Assert.areEqual(2, reminded, 'The moved date and the overdue one');
            Assert.areEqual(today, reread(moved.Id).Reminder_Sent_For__c, 'Restamped');
            Assert.isNull(reread(tooFar.Id).Reminder_Sent_For__c, 'Past the lead time');
            Assert.isNull(reread(tooOld.Id).Reminder_Sent_For__c, 'Over 30 days late');
            Assert.areEqual(2, tasks().size(), 'A task each');
            Assert.isFalse(
                GrantReminderService.isDue(done, today, 10),
                'A submitted requirement is never due'
            );
        }
    }

    @IsTest
    static void theGrantOwnerStandsInForAnInactiveOrMissingAssignee() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Id ownerId = UserInfo.getUserId();
            Id assignee = staff().Id;
            Grant_Requirement__c requirement = new Grant_Requirement__c(
                Assigned_To__c = assignee,
                Grant__r = new Grant__c(OwnerId = ownerId)
            );

            Test.startTest();
            Id whenActive = GrantReminderService.recipientFor(
                requirement,
                new Set<Id>{ assignee, ownerId }
            );
            Id whenInactive = GrantReminderService.recipientFor(
                requirement,
                new Set<Id>{ ownerId }
            );
            Id nobody = GrantReminderService.recipientFor(requirement, new Set<Id>());
            Test.stopTest();

            Assert.areEqual(assignee, whenActive, 'The assignee first');
            Assert.areEqual(ownerId, whenInactive, 'Then the grant owner');
            Assert.isNull(nobody, 'Nobody active: no reminder');
            Assert.isTrue(
                GrantReminderSelector.activeUsers(new Set<Id>{ ownerId }).contains(ownerId),
                'An active user is found'
            );
        }
    }

    @IsTest
    static void eachSettingTurnsItsHalfOffAndBothOffStopsTheRun() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Date today = Date.today();
            RecordingEmailSender stub = new RecordingEmailSender();
            GrantReminderService.emailSender = stub;
            Grant__c grant = awardedGrant();
            insert GrantTestData.requirement('Emailed only', grant.Id, today.addDays(1));

            Test.startTest();
            settings(false, true, 14);
            Integer emailedOnly = GrantReminderService.remind(due(today), today);
            insert GrantTestData.requirement('Task only', grant.Id, today.addDays(1));
            settings(true, false, 14);
            Integer taskOnly = GrantReminderService.remind(due(today), today);
            insert GrantTestData.requirement('Neither', grant.Id, today.addDays(1));
            settings(false, false, 14);
            Boolean active = GrantReminderService.isActive();
            Id started = GrantReminderBatch.startMorning();
            Integer neither = GrantReminderService.remind(due(today), today);
            Test.stopTest();

            Assert.areEqual(1, emailedOnly, 'Emails alone still remind and stamp');
            Assert.areEqual(1, taskOnly, 'Tasks alone remind and stamp');
            Assert.areEqual(1, stub.received.size(), 'One email, from the first run');
            Assert.areEqual(1, tasks().size(), 'One task, from the second run');
            Assert.isFalse(active, 'Both off: not active');
            Assert.isNull(started, 'No run starts');
            Assert.areEqual(0, neither, 'Nothing is reminded');
        }
    }

    @IsTest
    static void aFailedEmailIsLoggedAndNotRepeated() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            settings(true, true, 14);
            Date today = Date.today();
            RecordingEmailSender refusing = new RecordingEmailSender();
            refusing.refuseWith = 'Email is off in this org.';
            GrantReminderService.emailSender = refusing;
            Grant__c grant = awardedGrant();
            Grant_Requirement__c report = GrantTestData.requirement('Report', grant.Id, today);
            insert report;

            Test.startTest();
            Integer reminded = GrantReminderService.remind(due(today), today);
            Test.stopTest();

            Assert.areEqual(1, reminded, 'The task went in, so it counts as reminded');
            Assert.areEqual(today, reread(report.Id).Reminder_Sent_For__c, 'Stamped');
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'GrantReminderService'
                    WITH SYSTEM_MODE
                ],
                'The failed email is logged'
            );
        }
    }

    @IsTest
    static void settingsReadTheirShippedValuesAndRefuseOutOfRange() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            Test.startTest();
            Boolean tasksShipped = FundersSettings.reminderTasksEnabled();
            Boolean emailsShipped = FundersSettings.reminderEmailsEnabled();
            Integer leadShipped = FundersSettings.reminderLeadDays();
            settings(false, false, 91);
            Integer outOfRange = FundersSettings.reminderLeadDays();
            settings(true, true, 30);
            Integer saved = FundersSettings.reminderLeadDays();
            Test.stopTest();

            Assert.isTrue(tasksShipped, 'Tasks ship on');
            Assert.isFalse(emailsShipped, 'Emails ship off');
            Assert.areEqual(14, leadShipped, 'Fourteen days ships');
            Assert.areEqual(14, outOfRange, 'Out of range reads as the default');
            Assert.areEqual(30, saved, 'A saved value reads back');
        }
    }

    @IsTest
    static void theMorningJobIsSchedulableOnceAndRuns() {
        Id staffId = staff().Id;
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            GrantReminderScheduler.jobNameInUse = 'BarnCRM Grant Reminders test';
            GrantReminderService.emailSender = new RecordingEmailSender();
            Grant__c grant = awardedGrant();
            Grant_Requirement__c report = GrantTestData.requirement(
                'Report',
                grant.Id,
                Date.today().addDays(3)
            );
            report.Assigned_To__c = staffId;
            insert report;
            List<NightlyStep> steps = new FundersNightlyJobProvider().nightlySteps();

            Test.startTest();
            steps[0].run();
            Test.stopTest();

            Assert.areEqual(1, steps.size(), 'One step');
            Assert.areEqual(360, steps[0].minute, 'At six in the morning');
            Assert.isFalse(steps[0].hasSwitch(), 'No switch of its own');
            Assert.areEqual(
                Date.today().addDays(3),
                reread(report.Id).Reminder_Sent_For__c,
                'The batch reminded it'
            );
            Assert.isTrue(
                NightlyJobs.PROVIDER_CLASSES.contains('FundersNightlyJobProvider'),
                'Core lists the provider'
            );
        }
    }
}
