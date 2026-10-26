/**
 * That Completed Date follows Status however the status was changed: by the package, or by a person
 * editing the plan.
 */
@IsTest(testFor='ApexClass:StewardshipPlanTriggerHandler')
private class StewardshipPlanTriggerHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static Stewardship_Plan__c runningPlan() {
        Stewardship_Plan_Template__c template = new Stewardship_Plan_Template__c(
            Name = 'Hand closed plan',
            Plan_Key__c = 'hand_closed_plan',
            Active__c = true,
            Trigger_Event__c = StewardshipService.EVENT_GIFT_RECEIVED
        );
        insert template;
        Contact person = new Contact(LastName = 'Okafor');
        insert person;
        Stewardship_Plan__c plan = new Stewardship_Plan__c(
            Contact__c = person.Id,
            Stewardship_Plan_Template__c = template.Id,
            Status__c = StewardshipService.STATUS_RUNNING,
            Started_Date__c = Date.today()
        );
        insert plan;
        return plan;
    }

    private static Stewardship_Plan__c reload(Id planId) {
        return [SELECT Status__c, Completed_Date__c FROM Stewardship_Plan__c WHERE Id = :planId];
    }

    @IsTest
    static void settingAPlanCompleteByHandFillsTheDateAndReopeningClearsIt() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan__c plan = runningPlan();

            Test.startTest();
            plan.Status__c = StewardshipService.STATUS_COMPLETE;
            update plan;
            Stewardship_Plan__c completed = reload(plan.Id);
            plan.Status__c = StewardshipService.STATUS_RUNNING;
            update plan;
            Test.stopTest();

            Assert.areEqual(
                Date.today(),
                completed.Completed_Date__c,
                'A plan completed by hand gets today as its completed date.'
            );
            Assert.isNull(
                reload(plan.Id).Completed_Date__c,
                'A reopened plan has no completed date.'
            );
        }
    }

    @IsTest
    static void aDateTheUserTypedIsKeptAndACancelledPlanGetsOneToo() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan__c plan = runningPlan();
            Date typed = Date.today().addDays(-3);

            Test.startTest();
            plan.Status__c = StewardshipService.STATUS_CANCELLED;
            plan.Completed_Date__c = typed;
            update plan;
            Stewardship_Plan__c cancelled = reload(plan.Id);
            Stewardship_Plan__c second = runningPlan();
            second.Status__c = StewardshipService.STATUS_CANCELLED;
            update second;
            Test.stopTest();

            Assert.areEqual(typed, cancelled.Completed_Date__c, 'A typed date stands.');
            Assert.areEqual(
                Date.today(),
                reload(second.Id).Completed_Date__c,
                'Cancelling fills the date when there is none.'
            );
        }
    }
}
