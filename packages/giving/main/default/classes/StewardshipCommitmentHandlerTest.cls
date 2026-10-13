/**
 * What the Commitment started event does, now that it does something (R-SP3a).
 *
 * These tests have not been executed against an org: none was reachable from the environment they
 * were written in. They are written to the rules in canonical model Sections 25I to 25K.
 */
@IsTest
private class StewardshipCommitmentHandlerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    private static final String PLAN = 'Pledge welcome';

    private static Stewardship_Plan_Template__c activeTemplate() {
        Stewardship_Plan_Template__c template = new Stewardship_Plan_Template__c(
            Name = PLAN,
            Plan_Key__c = 'pledge_welcome',
            Active__c = true,
            Trigger_Event__c = StewardshipService.EVENT_COMMITMENT_STARTED
        );
        insert template;
        insert new List<Stewardship_Plan_Step__c>{
            new Stewardship_Plan_Step__c(
                Stewardship_Plan_Template__c = template.Id,
                Order__c = 1,
                Subject__c = 'Call to thank them for the pledge',
                Days_After_Start__c = 1,
                Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
                Priority__c = 'High'
            ),
            new Stewardship_Plan_Step__c(
                Stewardship_Plan_Template__c = template.Id,
                Order__c = 2,
                Subject__c = 'Send the pledge confirmation',
                Days_After_Start__c = 7,
                Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
                Priority__c = 'Normal'
            )
        };
        return template;
    }

    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        return person;
    }

    private static Commitment__c pledgeFor(Id donorId, String status) {
        return new Commitment__c(
            Type__c = 'Pledge',
            Status__c = status,
            Donor_Contact__c = donorId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today(),
            Expected_Total__c = 300,
            Installments_Planned__c = 3
        );
    }

    @IsTest
    static void aPledgeEnteredActiveStartsThePlanAndLaysOutItsTasks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();

            Test.startTest();
            insert pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            Test.stopTest();

            List<Stewardship_Plan__c> started = [
                SELECT Id, Status__c, Contact__c, Commitment__c, Gift__c, Started_Date__c
                FROM Stewardship_Plan__c
            ];
            Assert.areEqual(1, started.size(), 'A commitment that is already running has started.');
            Assert.areEqual(
                StewardshipService.STATUS_RUNNING,
                started[0].Status__c,
                'A plan starts running.'
            );
            Assert.areEqual(person.Id, started[0].Contact__c, 'It runs for the donor.');
            Assert.isNotNull(
                started[0].Commitment__c,
                'And it records the commitment that started it, as the gift path records the gift.'
            );
            Assert.isNull(started[0].Gift__c, 'No gift started this one.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Task WHERE WhatId = :started[0].Id],
                'Both steps became tasks (R-SP7).'
            );
        }
    }

    @IsTest
    static void aPledgeEnteredPausedStartsNothingUntilItIsTurnedOn() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            Commitment__c pledge = pledgeFor(person.Id, 'Paused');
            insert pledge;
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'A pledge nobody has started yet is not a pledge that started.'
            );

            Test.startTest();
            pledge.Status__c = StewardshipService.COMMITMENT_ACTIVE;
            update pledge;
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Turning it on is the start, because to the donor it is the same event (R-SP3a).'
            );
        }
    }

    @IsTest
    static void anEditThatLeavesTheStatusAloneStartsNothingFurther() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            Commitment__c pledge = pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            insert pledge;

            Test.startTest();
            pledge.Amount__c = 150;
            update pledge;
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Correcting an amount is not starting a commitment, so no second set of tasks.'
            );
        }
    }

    @IsTest
    static void theSamePledgePausedAndResumedDoesNotLayTheTasksOutTwice() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            Commitment__c pledge = pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            insert pledge;
            pledge.Status__c = 'Paused';
            update pledge;

            Test.startTest();
            pledge.Status__c = StewardshipService.COMMITMENT_ACTIVE;
            update pledge;
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'The first plan is still running, so R-SP6 refuses a second copy of the same sequence.'
            );
        }
    }

    @IsTest
    static void aGiftTemplateIsNotStartedByACommitment() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c gifts = new Stewardship_Plan_Template__c(
                Name = 'Every gift thanks',
                Plan_Key__c = 'every_gift_thanks',
                Active__c = true,
                Trigger_Event__c = StewardshipService.EVENT_GIFT_RECEIVED
            );
            insert gifts;
            insert new Stewardship_Plan_Step__c(
                Stewardship_Plan_Template__c = gifts.Id,
                Order__c = 1,
                Subject__c = 'Call to say thank you',
                Days_After_Start__c = 1,
                Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
                Priority__c = 'Normal'
            );
            Contact person = donor();

            Test.startTest();
            insert pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'A plan waiting for a gift is not started by a pledge.'
            );
        }
    }

    @IsTest
    static void anInactiveTemplateStartsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c template = activeTemplate();
            template.Active__c = false;
            update template;
            Contact person = donor();

            Test.startTest();
            insert pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Deactivating a template stops new plans (R-SP2).'
            );
        }
    }

    @IsTest
    static void switchingTheAutomationOffStopsPlansStarting() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            Contact person = donor();
            // The switch is a row the post-install script writes from the registry; a test
            // sees none of the org's rows, so it writes them the same way first.
            AutomationControl.ensureDefaults();
            AutomationControl.setEnabled('Stewardship_Plan_Starter_Commitment', false);
            AutomationControl.clearCache();

            Test.startTest();
            insert pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'An administrator loading a file of commitments gets no plans (R-SP1).'
            );
        }
    }

    @IsTest
    static void aFileOfPledgesCostsAFixedNumberOfQueries() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();
            List<Contact> donors = new List<Contact>();
            for (Integer i = 0; i < 50; i++) {
                donors.add(new Contact(FirstName = 'Donor', LastName = 'Number ' + i));
            }
            insert donors;
            List<Commitment__c> pledges = new List<Commitment__c>();
            for (Contact person : donors) {
                pledges.add(pledgeFor(person.Id, StewardshipService.COMMITMENT_ACTIVE));
            }

            Test.startTest();
            insert pledges;
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(
                50,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Fifty pledges started fifty plans.'
            );
            Assert.isTrue(
                queries < Limits.getLimitQueries(),
                'And they cost a fixed number of queries rather than one per commitment.'
            );
        }
    }

    @IsTest
    static void aPledgeWithNoDonorStartsNothingAndStillSaves() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            activeTemplate();

            Test.startTest();
            Commitment__c orphan = pledgeFor(null, StewardshipService.COMMITMENT_ACTIVE);
            Database.SaveResult saved = Database.insert(orphan, false);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'There is nobody to steward, so nothing starts.'
            );
            Assert.isNotNull(
                saved,
                'And the save was attempted rather than blocked by stewardship.'
            );
        }
    }
}
