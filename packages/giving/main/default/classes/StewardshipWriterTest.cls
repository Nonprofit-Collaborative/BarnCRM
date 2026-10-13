/**
 * The writes behind a stewardship plan: starting a batch of plans with their tasks, and closing
 * one. A plan that cannot start must never stop the gift or commitment that asked for it, so
 * every failure here is logged and swallowed, and what could still be written is written.
 */
@IsTest(testFor='ApexClass:StewardshipWriter')
private class StewardshipWriterTest {
    private static final Integer TWO_HUNDRED = 200;

    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = new Stewardship_Plan_Template__c(
                Name = 'Every gift thanks',
                Plan_Key__c = 'every_gift_thanks_writer',
                Active__c = true,
                Trigger_Event__c = StewardshipService.EVENT_GIFT_RECEIVED
            );
            insert template;
            insert new List<Stewardship_Plan_Step__c>{
                new Stewardship_Plan_Step__c(
                    Stewardship_Plan_Template__c = template.Id,
                    Order__c = 1,
                    Subject__c = 'Call to say thank you',
                    Days_After_Start__c = 1,
                    Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
                    Priority__c = 'High'
                ),
                new Stewardship_Plan_Step__c(
                    Stewardship_Plan_Template__c = template.Id,
                    Order__c = 2,
                    Subject__c = 'Send a handwritten note',
                    Days_After_Start__c = 7,
                    Assign_To__c = StewardshipService.ASSIGN_PLAN_STARTER
                )
            };
        }
    }

    private static Stewardship_Plan_Template__c templateWithSteps() {
        return [
            SELECT
                Id,
                Name,
                (
                    SELECT
                        Subject__c,
                        Comments__c,
                        Days_After_Start__c,
                        Priority__c,
                        Assign_To__c,
                        Assigned_User__c,
                        Order__c
                    FROM Steps__r
                    ORDER BY Order__c
                )
            FROM Stewardship_Plan_Template__c
            WHERE Plan_Key__c = 'every_gift_thanks_writer'
        ];
    }

    private static Stewardship_Plan__c planFor(Id contactId, Id templateId) {
        return new Stewardship_Plan__c(
            Contact__c = contactId,
            Stewardship_Plan_Template__c = templateId,
            Status__c = 'Running',
            Started_Date__c = Date.today()
        );
    }

    @IsTest
    static void nothingToStartIsNotAnError() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;

            Test.startTest();
            StewardshipWriter.startPlans(null, new List<Stewardship_Plan_Template__c>{ template });
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>(),
                new List<Stewardship_Plan_Template__c>{ template }
            );
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ planFor(person.Id, template.Id) },
                null
            );
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'No plan was started');
            Assert.areEqual(0, [SELECT COUNT() FROM Task], 'And no task was made');
        }
    }

    @IsTest
    static void plansAndTemplatesThatDoNotLineUpStartNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ planFor(person.Id, template.Id) },
                new List<Stewardship_Plan_Template__c>{ template, template }
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'A plan cannot be paired with a template when the lists differ, so none starts'
            );
        }
    }

    @IsTest
    static void aPlanForAPersonGetsEachStepAsATaskOwnedByThatPersonsOwner() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ planFor(person.Id, template.Id) },
                new List<Stewardship_Plan_Template__c>{ template }
            );
            Test.stopTest();

            Stewardship_Plan__c plan = [SELECT Id FROM Stewardship_Plan__c];
            List<Task> tasks = [
                SELECT Subject, ActivityDate, Priority, OwnerId, Status
                FROM Task
                WHERE WhatId = :plan.Id
                ORDER BY ActivityDate
            ];
            Assert.areEqual(2, tasks.size(), 'One task for each of the two steps');
            Assert.areEqual('Call to say thank you', tasks[0].Subject, 'In step order');
            Assert.areEqual(Date.today().addDays(1), tasks[0].ActivityDate, 'Dated from the start');
            Assert.areEqual(
                Date.today().addDays(7),
                tasks[1].ActivityDate,
                'A week on for the note'
            );
            Assert.areEqual('High', tasks[0].Priority, 'The step priority is kept');
            Assert.areEqual('Normal', tasks[1].Priority, 'A step with none gets Normal');
            Assert.areEqual(
                [SELECT OwnerId FROM Contact WHERE Id = :person.Id].OwnerId,
                tasks[0].OwnerId,
                'The record owner step goes to whoever owns the person'
            );
            Assert.areEqual(
                UserInfo.getUserId(),
                tasks[1].OwnerId,
                'The plan starter step goes to the starter'
            );
        }
    }

    @IsTest
    static void aPlanForAnOrganizationUsesTheOrganizationsOwner() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Account riverside = new Account(Name = 'Riverside Foundation');
            insert riverside;
            Stewardship_Plan__c plan = new Stewardship_Plan__c(
                Account__c = riverside.Id,
                Stewardship_Plan_Template__c = template.Id,
                Status__c = 'Running',
                Started_Date__c = Date.today()
            );

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ plan },
                new List<Stewardship_Plan_Template__c>{ template }
            );
            Test.stopTest();

            Task first = [
                SELECT OwnerId
                FROM Task
                WHERE WhatId = :plan.Id AND Subject = 'Call to say thank you'
            ];
            Assert.areEqual(
                [SELECT OwnerId FROM Account WHERE Id = :riverside.Id].OwnerId,
                first.OwnerId,
                'The record owner step goes to whoever owns the organization'
            );
        }
    }

    @IsTest
    static void twoHundredPlansStartWithTheirFourHundredTasks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < TWO_HUNDRED; i++) {
                people.add(new Contact(FirstName = 'Donor' + i, LastName = 'Plan'));
            }
            insert people;
            List<Stewardship_Plan__c> plans = new List<Stewardship_Plan__c>();
            List<Stewardship_Plan_Template__c> templates = new List<Stewardship_Plan_Template__c>();
            for (Contact person : people) {
                plans.add(planFor(person.Id, template.Id));
                templates.add(template);
            }

            Test.startTest();
            StewardshipWriter.startPlans(plans, templates);
            Test.stopTest();

            Assert.areEqual(
                TWO_HUNDRED,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Every one of the 200 plans started'
            );
            Assert.areEqual(
                TWO_HUNDRED * 2,
                [SELECT COUNT() FROM Task WHERE WhatId IN :plans],
                'With both steps as tasks for each'
            );
        }
    }

    @IsTest
    static void aPlanThatIsRefusedDoesNotStopTheOthersAndGetsNoTasks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;
            Stewardship_Plan__c good = planFor(person.Id, template.Id);
            Stewardship_Plan__c bad = planFor(person.Id, template.Id);
            bad.Status__c = 'Not a status';

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ bad, good },
                new List<Stewardship_Plan_Template__c>{ template, template }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Only the good plan saved'
            );
            Assert.areEqual(2, [SELECT COUNT() FROM Task], 'And only it has tasks');
        }
    }

    @IsTest
    static void aListThatCannotBeInsertedIsLoggedAndNothingElseHappens() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;
            Stewardship_Plan__c alreadyHasAnId = planFor(person.Id, template.Id);
            alreadyHasAnId.Id = FakeIds.of(Stewardship_Plan__c.SObjectType, 1);

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ alreadyHasAnId },
                new List<Stewardship_Plan_Template__c>{ template }
            );
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'No plan was written');
            Assert.areEqual(0, [SELECT COUNT() FROM Task], 'And no task');
        }
    }

    @IsTest
    static void aTemplateReadWithoutItsStepsStartsThePlanWithoutTasks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c bare = [
                SELECT Id, Name
                FROM Stewardship_Plan_Template__c
                WHERE Plan_Key__c = 'every_gift_thanks_writer'
            ];
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;

            Test.startTest();
            StewardshipWriter.startPlans(
                new List<Stewardship_Plan__c>{ planFor(person.Id, bare.Id) },
                new List<Stewardship_Plan_Template__c>{ bare }
            );
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'The plan still starts: a task that cannot be built never costs the plan'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Task], 'There is nothing to assign');
        }
    }

    @IsTest
    static void closingAPlanSavesItsStatus() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = templateWithSteps();
            Contact person = new Contact(LastName = 'Ramirez');
            insert person;
            Stewardship_Plan__c plan = planFor(person.Id, template.Id);
            insert plan;
            plan.Status__c = 'Complete';
            plan.Completed_Date__c = Date.today();

            Test.startTest();
            StewardshipWriter.closePlan(plan);
            StewardshipWriter.closePlan(null);
            Test.stopTest();

            Stewardship_Plan__c closed = [
                SELECT Status__c, Completed_Date__c
                FROM Stewardship_Plan__c
                WHERE Id = :plan.Id
            ];
            Assert.areEqual('Complete', closed.Status__c, 'The plan is complete');
            Assert.areEqual(Date.today(), closed.Completed_Date__c, 'On the day it was closed');
        }
    }

    @IsTest
    static void closingAPlanThatCannotBeSavedIsLoggedNotThrown() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan__c neverSaved = new Stewardship_Plan__c(Status__c = 'Complete');

            Test.startTest();
            StewardshipWriter.closePlan(neverSaved);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Stewardship_Plan__c], 'Nothing was written');
        }
    }
}
