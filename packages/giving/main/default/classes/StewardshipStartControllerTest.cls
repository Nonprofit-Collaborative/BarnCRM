/**
 * The Start Stewardship Plan action: it lists the plans that are on, starts one on a person or on
 * a household or organization, and tells a reader why nothing starts (testing guide finding C6).
 */
@IsTest(testFor='ApexClass:StewardshipStartController')
private class StewardshipStartControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static Stewardship_Plan_Template__c planWithOneStep(String name, Boolean active) {
        Stewardship_Plan_Template__c template = new Stewardship_Plan_Template__c(
            Name = name,
            Plan_Key__c = name.toLowerCase().replace(' ', '_'),
            Active__c = active,
            Trigger_Event__c = StewardshipService.EVENT_MANUAL,
            Description__c = 'After a meeting'
        );
        insert template;
        insert new Stewardship_Plan_Step__c(
            Stewardship_Plan_Template__c = template.Id,
            Order__c = 1,
            Subject__c = 'Call to say thank you',
            Days_After_Start__c = 1,
            Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
            Priority__c = 'Normal'
        );
        return template;
    }

    @IsTest
    static void listsThePlansThatAreOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c activePlan = planWithOneStep('Major gift thanks', true);
            planWithOneStep('Retired plan', false);

            Test.startTest();
            StewardshipStartController.StartModel model = StewardshipStartController.getStartable();
            Test.stopTest();

            Assert.isTrue(model.canStart, 'An administrator may start a plan.');
            Assert.areEqual(1, model.plans.size(), 'Only a plan that is on is offered.');
            Assert.areEqual(activePlan.Id, model.plans[0].value, 'The plan that is on.');
            Assert.areEqual('After a meeting', model.plans[0].description, 'With its description.');
        }
    }

    @IsTest
    static void startsAPlanOnAPersonAndOnAnOrganization() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = planWithOneStep('Major gift thanks', true);
            Contact person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
            insert person;
            Account organization = GivingTestDataFactory.insertOrganization('Summit Foundation');

            Test.startTest();
            Id personPlan = StewardshipStartController.startPlan(major.Id, person.Id);
            Id organizationPlan = StewardshipStartController.startPlan(major.Id, organization.Id);
            Test.stopTest();

            Stewardship_Plan__c onPerson = [
                SELECT Contact__c, Account__c, Status__c
                FROM Stewardship_Plan__c
                WHERE Id = :personPlan
            ];
            Assert.areEqual(person.Id, onPerson.Contact__c, 'A person is the plan Contact.');
            Assert.isNull(onPerson.Account__c, 'And not its Account.');
            Assert.areEqual(StewardshipService.STATUS_RUNNING, onPerson.Status__c, 'Running.');
            Assert.areEqual(
                organization.Id,
                [SELECT Account__c FROM Stewardship_Plan__c WHERE Id = :organizationPlan]
                .Account__c,
                'An organization is the plan Account.'
            );
        }
    }

    /** The start runs in system mode, so a donor the person cannot see is refused first (G-L3). */
    @IsTest
    static void aDonorThePersonCannotSeeStartsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = planWithOneStep('Major gift thanks', true);
            Contact gone = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
            insert gone;
            delete gone;
            String refusal;

            Test.startTest();
            try {
                StewardshipStartController.startPlan(major.Id, gone.Id);
            } catch (AuraHandledException refused) {
                refusal = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Giving_Stewardship_ErrorDonorNotVisible,
                refusal,
                'Says the donor cannot be seen.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c WHERE Contact__c = :gone.Id],
                'No plan was started.'
            );
        }
    }

    @IsTest
    static void aSecondStartOnTheSameDonorSaysWhy() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = planWithOneStep('Major gift thanks', true);
            Contact person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
            insert person;
            StewardshipStartController.startPlan(major.Id, person.Id);

            Test.startTest();
            String message;
            try {
                StewardshipStartController.startPlan(major.Id, person.Id);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(Label.Giving_Stewardship_ErrorAlreadyRunning, message, 'Told why.');
        }
    }

    @IsTest
    static void aReaderIsToldTheyCannotStartAPlan() {
        User reader = TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'BarnCRM_Read_Only', 'Giving_Read_Only' }
        );
        Stewardship_Plan_Template__c major;
        Contact person;
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            major = planWithOneStep('Major gift thanks', true);
            person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
            insert person;
        }

        StewardshipStartController.StartModel model;
        String message;
        Test.startTest();
        System.runAs(reader) {
            model = StewardshipStartController.getStartable();
            try {
                StewardshipStartController.startPlan(major.Id, person.Id);
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.isFalse(model.canStart, 'A reader is offered no Start.');
        Assert.areEqual(Label.Giving_Stewardship_StartNoPermission, message, 'Told why.');
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'Nothing started.');
        }
    }
}
