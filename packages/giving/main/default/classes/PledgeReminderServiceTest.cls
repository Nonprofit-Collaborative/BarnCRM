/**
 * Pledge reminders (G-30): which step an installment gets, the switch, the claim, the log, the
 * letter file and the nightly job.
 *
 * Nothing here sends mail. The sender is the acknowledgment tests' stand-in, which records what
 * it was handed and answers however the test says.
 */
@IsTest(testFor='ApexClass:PledgeReminderService, ApexClass:PledgeReminderBatch')
private class PledgeReminderServiceTest {
    private static final Id FAKE_DONOR = Id.valueOf('003000000000001AAA');

    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    private static List<Pledge_Reminder_Step__c> ladder() {
        return new List<Pledge_Reminder_Step__c>{
            PledgeReminderTestData.buildStep('Week ahead', -7, 'Email', 'X'),
            PledgeReminderTestData.buildStep('Week late', 7, 'Email', 'X'),
            PledgeReminderTestData.buildStep('Two weeks late', 14, 'Letter', null)
        };
    }

    // ------------------------------------------------------------------------ choosing a step

    @IsTest
    static void aBeforeDueStepFiresThatManyDaysAhead() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        List<PledgeReminderService.Planned> planned = PledgeReminderService.plan(
            new List<Installment__c>{
                PledgeReminderTestData.inMemory(today.addDays(7), FAKE_DONOR),
                PledgeReminderTestData.inMemory(today.addDays(8), FAKE_DONOR)
            },
            ladder(),
            today,
            counts
        );
        Assert.areEqual(1, planned.size(), 'Only the installment due in exactly a week is due.');
        Assert.areEqual('Week ahead', planned[0].step.Name);
        Assert.areEqual('Email', planned[0].channel);
    }

    @IsTest
    static void onlyTheLatestRecentStepIsMade() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        // 15 days overdue: the 7 day step is 8 days old, the 14 day step is 1 day old.
        List<PledgeReminderService.Planned> planned = PledgeReminderService.plan(
            new List<Installment__c>{
                PledgeReminderTestData.inMemory(today.addDays(-15), FAKE_DONOR)
            },
            ladder(),
            today,
            counts
        );
        Assert.areEqual(1, planned.size(), 'One reminder per installment per run (R-PR1).');
        Assert.areEqual('Two weeks late', planned[0].step.Name);
        Assert.areEqual('Letter', planned[0].channel);
    }

    @IsTest
    static void aStepWhoseDayIsLongPastDoesNotFire() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        // 200 days overdue: every step's day passed more than 14 days ago (R-PR2).
        List<PledgeReminderService.Planned> planned = PledgeReminderService.plan(
            new List<Installment__c>{
                PledgeReminderTestData.inMemory(today.addDays(-200), FAKE_DONOR)
            },
            ladder(),
            today,
            counts
        );
        Assert.isTrue(planned.isEmpty(), 'Turning the feature on must not reach back for months.');
    }

    @IsTest
    static void anInactiveStepNeverFires() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        List<Pledge_Reminder_Step__c> steps = ladder();
        steps[0].Active__c = false;
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        Assert.isTrue(
            PledgeReminderService.plan(
                    new List<Installment__c>{
                        PledgeReminderTestData.inMemory(today.addDays(7), FAKE_DONOR)
                    },
                    steps,
                    today,
                    counts
                )
                .isEmpty()
        );
    }

    @IsTest
    static void anEmailWithNobodyToSendItToIsCountedNotPlanned() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        List<PledgeReminderService.Planned> planned = PledgeReminderService.plan(
            new List<Installment__c>{ PledgeReminderTestData.inMemory(today.addDays(7), null) },
            ladder(),
            today,
            counts
        );
        Assert.isTrue(planned.isEmpty());
        Assert.areEqual(1, counts.withoutRecipient, 'R-PR5: counted, not guessed at.');
    }

    @IsTest
    static void theWindowCoversEveryStepsRecentDays() {
        // runs-as: deploying user (pure date arithmetic over in-memory steps, no DML or SOQL)
        Date today = Date.today();
        List<Pledge_Reminder_Step__c> steps = ladder();
        Assert.areEqual(
            today.addDays(-(14 + PledgeReminderService.CATCH_UP_DAYS)),
            PledgeReminderService.windowFrom(steps, today),
            'The latest step, 14 days, plus the catch up days.'
        );
        Assert.areEqual(
            today.addDays(7),
            PledgeReminderService.windowTo(steps, today),
            'The earliest step, a week ahead.'
        );
        Assert.isTrue(
            PledgeReminderService.windowFrom(new List<Pledge_Reminder_Step__c>(), today) >
            PledgeReminderService.windowTo(new List<Pledge_Reminder_Step__c>(), today),
            'No steps is an empty window, so the run selects nothing.'
        );
    }

    // ------------------------------------------------------------------------ the switch

    @IsTest
    static void nothingSendsWhileTheSettingIsOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentService.sendPermission = true;
            insert PledgeReminderTestData.buildStep(
                'Overdue',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;

            Assert.isFalse(PledgeReminderService.isEnabled(), 'Off by default.');
            PledgeReminderService.Counts counts = PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(0, counts.emails + counts.letters + counts.errors);
            Assert.isTrue(sender.received.isEmpty());
            Assert.areEqual(0, [SELECT COUNT() FROM Pledge_Reminder__c]);
            try {
                PledgeReminderService.startRun();
                Assert.fail('A run cannot start while reminders are off.');
            } catch (PledgeReminderService.PledgeReminderException refused) {
                Assert.areEqual(Label.Giving_PledgeReminders_Disabled, refused.getMessage());
            }
        }
    }

    @IsTest
    static void aRunNeedsThePermissionToSend() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            AcknowledgmentService.sendPermission = false;
            try {
                PledgeReminderService.startRun();
                Assert.fail('Sending needs the Send Acknowledgments permission.');
            } catch (PledgeReminderService.PledgeReminderException refused) {
                Assert.areEqual(Label.Giving_PledgeReminders_NoPermission, refused.getMessage());
            }
        }
    }

    // ------------------------------------------------------------------------ the send

    @IsTest
    static void anOverdueInstallmentIsRemindedOnceAndLogged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            Pledge_Reminder_Step__c step = PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            insert step;
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;
            List<Installment__c> due = new List<Installment__c>{
                PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
            };

            PledgeReminderService.Counts first = PledgeReminderService.process(due);
            PledgeReminderService.Counts second = PledgeReminderService.process(due);

            Assert.areEqual(1, first.emails);
            Assert.areEqual(
                0,
                second.emails,
                'The same step does not remind the same installment twice (R-PR4).'
            );
            Assert.areEqual(1, sender.received.size());
            Assert.areEqual(
                due[0].Id,
                sender.received[0].getWhatId(),
                'The template merges the installment.'
            );
            Assert.areEqual(donor.Id, sender.received[0].getTargetObjectId());

            Pledge_Reminder__c logged = [
                SELECT
                    Status__c,
                    Channel__c,
                    Step__c,
                    Step_Name__c,
                    Template__c,
                    Recipient_Email__c,
                    Days_Overdue__c,
                    Sent_On__c,
                    Reminder_Key__c,
                    Commitment__c
                FROM Pledge_Reminder__c
            ];
            Assert.areEqual('Sent', logged.Status__c);
            Assert.areEqual('Email', logged.Channel__c);
            Assert.areEqual(step.Id, logged.Step__c);
            Assert.areEqual('Week late', logged.Step_Name__c);
            Assert.areEqual(PledgeReminderTestData.TEMPLATE, logged.Template__c);
            Assert.areEqual('ada@example.org', logged.Recipient_Email__c);
            Assert.areEqual(7, logged.Days_Overdue__c);
            Assert.isNotNull(logged.Sent_On__c);
            Assert.areEqual(pledge.Id, logged.Commitment__c);
            Assert.areEqual(
                PledgeReminderService.keyFor(due[0].Id, step.Id),
                logged.Reminder_Key__c,
                'A sent reminder keeps its key, which is what stops a second one.'
            );
        }
    }

    @IsTest
    static void aFailedSendIsLoggedAndRetriedByTheNextRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            sender.failAt = new Set<Integer>{ 0 };
            PledgeReminderService.senderOverride = sender;
            List<Installment__c> due = new List<Installment__c>{
                PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
            };

            PledgeReminderService.Counts failed = PledgeReminderService.process(due);
            Assert.areEqual(1, failed.errors);
            Pledge_Reminder__c row = [
                SELECT Status__c, Failure_Reason__c, Reminder_Key__c
                FROM Pledge_Reminder__c
            ];
            Assert.areEqual('Failed', row.Status__c);
            Assert.areEqual('The address bounced.', row.Failure_Reason__c);
            Assert.isNull(row.Reminder_Key__c, 'The key is released so the next run retries.');

            sender.failAt = new Set<Integer>();
            PledgeReminderService.Counts retried = PledgeReminderService.process(due);
            Assert.areEqual(1, retried.emails);
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Pledge_Reminder__c],
                'Two rows: the failure stays as history, and the retry is its own row.'
            );
        }
    }

    @IsTest
    static void aStepWhoseTemplateIsGoneFailsItsRowAndSaysSo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep('Week late', 7, 'Email', 'No_Such_Template');
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;

            PledgeReminderService.Counts counts = PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(1, counts.errors);
            Assert.isTrue(sender.received.isEmpty());
            Pledge_Reminder__c row = [SELECT Status__c, Failure_Reason__c FROM Pledge_Reminder__c];
            Assert.areEqual('Failed', row.Status__c);
            Assert.isTrue(row.Failure_Reason__c.contains('No_Such_Template'));
        }
    }

    /** A sender whose whole call the platform refuses. */
    private class ThrowingSender implements AcknowledgmentSender {
        public List<AcknowledgmentSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
            throw new PledgeReminderService.PledgeReminderException('The mail server said no.');
        }
    }

    @IsTest
    static void aSendTheWholeCallRefusesFailsEveryRowAndReleasesItsKey() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            PledgeReminderService.senderOverride = new ThrowingSender();

            PledgeReminderService.Counts counts = PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(1, counts.errors);
            Pledge_Reminder__c row = [
                SELECT Status__c, Failure_Reason__c, Reminder_Key__c
                FROM Pledge_Reminder__c
            ];
            Assert.areEqual('Failed', row.Status__c, 'Never left Queued.');
            Assert.areEqual('The mail server said no.', row.Failure_Reason__c);
            Assert.isNull(row.Reminder_Key__c, 'The key is released so the next run retries.');
        }
    }

    @IsTest
    static void aSettleThatFailsStillLeavesNoRowQueued() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            sender.failAt = new Set<Integer>{ 0 };
            // Longer than the field holds, so the first, all-or-none settle throws.
            sender.failureReason = 'x'.repeat(300);
            PledgeReminderService.senderOverride = sender;

            PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Pledge_Reminder__c row = [
                SELECT Status__c, Failure_Reason__c, Reminder_Key__c
                FROM Pledge_Reminder__c
            ];
            Assert.areEqual('Failed', row.Status__c, 'Settled again on its own, not left Queued.');
            Assert.areEqual(Label.Giving_PledgeReminders_SendFailedUnknown, row.Failure_Reason__c);
            Assert.isNull(row.Reminder_Key__c);
        }
    }

    @IsTest
    static void aBeforeDueStepStopsOnTheDueDate() {
        // runs-as: deploying user (planning logic over in-memory records; its one query is the opt-out read, in system mode)
        Date today = Date.today();
        List<Pledge_Reminder_Step__c> steps = new List<Pledge_Reminder_Step__c>{
            PledgeReminderTestData.buildStep('Week ahead', -7, 'Email', 'X')
        };
        PledgeReminderService.Counts counts = new PledgeReminderService.Counts();
        List<PledgeReminderService.Planned> planned = PledgeReminderService.plan(
            new List<Installment__c>{
                // Step day four days ago, still before the due date: fires.
                PledgeReminderTestData.inMemory(today.addDays(3), FAKE_DONOR),
                // Due today: a heads-up no longer applies.
                PledgeReminderTestData.inMemory(today, FAKE_DONOR),
                // Due three days ago, step day inside the catch up days: still not sent.
                PledgeReminderTestData.inMemory(today.addDays(-3), FAKE_DONOR)
            },
            steps,
            today,
            counts
        );
        Assert.areEqual(1, planned.size(), 'R-PR2: a before-due step stops on the due date.');
        Assert.areEqual(today.addDays(3), planned[0].installment.Due_Date__c);
    }

    @IsTest
    static void aDonorWithNoEmailAddressGetsALetterInstead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', null);
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;

            PledgeReminderService.Counts counts = PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(0, counts.emails);
            Assert.areEqual(
                1,
                counts.letters,
                'R-PR5: no address goes by letter, like an opt-out.'
            );
            Assert.isTrue(sender.received.isEmpty());
            Assert.areEqual('Letter', [SELECT Channel__c FROM Pledge_Reminder__c].Channel__c);
        }
    }

    @IsTest
    static void aDonorWhoOptedOutOfEmailGetsALetterInstead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            donor.HasOptedOutOfEmail = true;
            update donor;
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;

            PledgeReminderService.Counts counts = PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(0, counts.emails);
            Assert.areEqual(1, counts.letters, 'R-PR5, the same rule as R-AK13.');
            Assert.isTrue(sender.received.isEmpty());
            Pledge_Reminder__c row = [SELECT Channel__c, Status__c FROM Pledge_Reminder__c];
            Assert.areEqual('Letter', row.Channel__c);
            Assert.areEqual('Queued', row.Status__c);
        }
    }

    // ------------------------------------------------------------------------ letters

    @IsTest
    static void lettersAreFiledThenMarkedSentByAPerson() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep('Final letter', 7, 'Letter', null);
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            donor.MailingStreet = '1 Analytical Way';
            donor.MailingCity = 'London';
            update donor;
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );
            Assert.areEqual(
                'Queued',
                [SELECT Status__c FROM Pledge_Reminder__c].Status__c,
                'A letter is queued, not sent, until a person says it went (R-PR6).'
            );

            Integer filed = PledgeReminderService.produceLetters();
            Assert.areEqual(1, filed);
            Pledge_Reminder__c row = [
                SELECT Status__c, Letter_File_Document_Id__c
                FROM Pledge_Reminder__c
            ];
            Assert.isNotNull(row.Letter_File_Document_Id__c);
            Assert.areEqual('Queued', row.Status__c, 'Still waiting for a person.');
            Assert.areEqual(0, PledgeReminderService.produceLetters(), 'A letter is filed once.');

            String csv = [
                    SELECT VersionData
                    FROM ContentVersion
                    WHERE ContentDocumentId = :row.Letter_File_Document_Id__c
                ]
                .VersionData.toString();
            Assert.isTrue(csv.startsWith('Pledge,Installment,Due Date,Amount Due'));
            Assert.isTrue(csv.contains('Byron'));
            Assert.isTrue(csv.contains('1 Analytical Way'));
            Assert.isTrue(csv.contains('Final letter'));

            Assert.areEqual(1, PledgeReminderService.markLettersSent());
            Pledge_Reminder__c sent = [SELECT Status__c, Sent_On__c FROM Pledge_Reminder__c];
            Assert.areEqual('Sent', sent.Status__c);
            Assert.isNotNull(sent.Sent_On__c);
        }
    }

    @IsTest
    static void aLetterRowCannotLeakAFormulaIntoTheFile() {
        // runs-as: deploying user (pure CSV text over an in-memory record, no DML or SOQL)
        Pledge_Reminder__c letter = new Pledge_Reminder__c(
            Step_Name__c = '=HYPERLINK("http://example.org")',
            Days_Overdue__c = 3
        );
        String csv = PledgeReminderService.csvFor(new List<Pledge_Reminder__c>{ letter });
        Assert.isFalse(csv.contains('\n=HYPERLINK'), 'Formula starts are neutralised.');
        Assert.isTrue(csv.contains('\'=HYPERLINK'));
    }

    // ------------------------------------------------------------------------ the run

    @IsTest
    static void thePreviewCountsWhatTheRunWouldDo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert new List<Pledge_Reminder_Step__c>{
                PledgeReminderTestData.buildStep(
                    'Week late',
                    7,
                    'Email',
                    PledgeReminderTestData.TEMPLATE
                )
            };
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            PledgeReminderTestData.insertPledge(donor.Id, 7);

            PledgeReminderService.Counts counts = PledgeReminderService.preview();

            Assert.areEqual(1, counts.emails);
            Assert.areEqual(0, counts.letters);
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Pledge_Reminder__c],
                'A preview writes nothing.'
            );
        }
    }

    @IsTest
    static void theBatchRunsTheWholeWindowAndRecordsTheLastRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep(
                'Week late',
                7,
                'Email',
                PledgeReminderTestData.TEMPLATE
            );
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            PledgeReminderTestData.insertPledge(donor.Id, 7);
            AcknowledgmentTestData.RecordingSender sender = new AcknowledgmentTestData.RecordingSender();
            PledgeReminderService.senderOverride = sender;

            Test.startTest();
            PledgeReminderService.startRun();
            Test.stopTest();

            Assert.areEqual(1, sender.received.size());
            Assert.areEqual(1, [SELECT COUNT() FROM Pledge_Reminder__c WHERE Status__c = 'Sent']);
            Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
            Assert.isNotNull(settings.Pledge_Reminders_Last_Run__c);
            Assert.isTrue(
                settings.Pledge_Reminders_Last_Run_Summary__c.contains('1 reminder emails sent')
            );
        }
    }

    @IsTest
    static void theNightlyScheduleStartsStopsAndDoesNothingWhileOff() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.isFalse(PledgeReminderScheduler.isScheduled());
            Test.startTest();
            PledgeReminderScheduler.start();
            Assert.isTrue(PledgeReminderScheduler.isScheduled());
            Assert.isNotNull(PledgeReminderScheduler.nextRunAt());
            Assert.areEqual(
                PledgeReminderScheduler.start(),
                PledgeReminderScheduler.start(),
                'Starting twice is one job.'
            );
            // Switched off: executing the job queues nothing and raises nothing.
            new PledgeReminderScheduler().execute(null);
            PledgeReminderScheduler.stop();
            Test.stopTest();
            Assert.isFalse(PledgeReminderScheduler.isScheduled());
            Assert.areEqual(0, [SELECT COUNT() FROM Pledge_Reminder__c]);
        }
    }
}
