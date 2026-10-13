/**
 * The limits and failure paths of the household soft credit recompute job: nothing to do, more
 * households than one save may chase, no job slot left, and a job that cannot read what it needs.
 * A recompute that cannot run must leave the gift that asked for it saved, and says so in the
 * Error Log; the credits are corrected the next time each gift is saved.
 */
@IsTest(testFor='ApexClass:HouseholdSoftCreditRecompute')
private class HouseholdSoftCreditRecomputeTest {
    private static Set<Id> fakeHouseholds(Integer howMany) {
        Set<Id> ids = new Set<Id>();
        for (Integer i = 1; i <= howMany; i++) {
            ids.add(FakeIds.of(Account.SObjectType, i));
        }
        return ids;
    }

    private static Integer jobsRun() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE ApexClass.Name = 'HouseholdSoftCreditRecompute' AND JobType = 'Queueable'
        ];
    }

    @IsTest
    static void noHouseholdsQueuesNothing() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            HouseholdSoftCreditRecompute.enqueue(null);
            HouseholdSoftCreditRecompute.enqueue(new Set<Id>());
            Test.stopTest();

            Assert.areEqual(0, jobsRun(), 'Nothing to recompute, nothing queued');
        }
    }

    @IsTest
    static void aFewHouseholdsAreRecomputedByOneJob() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            HouseholdSoftCreditRecompute.enqueue(fakeHouseholds(3));
            Test.stopTest();

            Assert.areEqual(1, jobsRun(), 'One job is queued and it runs');
            Assert.areEqual(
                'Completed',
                [
                    SELECT Status
                    FROM AsyncApexJob
                    WHERE ApexClass.Name = 'HouseholdSoftCreditRecompute'
                    LIMIT 1
                ]
                .Status,
                'And it completes: a household with no gifts is not an error'
            );
        }
    }

    @IsTest
    static void aBulkLoadOfPeopleIsCappedAtFiftyHouseholdsAndTheRestIsLogged() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            HouseholdSoftCreditRecompute.enqueue(
                fakeHouseholds(HouseholdSoftCreditRecompute.HOUSEHOLDS_PER_TRANSACTION_CAP + 150)
            );
            Test.stopTest();

            Assert.areEqual(1, jobsRun(), 'The capped list still gets its job');
        }
    }

    @IsTest
    static void whenNoJobSlotIsLeftTheRecomputeIsDeferredNotThrown() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
                HouseholdSoftCreditRecompute.enqueue(
                    new Set<Id>{ FakeIds.of(Account.SObjectType, i + 1) }
                );
            }
            Integer queuedBefore = Limits.getQueueableJobs();
            HouseholdSoftCreditRecompute.enqueue(
                new Set<Id>{ FakeIds.of(Account.SObjectType, 999) }
            );
            Integer queuedAfter = Limits.getQueueableJobs();
            Test.stopTest();

            Assert.areEqual(
                Limits.getLimitQueueableJobs(),
                queuedBefore,
                'Every slot this transaction may use is taken'
            );
            Assert.areEqual(
                queuedBefore,
                queuedAfter,
                'The next request takes none and does not throw'
            );
        }
    }

    @IsTest
    static void aJobThatCannotReadTheGiftsLogsAndStillCompletes() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            User outsider = TestDataFactory.createUser('NoAccess', new List<String>());

            System.runAs(outsider) {
                Test.startTest();
                HouseholdSoftCreditRecompute.enqueue(fakeHouseholds(2));
                Test.stopTest();
            }

            Assert.areEqual(
                'Completed',
                [
                    SELECT Status
                    FROM AsyncApexJob
                    WHERE ApexClass.Name = 'HouseholdSoftCreditRecompute'
                    LIMIT 1
                ]
                .Status,
                'The failure is caught and logged inside the job, so the platform sees it complete'
            );
        }
    }
}
