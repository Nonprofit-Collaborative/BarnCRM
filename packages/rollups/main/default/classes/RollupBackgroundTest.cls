/**
 * Real-time totals recalculated just after the save, the default (ADR-0098 async rollups,
 * canonical model R-R4): the save marks and queues, the Rollup Queue recalculates, and the
 * totals end up exactly what recalculating in the save gives.
 *
 * Core holds no giving objects, so people (Contact, registered for real time by
 * `Core_Rollups_Contact`) are counted on their organization (`AccountId`).
 */
@IsTest(testFor='ApexClass:RollupService, ApexClass:RollupQueue')
private class RollupBackgroundTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static final Integer EMPLOYER_COUNT = 10;

    private static Rollup_Definition__c staffCount() {
        return new Rollup_Definition__c(
            Name = 'Staff count',
            Definition_Key__c = 'Test_Background_Staff_Count',
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    private static List<Account> organizations(Integer count) {
        Id organizationType = AccountKindsTestData.organizationRecordTypeId();
        List<Account> created = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            created.add(new Account(Name = 'Organization ' + i, RecordTypeId = organizationType));
        }
        insert created;
        return created;
    }

    private static Map<Id, Integer> countsOn(List<Account> organizations) {
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (Account organization : [
            SELECT Id, NumberOfEmployees
            FROM Account
            WHERE Id IN :new Map<Id, Account>(organizations).keySet()
        ]) {
            counts.put(
                organization.Id,
                organization.NumberOfEmployees == null ? 0 : organization.NumberOfEmployees
            );
        }
        return counts;
    }

    /** What every total should be: the people each organization has now, counted directly. */
    private static Map<Id, Integer> expectedOn(List<Account> organizations) {
        Map<Id, Integer> expected = new Map<Id, Integer>();
        for (Account organization : organizations) {
            expected.put(organization.Id, 0);
        }
        for (AggregateResult row : [
            SELECT AccountId, COUNT(Id) people
            FROM Contact
            WHERE AccountId IN :expected.keySet()
            GROUP BY AccountId
        ]) {
            expected.put((Id) row.get('AccountId'), (Integer) row.get('people'));
        }
        return expected;
    }

    private static Integer pending() {
        return [
            SELECT COUNT()
            FROM Rollup_Queue__c
            WHERE Status__c = :RollupQueue.STATUS_PENDING
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void nothingIsSavedSoTheDefaultIsJustAfterTheSave() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Assert.isFalse(
                RollupService.recalculatesInTheSave(),
                'An org that never saved the setting recalculates just after the save'
            );
            RollupTestSupport.recalculateInTheSave();
            Assert.isTrue(RollupService.recalculatesInTheSave(), 'Unless it chose the save');
        }
    }

    /** One save: marked and queued in the save, calculated just after it. */
    @IsTest
    static void aSaveQueuesItsTotalsAndTheQueueCalculatesThem() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            Account organization = organizations(1)[0];

            Test.startTest();
            insert new Contact(LastName = 'Ames', AccountId = organization.Id);
            Integer countInTheSave = countsOn(new List<Account>{ organization })
                .get(organization.Id);
            Integer queuedInTheSave = pending();
            Test.stopTest();

            Assert.areEqual(0, countInTheSave, 'The save did not calculate the total itself');
            Assert.isTrue(queuedInTheSave > 0, 'It queued the organization instead');
            Assert.areEqual(
                1,
                countsOn(new List<Account>{ organization }).get(organization.Id),
                'Just after the save, the queue counted Ames'
            );
        }
    }

    /**
     * 200 people saved, 50 of them moved to another organization, 20 deleted and 10 of those
     * restored, all in one transaction: every organization's count is exactly the people it has
     * at the end, as recalculating in the save gives. The Rollup Queue merges what every save
     * queued into one recalculation per organization.
     */
    @IsTest
    static void aBulkLoadEndsWithTheTotalsTheSaveWouldHaveCalculated() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            insert staffCount();
            List<Account> employers = organizations(EMPLOYER_COUNT);

            Test.startTest();
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(
                    new Contact(
                        LastName = 'Person ' + i,
                        AccountId = employers[Math.mod(i, EMPLOYER_COUNT)].Id
                    )
                );
            }
            insert people;
            List<Contact> moving = new List<Contact>();
            for (Integer i = 0; i < 50; i++) {
                moving.add(
                    new Contact(
                        Id = people[i].Id,
                        AccountId = employers[Math.mod(i + 1, EMPLOYER_COUNT)].Id
                    )
                );
            }
            update moving;
            List<Contact> leaving = new List<Contact>();
            for (Integer i = 100; i < 120; i++) {
                leaving.add(people[i]);
            }
            delete leaving;
            undelete new List<Contact>{
                leaving[0],
                leaving[1],
                leaving[2],
                leaving[3],
                leaving[4],
                leaving[5],
                leaving[6],
                leaving[7],
                leaving[8],
                leaving[9]
            };
            Test.stopTest();

            Assert.areEqual(
                expectedOn(employers),
                countsOn(employers),
                'Each organization counts the people it has after every change'
            );
        }
    }

    /**
     * ROLLUPS-2: recalculating in the save is planned before it starts. One query per
     * definition, one more for a household token, and the fixed cost of the target entity.
     */
    @IsTest
    static void theRecalculationInTheSaveIsPlannedBeforeItStarts() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            Rollup_Definition__c byHousehold = staffCount();
            byHousehold.Definition_Key__c = 'Test_Background_Household';
            byHousehold.Relationship_Path__c = '{Household}';
            byHousehold.Target_Field__c = 'AnnualRevenue';
            List<Rollup_Definition__c> both = new List<Rollup_Definition__c>{
                staffCount(),
                byHousehold
            };
            insert both;
            Map<String, List<Rollup_Definition__c>> marked = new Map<String, List<Rollup_Definition__c>>{
                'Account' => both
            };

            Test.startTest();
            Integer planned = RollupService.plannedQueries(marked);
            Boolean fits = RollupService.canRecalculateNow(1, marked);
            Test.stopTest();

            Assert.areEqual(4 + 1 + 2, planned, 'Fixed cost, one plain, one through a token');
            Assert.isTrue(fits, 'A fresh transaction has the room');
        }
    }
}
