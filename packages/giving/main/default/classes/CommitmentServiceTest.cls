/**
 * Tests for the schedule David sees when he records a pledge or a recurring gift, and for
 * what happens to it when gifts arrive, when the schedule changes, and when the daily job
 * runs (G-07).
 */
@IsTest
private class CommitmentServiceTest {
    /**
     * A gift saves only when there is a default fund to allocate it to (R-GA2).
     */
    @TestSetup
    static void makeData() {
        GivingTestDataFactory.ensureDefaultFund();
    }

    private static Contact donor() {
        Contact person = new Contact(FirstName = 'Sarah', LastName = 'Nguyen');
        insert person;
        return person;
    }

    private static Commitment__c newPledge(Id donorId, Date start) {
        return new Commitment__c(
            Type__c = 'Pledge',
            Status__c = 'Active',
            Donor_Contact__c = donorId,
            Amount__c = 100,
            Frequency__c = 'Monthly',
            Start_Date__c = start,
            End_Date__c = start.addMonths(12).addDays(-1),
            Expected_Total__c = 1200,
            Installments_Planned__c = 12
        );
    }

    private static List<Installment__c> installmentsOf(Id commitmentId) {
        return [
            SELECT Id, Sequence__c, Due_Date__c, Expected_Amount__c, Status__c
            FROM Installment__c
            WHERE Commitment__c = :commitmentId
            ORDER BY Sequence__c
        ];
    }

    @IsTest
    static void generatesTwelveMonthlyInstallmentsForAPledge() {
        Contact person = donor();
        Date start = Date.today();
        Commitment__c pledge = newPledge(person.Id, start);

        Test.startTest();
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        List<Installment__c> schedule = installmentsOf(pledge.Id);
        Assert.areEqual(12, schedule.size(), 'A 1,200 pledge of 100 a month is twelve payments.');
        Assert.areEqual(
            start,
            schedule[0].Due_Date__c,
            'The first payment falls on the start date.'
        );
        Assert.areEqual(
            start.addMonths(11),
            schedule[11].Due_Date__c,
            'The last payment falls eleven months later.'
        );
        Assert.areEqual(100, schedule[0].Expected_Amount__c, 'Each payment is the amount.');
        Assert.areEqual('Scheduled', schedule[0].Status__c, 'A new payment is Scheduled.');
    }

    @IsTest
    static void countsInstallmentsFromTheTotalWhenNoneArePlanned() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Installments_Planned__c = null;
        pledge.Expected_Total__c = 250;
        pledge.Amount__c = 100;
        pledge.End_Date__c = null;

