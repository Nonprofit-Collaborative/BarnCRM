/**
 * What a stewardship plan does when it starts, and the four things it refuses to do.
 *
 * These tests have not been executed against an org: none was reachable from the environment they
 * were written in. They are written to the rules in canonical model Sections 25I to 25K.
 */
@IsTest
private class StewardshipServiceTest {
    private static final String WELCOME = 'First gift welcome';
    private static final String MAJOR = 'Major gift thanks';

    /**
     * A gift saves only when there is a default fund to allocate it to (R-GA2).
     */
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            GivingTestDataFactory.ensureDefaultFund();
        }
    }

    private static Stewardship_Plan_Template__c template(
        String name,
        String event,
        Decimal minimum
    ) {
        return new Stewardship_Plan_Template__c(
            Name = name,
            Plan_Key__c = name.toLowerCase().replace(' ', '_'),
            Active__c = true,
            Trigger_Event__c = event,
            Minimum_Amount__c = minimum
        );
    }

    private static Stewardship_Plan_Step__c step(Id templateId, Integer order, Integer days) {
        return new Stewardship_Plan_Step__c(
            Stewardship_Plan_Template__c = templateId,
            Order__c = order,
            Subject__c = 'Step ' + order,
            Days_After_Start__c = days,
            Assign_To__c = StewardshipService.ASSIGN_RECORD_OWNER,
            Priority__c = 'Normal'
        );
    }

    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Ana', LastName = 'Ramirez');
        insert person;
        return person;
    }

    @IsTest
    static void aFirstGiftStartsThePlanAndLaysOutItsTasks() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template(
                WELCOME,
                StewardshipService.EVENT_FIRST_GIFT,
                null
            );
            insert welcome;
            insert new List<Stewardship_Plan_Step__c>{
                step(welcome.Id, 1, 0),
                step(welcome.Id, 2, 7)
            };
            Contact person = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 50);
            Test.stopTest();

            List<Stewardship_Plan__c> started = [
                SELECT Id, Status__c, Started_Date__c, Contact__c, Account__c, Gift__c
                FROM Stewardship_Plan__c
            ];
            Assert.areEqual(1, started.size(), 'The first gift started one plan.');
            Assert.areEqual(
                StewardshipService.STATUS_RUNNING,
                started[0].Status__c,
                'A plan starts running.'
            );
            Assert.areEqual(person.Id, started[0].Contact__c, 'It runs for the donor.');
            Assert.isNull(started[0].Account__c, 'And only one side of the donor pair is set.');
            Assert.isNotNull(started[0].Gift__c, 'It records the gift that started it.');

            List<Task> tasks = [
                SELECT Subject, ActivityDate, WhatId
                FROM Task
                WHERE WhatId = :started[0].Id
                ORDER BY ActivityDate ASC
            ];
            Assert.areEqual(2, tasks.size(), 'Both steps became tasks (R-SP7).');
            Assert.areEqual(
                started[0].Started_Date__c,
                tasks[0].ActivityDate,
                'Day zero is the day the plan started (R-SP5).'
            );
            Assert.areEqual(
                started[0].Started_Date__c.addDays(7),
                tasks[1].ActivityDate,
                'And day seven is a week later.'
            );
        }
    }

    @IsTest
    static void aSecondGiftDoesNotStartTheFirstGiftPlanAgain() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template(
                WELCOME,
                StewardshipService.EVENT_FIRST_GIFT,
                null
            );
            insert welcome;
            insert step(welcome.Id, 1, 0);
            Contact person = donor();
            insert GivingTestDataFactory.buildGift(person.Id, 50);

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 75);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'The welcome is for the first gift only (R-SP3).'
            );
        }
    }

    @IsTest
    static void aGiftUnderTheThresholdStartsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_GIFT_RECEIVED,
                1000
            );
            insert major;
            insert step(major.Id, 1, 1);
            Contact person = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 999);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'A gift below the minimum is not the gift this plan is waiting for.'
            );
        }
    }

    @IsTest
    static void anInactiveTemplateStartsNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c welcome = template(
                WELCOME,
                StewardshipService.EVENT_GIFT_RECEIVED,
                null
            );
            welcome.Active__c = false;
            insert welcome;
            insert step(welcome.Id, 1, 0);
            Contact person = donor();

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 500);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Only an active template starts anything (R-SP2).'
            );
        }
    }

    @IsTest
    static void theSamePlanWillNotRunTwiceOnOneDonor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_GIFT_RECEIVED,
                null
            );
            insert major;
            insert step(major.Id, 1, 0);
            Contact person = donor();
            insert GivingTestDataFactory.buildGift(person.Id, 500);

            Test.startTest();
            insert GivingTestDataFactory.buildGift(person.Id, 600);
            Test.stopTest();

            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'One running plan per template per donor (R-SP6).'
            );
        }
    }

    @IsTest
    static void startingByHandRefusesASecondRunAndSaysWhy() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_MANUAL,
                null
            );
            insert major;
            insert step(major.Id, 1, 0);
            Contact person = donor();
            StewardshipService.start(major.Id, person.Id, null);

            Test.startTest();
            String message;
            try {
                StewardshipService.start(major.Id, person.Id, null);
            } catch (StewardshipService.StewardshipException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Giving_Stewardship_ErrorAlreadyRunning,
                message,
                'A person who pressed a button is told why nothing happened (R-SP6).'
            );
        }
    }

    @IsTest
    static void startingByHandNeedsExactlyOneDonor() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_MANUAL,
                null
            );
            insert major;

            Test.startTest();
            String message;
            try {
                StewardshipService.start(major.Id, null, null);
            } catch (StewardshipService.StewardshipException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                System.Label.Giving_Stewardship_ErrorOneDonor,
                message,
                'A plan runs for one donor, never for nobody.'
            );
        }
    }

    @IsTest
    static void cancellingAPlanLeavesItsTasksAlone() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_MANUAL,
                null
            );
            insert major;
            insert step(major.Id, 1, 0);
            Contact person = donor();
            Stewardship_Plan__c running = StewardshipService.start(major.Id, person.Id, null);
            Integer tasksBefore = [SELECT COUNT() FROM Task WHERE WhatId = :running.Id];

            Test.startTest();
            StewardshipService.close(running.Id, StewardshipService.STATUS_CANCELLED);
            Test.stopTest();

            Stewardship_Plan__c after = [
                SELECT Status__c, Completed_Date__c
                FROM Stewardship_Plan__c
                WHERE Id = :running.Id
            ];
            Assert.areEqual(
                StewardshipService.STATUS_CANCELLED,
                after.Status__c,
                'The plan says it was abandoned.'
            );
            Assert.isNotNull(after.Completed_Date__c, 'And when.');
            Assert.areEqual(
                tasksBefore,
                [SELECT COUNT() FROM Task WHERE WhatId = :running.Id],
                'The package never deletes a task it created (R-SP8).'
            );
        }
    }

    @IsTest
    static void twoHundredGiftsStayInsideTheLimits() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Stewardship_Plan_Template__c major = template(
                MAJOR,
                StewardshipService.EVENT_GIFT_RECEIVED,
                null
            );
            insert major;
            insert step(major.Id, 1, 0);

            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(new Contact(FirstName = 'Donor', LastName = 'Number' + i));
            }
            insert people;
            List<Gift__c> gifts = new List<Gift__c>();
            for (Contact person : people) {
                gifts.add(GivingTestDataFactory.buildGift(person.Id, 25));
            }

            Test.startTest();
            Integer queriesBefore = Limits.getQueries();
            insert gifts;
            Integer queriesUsed = Limits.getQueries() - queriesBefore;
            Test.stopTest();

            Assert.areEqual(
                200,
                [SELECT COUNT() FROM Stewardship_Plan__c],
                'Every donor got their plan.'
            );
            Assert.isTrue(
                queriesUsed < 40,
                'Two hundred gifts cost a handful of queries, not one per gift. Used: ' +
                queriesUsed
            );
        }
    }
}
