/**
 * The Pledge Reminders page's Apex: what it shows, and the refusals it reports (G-30).
 */
@IsTest(testFor='ApexClass:PledgeReminderController')
private class PledgeReminderControllerTest {
    @TestSetup
    static void setUp() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.insertDefaultFund();
        }
    }

    @IsTest
    static void theDefaultPageSaysOffAndListsStepsWithTheirTemplates() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            insert new List<Pledge_Reminder_Step__c>{
                PledgeReminderTestData.buildStep(
                    'Week late',
                    7,
                    'Email',
                    PledgeReminderTestData.TEMPLATE
                ),
                PledgeReminderTestData.buildStep('Lost', 14, 'Email', 'No_Such_Template'),
                PledgeReminderTestData.buildStep('Letter', 30, 'Letter', null)
            };

            PledgeReminderController.PageView view = PledgeReminderController.getPage();

            Assert.isFalse(view.enabled, 'Reminders are off by default.');
            Assert.areEqual(3, view.steps.size());
            Assert.isTrue(view.steps[0].templateFound);
            Assert.isNotNull(view.steps[0].templateLabel, 'The shipped template is shown by name.');
            Assert.isFalse(view.steps[1].templateFound);
            Assert.isTrue(view.steps[2].templateFound, 'A letter step needs no template.');
            Assert.isFalse(view.scheduled);
            Assert.isTrue(view.reminders.isEmpty());
        }
    }

    @IsTest
    static void sendingWhileOffIsRefusedInWordsAPersonCanRead() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            AcknowledgmentService.sendPermission = true;
            try {
                PledgeReminderController.sendNow();
                Assert.fail('A send while off must be refused.');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Giving_PledgeReminders_Disabled, refused.getMessage());
            }
        }
    }

    @IsTest
    static void theScheduleToggleStartsAndStopsTheNightlyRun() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Assert.isTrue(PledgeReminderController.setSchedule(true).scheduled);
            Assert.isFalse(PledgeReminderController.setSchedule(false).scheduled);
            Test.stopTest();
        }
    }

    @IsTest
    static void theLetterButtonsReportTheQueueAndTheFile() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            PledgeReminderTestData.enable();
            insert PledgeReminderTestData.buildStep('Final letter', 7, 'Letter', null);
            Contact donor = AcknowledgmentTestData.insertDonor('Ada', 'Byron', 'ada@example.org');
            Commitment__c pledge = PledgeReminderTestData.insertPledge(donor.Id, 7);
            PledgeReminderService.process(
                new List<Installment__c>{
                    PledgeReminderTestData.installmentDue(pledge.Id, Date.today().addDays(-7))
                }
            );

            Assert.areEqual(1, PledgeReminderController.getPage().lettersWaiting);
            PledgeReminderController.PageView filed = PledgeReminderController.produceLetters();
            Assert.areEqual(0, filed.lettersWaiting);
            Assert.areEqual(1, filed.lettersAwaitingConfirmation);
            Assert.isNotNull(filed.lettersFileId);
            PledgeReminderController.PageView marked = PledgeReminderController.markLettersSent();
            Assert.areEqual(0, marked.lettersAwaitingConfirmation);
            Assert.areEqual('Sent', marked.reminders[0].status);
        }
    }
}