        Test.startTest();
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        List<Installment__c> schedule = installmentsOf(pledge.Id);
        Assert.areEqual(3, schedule.size(), '250 divided by 100 rounds up to three payments.');
        Assert.areEqual(100, schedule[0].Expected_Amount__c, 'The first payment is the amount.');
        Assert.areEqual(
            50,
            schedule[2].Expected_Amount__c,
            'The last payment absorbs what the even amounts left over.'
        );
    }

    @IsTest
    static void putsTheThirtyFirstOnTheLastDayOfAShortMonth() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.newInstance(2027, 1, 31));
        pledge.Day_of_Month__c = 31;
        pledge.Installments_Planned__c = 4;
        pledge.Expected_Total__c = null;
        pledge.End_Date__c = null;

        Test.startTest();
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        List<Installment__c> schedule = installmentsOf(pledge.Id);
        Assert.areEqual(4, schedule.size(), 'Four payments were planned.');
        Assert.areEqual(
            Date.newInstance(2027, 2, 28),
            schedule[1].Due_Date__c,
            'A 31 falls on the last day of February.'
        );
        Assert.areEqual(
            Date.newInstance(2027, 3, 31),
            schedule[2].Due_Date__c,
            'March is back on the thirty first, because dates are computed from the start.'
        );
    }

    @IsTest
    static void handlesTheLeapDay() {
        Contact person = donor();
        // A monthly schedule that starts on a leap day keeps landing on the last day it can.
        Commitment__c monthly = newPledge(person.Id, Date.newInstance(2028, 2, 29));
        monthly.Installments_Planned__c = 2;
        monthly.Expected_Total__c = null;
        monthly.End_Date__c = null;
        List<Installment__c> monthlyPlan = CommitmentService.buildSchedule(monthly);
        Assert.areEqual(
            Date.newInstance(2028, 2, 29),
            monthlyPlan[0].Due_Date__c,
            'The first payment falls on the leap day itself.'
        );
        Assert.areEqual(
            Date.newInstance(2028, 3, 29),
            monthlyPlan[1].Due_Date__c,
            'The next month is the twenty ninth, because March has one.'
        );

        // A yearly schedule from a leap day falls on the twenty eighth in a common year.
        Commitment__c yearly = newPledge(person.Id, Date.newInstance(2028, 2, 29));
        yearly.Frequency__c = 'Yearly';
        yearly.Installments_Planned__c = 2;
        yearly.Expected_Total__c = null;
        yearly.End_Date__c = null;
        List<Installment__c> yearlyPlan = CommitmentService.buildSchedule(yearly);
        Assert.areEqual(
            Date.newInstance(2029, 2, 28),
            yearlyPlan[1].Due_Date__c,
            'A leap day anniversary falls on the twenty eighth in a year that has no twenty ninth.'
        );
    }

    @IsTest
    static void spacesEveryFrequencyCorrectly() {
        Contact person = donor();
        Date start = Date.newInstance(2026, 10, 5);
        Map<String, Date> secondDueDate = new Map<String, Date>{
            'Weekly' => Date.newInstance(2026, 10, 12),
            'Every two weeks' => Date.newInstance(2026, 10, 19),
            'Monthly' => Date.newInstance(2026, 11, 5),
            'Quarterly' => Date.newInstance(2027, 1, 5),
            'Twice a year' => Date.newInstance(2027, 4, 5),
            'Yearly' => Date.newInstance(2027, 10, 5)
        };

        for (String frequency : secondDueDate.keySet()) {
            Commitment__c pledge = new Commitment__c(
                Type__c = 'Pledge',
                Status__c = 'Active',
                Donor_Contact__c = person.Id,
                Amount__c = 50,
                Frequency__c = frequency,
                Start_Date__c = start,
                Installments_Planned__c = 2
            );
            List<Installment__c> plan = CommitmentService.buildSchedule(pledge);
            Assert.areEqual(2, plan.size(), 'Two payments were planned for ' + frequency + '.');
            Assert.areEqual(
                secondDueDate.get(frequency),
                plan[1].Due_Date__c,
                'The second payment of a ' + frequency + ' schedule is spaced correctly.'
            );
        }
    }

    @IsTest
    static void generatesARecurringScheduleToTheHorizonAndTopsItUp() {
        Contact person = donor();
        Commitment__c recurring = new Commitment__c(
            Type__c = 'Recurring',
            Status__c = 'Active',
            Donor_Contact__c = person.Id,
            Amount__c = 25,
            Frequency__c = 'Monthly',
            Start_Date__c = Date.today()
        );

        Test.startTest();
        insert recurring;
        CommitmentService.generateInstallments(new Set<Id>{ recurring.Id });
        Integer firstPass = installmentsOf(recurring.Id).size();
        CommitmentService.topUpRecurringSchedules(
            new List<Commitment__c>{ new Commitment__c(Id = recurring.Id) }
        );
        Test.stopTest();

        Assert.isTrue(firstPass >= 12, 'A year of payments is generated ahead: ' + firstPass);
        Assert.areEqual(
            firstPass,
            installmentsOf(recurring.Id).size(),
            'Topping up the same day adds nothing, because generation is idempotent.'
        );
    }

    @IsTest
    static void generatesForTwoHundredCommitmentsInOneInsert() {
        Contact person = donor();
        List<Commitment__c> pledges = new List<Commitment__c>();
        for (Integer index = 0; index < 200; index++) {
            Commitment__c pledge = newPledge(person.Id, Date.today());
            pledge.Installments_Planned__c = 4;
            pledge.Expected_Total__c = 400;
            pledge.End_Date__c = null;
            pledges.add(pledge);
        }

        Test.startTest();
        insert pledges;
        CommitmentService.generateInstallments(new Map<Id, Commitment__c>(pledges).keySet());
        Test.stopTest();

        Assert.areEqual(
            800,
            [SELECT COUNT() FROM Installment__c],
            'Two hundred commitments of four payments generate eight hundred rows in one pass.'
        );
    }

    @IsTest
    static void marksTheFirstInstallmentPaidWhenAGiftArrives() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        List<Installment__c> schedule = installmentsOf(pledge.Id);

        Gift__c gift = new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 100,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = pledge.Id,
            Installment__c = schedule[0].Id
        );

        Test.startTest();
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });
        Test.stopTest();

        Assert.areEqual(
            'Paid',
            [SELECT Status__c FROM Installment__c WHERE Id = :schedule[0].Id].Status__c,
            'A gift for the whole expected amount pays the payment off.'
        );
    }

    @IsTest
    static void marksAnInstallmentPartiallyPaid() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        List<Installment__c> schedule = installmentsOf(pledge.Id);

        Gift__c gift = new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 40,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = pledge.Id,
            Installment__c = schedule[0].Id
        );

        Test.startTest();
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });
        Test.stopTest();

        Assert.areEqual(
            'Partially paid',
            [SELECT Status__c FROM Installment__c WHERE Id = :schedule[0].Id].Status__c,
            'Part of the expected amount leaves the payment partly paid.'
        );
    }

    @IsTest
    static void appliesAGiftThatNamesOnlyTheCommitment() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        List<Installment__c> schedule = installmentsOf(pledge.Id);

        Gift__c gift = new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 100,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = pledge.Id
        );

        Test.startTest();
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });
        Test.stopTest();

        Gift__c saved = [SELECT Installment__c FROM Gift__c WHERE Id = :gift.Id];
        Assert.areEqual(
            schedule[0].Id,
            saved.Installment__c,
            'A gift with no payment named goes to the earliest unpaid one.'
        );
    }

    @IsTest
    static void completesAPledgeThatHasBeenPaidInFull() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Expected_Total__c = 100;
        pledge.Installments_Planned__c = 1;
        pledge.End_Date__c = null;
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });

        Gift__c gift = new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 100,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = pledge.Id
        );

        Test.startTest();
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });
        Test.stopTest();

        Assert.areEqual(
            'Completed',
            [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
            'A pledge paid to its expected total is Completed.'
        );
    }

    @IsTest
    static void marksOverdueOnlyAfterTheGracePeriod() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today().addMonths(-2));
        pledge.End_Date__c = null;
        insert pledge;

        List<Installment__c> installments = new List<Installment__c>{
            new Installment__c(
                Commitment__c = pledge.Id,
                Sequence__c = 1,
                Due_Date__c = Date.today().addDays(-30),
                Expected_Amount__c = 100,
                Status__c = 'Scheduled'
            ),
            new Installment__c(
                Commitment__c = pledge.Id,
                Sequence__c = 2,
                Due_Date__c = Date.today().addDays(-1),
                Expected_Amount__c = 100,
                Status__c = 'Scheduled'
            )
        };
        insert installments;

        Test.startTest();
        CommitmentService.markOverdue();
        Test.stopTest();

        Assert.areEqual(
            'Overdue',
            [SELECT Status__c FROM Installment__c WHERE Id = :installments[0].Id].Status__c,
            'A payment a month late is Overdue.'
        );
        Assert.areEqual(
            'Scheduled',
            [SELECT Status__c FROM Installment__c WHERE Id = :installments[1].Id].Status__c,
            'A payment one day late is still inside the grace period.'
        );
    }

    @IsTest
    static void rebuildsUnpaidInstallmentsWhenTheAmountChanges() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Installments_Planned__c = 4;
        pledge.Expected_Total__c = 400;
        pledge.End_Date__c = null;
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });

        pledge.Amount__c = 50;
        pledge.Expected_Total__c = 200;
        update pledge;

        Test.startTest();
        CommitmentService.regenerateFutureInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        List<Installment__c> schedule = installmentsOf(pledge.Id);
        Assert.areEqual(4, schedule.size(), 'The number of payments did not change.');
        Assert.areEqual(
            50,
            schedule[0].Expected_Amount__c,
            'The unpaid payments carry the new amount.'
        );
    }

    @IsTest
    static void leavesAPaidInstallmentAloneWhenTheScheduleChanges() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Installments_Planned__c = 3;
        pledge.Expected_Total__c = 300;
        pledge.End_Date__c = null;
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        List<Installment__c> schedule = installmentsOf(pledge.Id);

        Gift__c gift = new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 100,
            Type__c = 'Check',
            Status__c = 'Received',
            Commitment__c = pledge.Id,
            Installment__c = schedule[0].Id
        );
        insert gift;
        CommitmentService.applyGift(new List<Gift__c>{ gift });

        Test.startTest();
        CommitmentService.regenerateFutureInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        Installment__c paid = [
            SELECT Status__c, Expected_Amount__c
            FROM Installment__c
            WHERE Id = :schedule[0].Id
        ];
        Assert.areEqual('Paid', paid.Status__c, 'A paid payment keeps its status.');
        Assert.areEqual(100, paid.Expected_Amount__c, 'A paid payment is never rewritten.');
    }

    @IsTest
    static void pausesResumesCancelsAndCompletes() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        Set<Id> ids = new Set<Id>{ pledge.Id };

        Test.startTest();
        CommitmentService.pause(ids);
        Assert.areEqual(
            'Paused',
            [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
            'Pausing stops generation.'
        );
        CommitmentService.resume(ids);
        Assert.areEqual(
            'Active',
            [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
            'Resuming starts it again.'
        );
        CommitmentService.cancel(ids);
        Test.stopTest();

        Assert.areEqual(
            'Cancelled',
            [SELECT Status__c FROM Commitment__c WHERE Id = :pledge.Id].Status__c,
            'Cancelling ends the commitment.'
        );
        Assert.areEqual(
            12,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id AND Status__c = 'Skipped'
            ],
            'Cancelling marks the unpaid payments Skipped and deletes nothing.'
        );
    }

    @IsTest
    static void refusesAStatusChangeThatIsNotAllowed() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Status__c = 'Cancelled';
        insert pledge;

        Boolean refused = false;
        Test.startTest();
        try {
            CommitmentService.pause(new Set<Id>{ pledge.Id });
        } catch (CommitmentService.CommitmentException expected) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A cancelled commitment cannot be paused.');
    }

    @IsTest
    static void keepsAnInstallmentAPendingGiftPointsAtWhenTheScheduleShrinks() {
        Contact person = donor();
        Commitment__c pledge = newPledge(person.Id, Date.today());
        pledge.Installments_Planned__c = 4;
        pledge.Expected_Total__c = 400;
        pledge.End_Date__c = null;
        insert pledge;
        CommitmentService.generateInstallments(new Set<Id>{ pledge.Id });
        List<Installment__c> schedule = installmentsOf(pledge.Id);
        Installment__c last = schedule[3];

        // A pledged gift is not Received, so it adds nothing to Paid Amount, but it does
        // point at the payment and must not have that payment removed from under it.
        insert new Gift__c(
            Donor_Contact__c = person.Id,
            Gift_Date__c = Date.today(),
            Amount__c = 100,
            Type__c = 'Check',
            Status__c = 'Pending',
            Commitment__c = pledge.Id,
            Installment__c = last.Id
        );

        pledge.Installments_Planned__c = 2;
        pledge.Expected_Total__c = 200;
        update pledge;

        Test.startTest();
        CommitmentService.regenerateFutureInstallments(new Set<Id>{ pledge.Id });
        Test.stopTest();

        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Installment__c WHERE Id = :last.Id],
            'A payment a gift points at survives the schedule shrinking (R-CM2).'
        );
        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM Installment__c
                WHERE Commitment__c = :pledge.Id AND Sequence__c = 3
            ],
            'The payment beyond the shorter schedule that nothing points at is removed.'
        );
    }

    @IsTest
    static void recordsWhenTheTopUpJobLastRanAndWhatItDid() {
        Datetime finishedAt = System.now();

        Test.startTest();
        CommitmentService.recordTopUpRun(finishedAt, 'Extended 3 recurring schedules.');
        Test.stopTest();

        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        Assert.areNotEqual(
            null,
            settings.Installment_Top_Up_Last_Run__c,
            'The job records when it finished, which is what the Hub shows.'
        );
        Assert.areEqual(
            'Extended 3 recurring schedules.',
            settings.Installment_Top_Up_Last_Run_Summary__c,
            'It also records what it did, because a timestamp alone says only that the job woke up.'
        );
    }

    @IsTest
    static void recordsWhenTheOverduePassLastRanAndWhatItMarked() {
        Datetime finishedAt = System.now();

        Test.startTest();
        CommitmentService.recordOverdueRun(finishedAt, 'No payments were overdue.');
        Test.stopTest();

        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        Assert.areNotEqual(
            null,
            settings.Installment_Overdue_Last_Run__c,
            'A pass that marked nothing still records that it ran, so a blank stamp means it never ran.'
        );
        Assert.areEqual(
            'No payments were overdue.',
            settings.Installment_Overdue_Last_Run_Summary__c,
            'The sentence the Nightly Jobs page shows is the one the pass wrote.'
        );
    }
}
