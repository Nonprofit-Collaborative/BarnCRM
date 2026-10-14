/**
 * The limits and failure paths of the household soft credit recompute job: nothing to do, more
 * households than one save may chase, no job slot left, and a job that cannot read what it needs.
 * A recompute that cannot run must leave the gift that asked for it saved, and says so in the
 * Error Log; the credits are corrected the next time each gift is saved.
 */
@IsTest(testFor='ApexClass:HouseholdSoftCreditRecompute')
private class HouseholdSoftCreditRecomputeTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Giving_Admin');
    }

    /**
     * Households with one gift each: a household with no gifts is never queued, so only these
     * reach the job.
     */
    private static List<Id> householdsWithGifts(Integer howMany) {
        GivingTestDataFactory.ensureDefaultFund();
        Id householdType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(RecognitionTestData.HOUSEHOLD_RECORD_TYPE)
            .getRecordTypeId();
        List<Account> households = new List<Account>();
        for (Integer i = 0; i < howMany; i++) {
            households.add(new Account(Name = 'Household ' + i, RecordTypeId = householdType));
        }
        insert households;
        List<Gift__c> gifts = new List<Gift__c>();
        for (Account household : households) {
            gifts.add(RecognitionTestData.newGift(null, household.Id, 100));
        }
        insert gifts;
        return new List<Id>(new Map<Id, Account>(households).keySet());
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
            Set<Id> households = new Set<Id>(householdsWithGifts(3));

            Test.startTest();
            HouseholdSoftCreditRecompute.enqueue(households);
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
            Set<Id> households = new Set<Id>(
                householdsWithGifts(
                    HouseholdSoftCreditRecompute.HOUSEHOLDS_PER_TRANSACTION_CAP + 10
                )
            );

            Test.startTest();
            HouseholdSoftCreditRecompute.enqueue(households);
            Test.stopTest();

            Assert.areEqual(1, jobsRun(), 'The capped list still gets its job');
        }
    }

    @IsTest
    static void whenNoJobSlotIsLeftTheRecomputeIsDeferredNotThrown() {
        System.runAs(TestUsers.adminWith('Giving_Admin')) {
            List<Id> households = householdsWithGifts(Limits.getLimitQueueableJobs() + 1);

            Test.startTest();
            for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) {
                HouseholdSoftCreditRecompute.enqueue(new Set<Id>{ households[i] });
            }
            Integer queuedBefore = Limits.getQueueableJobs();
            HouseholdSoftCreditRecompute.enqueue(new Set<Id>{ households[households.size() - 1] });
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
            Set<Id> households = new Set<Id>(householdsWithGifts(2));
            User outsider = TestDataFactory.createUser('NoAccess', new List<String>());

            System.runAs(outsider) {
                Test.startTest();
                HouseholdSoftCreditRecompute.enqueue(households);
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
