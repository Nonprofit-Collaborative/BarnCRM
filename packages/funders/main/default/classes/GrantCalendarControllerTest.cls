/**
 * The Grant Calendar's server side (F-08): the application deadlines, open requirements and
 * expected payments between two dates, Mine, the six-week cap, refusing a backwards range, and
 * a reader seeing the same dates.
 */
@IsTest(testFor='ApexClass:GrantCalendarController, ApexClass:GrantDeadlineSelector')
private class GrantCalendarControllerTest {
    @TestSetup
    static void createTestUsers() {
        TestUsers.adminWith(GrantTestData.ADMIN);
        TestUsers.standardUserWith(
            'Gcalreader',
            new List<String>{ 'BarnCRM_Read_Only', 'Funders_Read_Only' }
        );
    }

    private static final Date FIRST = Date.newInstance(2027, 3, 1);

    /**
     * Inside March 2027: a prospect due on the 10th, a requirement due on the 15th, an expected
     * payment on the 20th. Outside or not shown: an applied grant due on the 12th (already
     * submitted), a received payment on the 21st, a prospect due in May, a submitted requirement.
     */
    private static void dates() {
        Account funder = GrantTestData.funder('Lakeside Foundation');
        Grant__c prospect = GrantTestData.grant('Soon', funder.Id, GrantService.STAGE_PROSPECT);
        prospect.Application_Deadline__c = FIRST.addDays(9);
        Grant__c applied = GrantTestData.grant('Applied', funder.Id, GrantService.STAGE_APPLIED);
        applied.Application_Deadline__c = FIRST.addDays(11);
        Grant__c later = GrantTestData.grant('Later', funder.Id, GrantService.STAGE_PROSPECT);
        later.Application_Deadline__c = FIRST.addMonths(2);
        Grant__c award = GrantTestData.grant('Award', funder.Id, GrantService.STAGE_AWARDED);
        insert new List<Grant__c>{ prospect, applied, later, award };

        Grant_Requirement__c due = GrantTestData.requirement('Report', award.Id, FIRST.addDays(14));
        Grant_Requirement__c done = GrantTestData.requirement('Done', award.Id, FIRST.addDays(14));
        done.Status__c = 'Submitted';
        insert new List<Grant_Requirement__c>{ due, done };
        insert new List<Grant_Payment__c>{
            new Grant_Payment__c(
                Grant__c = award.Id,
                Due_Date__c = FIRST.addDays(19),
                Amount__c = 5000,
                Status__c = GrantPaymentService.STATUS_EXPECTED
            ),
            new Grant_Payment__c(
                Grant__c = award.Id,
                Due_Date__c = FIRST.addDays(20),
                Amount__c = 5000,
                Status__c = GrantPaymentService.STATUS_RECEIVED
            )
        };
    }

    private static List<String> kinds(GrantCalendarController.Calendar calendar) {
        List<String> out = new List<String>();
        for (GrantPipelineController.Card row : calendar.rows) {
            out.add(row.kind + ' ' + row.deadline.day());
        }
        out.sort();
        return out;
    }

    @IsTest
    static void theMonthShowsItsDeadlinesRequirementsAndExpectedPayments() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            dates();

            Test.startTest();
            GrantCalendarController.Calendar calendar = GrantCalendarController.getCalendar(
                FIRST,
                FIRST.addDays(30),
                false
            );
            Test.stopTest();

            Assert.areEqual(
                new List<String>{ 'application 10', 'payment 20', 'requirement 15' },
                kinds(calendar),
                'Only open dates in the range'
            );
            Assert.areEqual(Date.today(), calendar.today, 'Today for overdue marks');
            Assert.areEqual(
                Schema.SObjectType.Grant_Payment__c.getLabel(),
                calendar.paymentLabel,
                'Payments are named by the object label'
            );
            Assert.areEqual(
                Schema.SObjectType.Grant_Requirement__c.getLabel(),
                calendar.requirementLabel,
                'The legend names requirements by the object label'
            );
            for (GrantPipelineController.Card row : calendar.rows) {
                if (row.kind == GrantCalendarController.KIND_PAYMENT) {
                    Assert.areEqual(5000, row.amount, 'The amount expected');
                    Assert.areEqual('Award', row.grantName, 'And its grant');
                }
            }
        }
    }

    @IsTest
    static void mineIsTheNamesOwnAndTheRangeIsCapped() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            dates();
        }
        User reader = [SELECT Id FROM User WHERE LastName = 'Gcalreader' WITH SYSTEM_MODE LIMIT 1];
        GrantCalendarController.Calendar mine;
        GrantCalendarController.Calendar everyone;
        GrantCalendarController.Calendar capped;

        Test.startTest();
        System.runAs(reader) {
            mine = GrantCalendarController.getCalendar(FIRST, FIRST.addDays(30), true);
            everyone = GrantCalendarController.getCalendar(FIRST, FIRST.addDays(30), false);
            capped = GrantCalendarController.getCalendar(FIRST, FIRST.addDays(100), false);
        }
        Test.stopTest();

        Assert.isTrue(mine.rows.isEmpty(), 'The reader owns nothing');
        Assert.areEqual(3, everyone.rows.size(), 'A reader sees the same dates');
        Assert.areEqual(3, capped.rows.size(), 'Six weeks at most: May is not read');
    }

    @IsTest
    static void aBackwardsRangeIsRefused() {
        System.runAs(TestUsers.adminWith(GrantTestData.ADMIN)) {
            String refusal;
            Test.startTest();
            try {
                GrantCalendarController.getCalendar(FIRST, FIRST.addDays(-1), false);
            } catch (AuraHandledException e) {
                refusal = e.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                BarnHelp.text('Funders', 'Funders_Calendar_LoadFailed'),
                refusal,
                'Refused with a message'
            );
        }
    }
}
