/**
 * The recompute Maria starts after she changes a naming pattern.
 */
@IsTest(testFor='ApexClass:HouseholdNamingBatch')
private class HouseholdNamingBatchTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void everyHouseholdIsRenamedExceptTheOnesWordedByHand() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account patterned = HouseholdTestDataFactory.newHousehold('Old name');
            Account byHand = HouseholdTestDataFactory.newHousehold('The Reverend and Mrs. Smith');
            byHand.Custom_Name__c = true;
            insert new List<Account>{ patterned, byHand };
            insert new List<Contact>{
                new Contact(
                    Salutation = 'Ms.',
                    FirstName = 'Maria',
                    LastName = 'Garcia',
                    AccountId = patterned.Id
                ),
                new Contact(
                    Salutation = 'Mr.',
                    FirstName = 'John',
                    LastName = 'Smith',
                    AccountId = byHand.Id
                )
            };
            update new Account(Id = patterned.Id, Name = 'Old name');

            Test.startTest();
            Database.executeBatch(new HouseholdNamingBatch(), 200);
            Test.stopTest();

            Assert.areEqual(
                'The Garcia Family',
                [SELECT Name FROM Account WHERE Id = :patterned.Id].Name,
                'The household was renamed from the pattern'
            );
            Assert.areEqual(
                'The Reverend and Mrs. Smith',
                [SELECT Name FROM Account WHERE Id = :byHand.Id].Name,
                'A household worded by hand is never touched'
            );
        }
    }

    @IsTest
    static void theJobKeepsCountOfWhatItRead() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('Old name');
            insert household;
            HouseholdNamingBatch job = new HouseholdNamingBatch();

            Test.startTest();
            job.execute(null, new List<Account>{ household });
            Test.stopTest();

            Assert.areEqual(1, job.householdsRead, 'One household was read');
        }
    }

    /**
     * Mutual exclusion (product-plan Section 11.2 item 9): a household that already carries
     * a native Nonprofit Cloud household group is left out of the rewrite, while another
     * household in the same scope is still renamed. The native object cannot exist in this
     * test, so the probe is injected the way the delete guard's tests inject it.
     */
    @IsTest
    static void aHouseholdWithANativeGroupIsSkippedButOthersInTheBatchAreStillRenamed() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account native = HouseholdTestDataFactory.newHousehold('Old native name');
            Account ordinary = HouseholdTestDataFactory.newHousehold('Old ordinary name');
            insert new List<Account>{ native, ordinary };
            insert new List<Contact>{
                new Contact(
                    Salutation = 'Ms.',
                    FirstName = 'Maria',
                    LastName = 'Garcia',
                    AccountId = native.Id
                ),
                new Contact(
                    Salutation = 'Mr.',
                    FirstName = 'John',
                    LastName = 'Smith',
                    AccountId = ordinary.Id
                )
            };
            update new List<Account>{
                new Account(Id = native.Id, Name = 'Old native name'),
                new Account(Id = ordinary.Id, Name = 'Old ordinary name')
            };
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNativeHouseholdGroups = true;
            OrgShapeDetector.overrideShape = shape;
            HouseholdSelector.accountsWithNativeDependentsOverride = new Set<Id>{ native.Id };
            HouseholdNamingBatch job = new HouseholdNamingBatch();

            Test.startTest();
            job.execute(null, new List<Account>{ native, ordinary });
            Test.stopTest();

            Assert.areEqual(
                'Old native name',
                [SELECT Name FROM Account WHERE Id = :native.Id].Name,
                'A household with a native group keeps whatever name it already has'
            );
            Assert.areEqual(
                'The Smith Family',
                [SELECT Name FROM Account WHERE Id = :ordinary.Id].Name,
                'An ordinary household in the same batch is still renamed'
            );
            Assert.areEqual(1, job.householdsSkippedNative, 'One skip was counted');
        }
    }
}
