/**
 * What the Stewardship Plans page in the settings console can do, and the one thing it refuses.
 *
 * These tests have not been executed against an org: none was reachable from the environment they
 * were written in. They are written to the rules in canonical model Sections 25I to 25K.
 */
@IsTest(testFor='ApexClass:StewardshipPlanController')
private class StewardshipPlanControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static Stewardship_Plan_Template__c template(String name, String key, Boolean active) {
        Stewardship_Plan_Template__c created = new Stewardship_Plan_Template__c(
            Name = name,
            Plan_Key__c = key,
            Active__c = active,
            Trigger_Event__c = StewardshipService.EVENT_MANUAL
        );
        insert created;
        return created;
    }

    private static Stewardship_Plan_Step__c step(Id templateId, Integer order, String subject) {
        return new Stewardship_Plan_Step__c(
            Stewardship_Plan_Template__c = templateId,
            Order__c = order,
            Subject__c = subject,
            Days_After_Start__c = order,
            Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
            Priority__c = 'Normal'
        );
    }

    private static StewardshipPlanController.TemplateModel model(
        Id recordId,
        String name,
        String key
    ) {
        StewardshipPlanController.TemplateModel input = new StewardshipPlanController.TemplateModel();
        input.recordId = recordId;
        input.name = name;
        input.planKey = key;
        input.triggerEvent = StewardshipService.EVENT_MANUAL;
        input.active = false;
        return input;
    }

    private static StewardshipPlanController.StepModel stepModel(String subject) {
        StewardshipPlanController.StepModel input = new StewardshipPlanController.StepModel();
        input.subject = subject;
        input.daysAfterStart = 3;
        input.assignTo = StewardshipService.ASSIGN_RECORD_OWNER;
        input.priority = 'Normal';
        return input;
    }

    @IsTest
    static void thePageShowsEveryPlanItsStepsInOrderAndWhatIsRunning() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', true);
            insert new List<Stewardship_Plan_Step__c>{
                step(welcome.Id, 2, 'Send the packet'),
                step(welcome.Id, 1, 'Call to say thank you')
            };
            Contact person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
            insert person;
            insert new Stewardship_Plan__c(
                Stewardship_Plan_Template__c = welcome.Id,
                Contact__c = person.Id,
                Status__c = StewardshipService.STATUS_RUNNING,
                Started_Date__c = System.today()
            );

            Test.startTest();
            StewardshipPlanController.PageModel page = StewardshipPlanController.getPage();
            Test.stopTest();

            Assert.areEqual(1, page.templates.size(), 'The one plan is listed.');
            StewardshipPlanController.TemplateModel shown = page.templates[0];
            Assert.areEqual(2, shown.steps.size(), 'With both of its steps.');
            Assert.areEqual(
                'Call to say thank you',
                shown.steps[0].subject,
                'In the order they are laid out rather than the order they were created.'
            );
            Assert.areEqual(
                1,
                shown.runningPlans,
                'And the number an edit will not reach, which is what R-SP7 costs.'
            );
            Assert.isFalse(
                page.triggerEvents.isEmpty(),
                'The events are offered in the words of the field itself.'
            );
            Assert.isFalse(page.assignTo.isEmpty(), 'So are the ways a step can be assigned.');
        }
    }

    @IsTest
    static void aPlanIsCreatedFromThePageWithoutOpeningAnObjectTab() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Id created = StewardshipPlanController.saveTemplate(
                model(null, 'Pledge welcome', 'pledge_welcome')
            );
            Test.stopTest();

            Assert.isNotNull(created, 'The page created the plan.');
            Stewardship_Plan_Template__c saved = [
                SELECT Name, Plan_Key__c, Active__c
                FROM Stewardship_Plan_Template__c
                WHERE Id = :created
            ];
            Assert.areEqual('Pledge welcome', saved.Name, 'With the name the administrator typed.');
            Assert.isFalse(saved.Active__c, 'And off until she says otherwise.');
        }
    }

    private static String keyOf(Id templateId) {
        return [SELECT Plan_Key__c FROM Stewardship_Plan_Template__c WHERE Id = :templateId]
        .Plan_Key__c;
    }

    @IsTest
    static void aNewPlanGetsAKeyMadeFromItsName() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            Id created = StewardshipPlanController.saveTemplate(
                model(null, '  First gift: welcome!  ', null)
            );
            Test.stopTest();

            Assert.areEqual(
                'first_gift_welcome',
                keyOf(created),
                'The administrator is never asked for a code; one is made from the name.'
            );
        }
    }

    /** The bulk case: two hundred plans already share the name, and the next one still saves. */
    @IsTest
    static void aPlanNamedLikeTwoHundredOthersGetsTheNextFreeKey() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Stewardship_Plan_Template__c> existing = new List<Stewardship_Plan_Template__c>();
            for (Integer i = 1; i <= 200; i++) {
                existing.add(
                    new Stewardship_Plan_Template__c(
                        Name = 'Welcome',
                        Plan_Key__c = i == 1 ? 'Welcome' : 'welcome_' + i,
                        Active__c = false,
                        Trigger_Event__c = StewardshipService.EVENT_MANUAL
                    )
                );
            }
            insert existing;

            Test.startTest();
            Id created = StewardshipPlanController.saveTemplate(model(null, 'Welcome', null));
            Test.stopTest();

            Assert.areEqual(
                'welcome_201',
                keyOf(created),
                'Keys are compared without case, as the unique field compares them.'
            );
        }
    }

    @IsTest
    static void editingAPlanNeverChangesItsKey() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c plan = template('Old name', 'old_key', false);

            Test.startTest();
            StewardshipPlanController.saveTemplate(model(plan.Id, 'A new name', null));
            Test.stopTest();

            Assert.areEqual(
                'old_key',
                keyOf(plan.Id),
                'The key is what keeps a renamed plan recognizable, so a rename leaves it alone.'
            );
        }
    }

    @IsTest
    static void aNameWithNoLettersOrDigitsStillGetsAKey() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Assert.areEqual(
                'plan',
                StewardshipPlanController.uniquePlanKeyFor('???'),
                'A name in another script still produces a usable key.'
            );
        }
    }

    @IsTest
    static void aPlanWithNoNameIsRefusedWithSomethingToActOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            String message;

            Test.startTest();
            try {
                StewardshipPlanController.saveTemplate(model(null, '', 'no_name'));
            } catch (AuraHandledException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Giving_Stewardship_ErrorNameRequired,
                message,
                'A plan without a name is refused in words rather than with a stack trace.'
            );
        }
    }

    @IsTest
    static void turningAPlanOnAndOffIsOneAction() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', false);

            Test.startTest();
            StewardshipPlanController.setActive(welcome.Id, true);
            Test.stopTest();

            Assert.isTrue(
                [SELECT Active__c FROM Stewardship_Plan_Template__c WHERE Id = :welcome.Id]
                .Active__c,
                'The switch an administrator uses most often does not need the record opened.'
            );
        }
    }

    @IsTest
    static void aNewStepGoesToTheEndOfThePlan() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', true);
            insert step(welcome.Id, 1, 'Call to say thank you');

            Test.startTest();
            Id added = StewardshipPlanController.saveStep(welcome.Id, stepModel('Send the packet'));
            Test.stopTest();

            Stewardship_Plan_Step__c saved = [
                SELECT Order__c, Subject__c, Days_After_Start__c
                FROM Stewardship_Plan_Step__c
                WHERE Id = :added
            ];
            Assert.areEqual(2, saved.Order__c, 'A step added without an order goes last.');
            Assert.areEqual(
                'Send the packet',
                saved.Subject__c,
                'With the subject that was typed.'
            );
        }
    }

    @IsTest
    static void reorderingWritesTheOrderTheAdministratorPutTheStepsIn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', true);
            List<Stewardship_Plan_Step__c> steps = new List<Stewardship_Plan_Step__c>{
                step(welcome.Id, 1, 'Call to say thank you'),
                step(welcome.Id, 2, 'Send the packet'),
                step(welcome.Id, 3, 'Check in')
            };
            insert steps;

            Test.startTest();
            StewardshipPlanController.reorderSteps(
                welcome.Id,
                new List<Id>{ steps[2].Id, steps[0].Id, steps[1].Id }
            );
            Test.stopTest();

            Map<Id, Stewardship_Plan_Step__c> saved = new Map<Id, Stewardship_Plan_Step__c>(
                [SELECT Id, Order__c FROM Stewardship_Plan_Step__c WHERE Id IN :steps]
            );
            Assert.areEqual(
                1,
                saved.get(steps[2].Id).Order__c,
                'The step moved to the top is first.'
            );
            Assert.areEqual(2, saved.get(steps[0].Id).Order__c, 'The others follow it.');
            Assert.areEqual(3, saved.get(steps[1].Id).Order__c, 'In the order they were given.');
        }
    }

    @IsTest
    static void aStepFromAnotherPlanIsIgnoredRatherThanReordered() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', true);
            Stewardship_Plan_Template__c thanks = template('Major gift thanks', 'thanks', true);
            Stewardship_Plan_Step__c mine = step(welcome.Id, 5, 'Call to say thank you');
            Stewardship_Plan_Step__c theirs = step(thanks.Id, 5, 'Call the major donor');
            insert new List<Stewardship_Plan_Step__c>{ mine, theirs };

            Test.startTest();
            StewardshipPlanController.reorderSteps(welcome.Id, new List<Id>{ theirs.Id, mine.Id });
            Test.stopTest();

            Assert.areEqual(
                5,
                [SELECT Order__c FROM Stewardship_Plan_Step__c WHERE Id = :theirs.Id].Order__c,
                'The order comes from the page, so a step belonging to another plan is not trusted.'
            );
            Assert.areEqual(
                1,
                [SELECT Order__c FROM Stewardship_Plan_Step__c WHERE Id = :mine.Id].Order__c,
                'The plan being reordered is reordered.'
            );
        }
    }

    @IsTest
    static void removingAStepChangesTheRecipeOnly() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template('First gift welcome', 'welcome', true);
            Stewardship_Plan_Step__c only = step(welcome.Id, 1, 'Call to say thank you');
            insert only;

            Test.startTest();
            StewardshipPlanController.deleteStep(only.Id);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan_Step__c WHERE Id = :only.Id],
                'The step is gone from the plan.'
            );
        }
    }

    @IsTest
    static void aUserWithoutTheSettingsPermissionCannotChangeAPlan() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User standard = SettingsTestPermissions.buildStandardUser('Sam', 'Rivera', 'srivera');
            insert standard;

            String message;
            System.runAs(standard) {
                try {
                    StewardshipPlanController.saveTemplate(model(null, 'Anything', 'anything'));
                } catch (AuraHandledException refused) {
                    message = refused.getMessage();
                }
            }

            Assert.areEqual(
                Label.Giving_Stewardship_ErrorNotPermitted,
                message,
                'Changing what the whole organization follows up on needs the settings permission, ' +
                'and says so in words rather than failing quietly.'
            );
        }
    }
}
