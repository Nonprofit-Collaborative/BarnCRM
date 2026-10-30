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
    static void theBatchFillsOnlyBlankGreetingsOnCustomNamedHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account blank = customNamed('The Reverend and Mrs. Smith');
            Account oneTyped = customNamed('The Reverend Smith');
            Database.insert(new List<Account>{ blank, oneTyped }, AccessLevel.SYSTEM_MODE);
            insert new List<Contact>{ smith(blank.Id), smith(oneTyped.Id) };
            // Upkeep filled them when the members were added; take the greetings back to what
            // the batch is to start from.
            Database.update(
                new List<Account>{
                    greetings(blank.Id, null, null),
                    greetings(oneTyped.Id, 'The Reverend John Smith', null)
                },
                AccessLevel.SYSTEM_MODE
            );

            Test.startTest();
            Database.executeBatch(new HouseholdNamingBatch(), 200);
            Test.stopTest();

            Account filled = wordingOf(blank.Id);
            Assert.areEqual('The Reverend and Mrs. Smith', filled.Name, 'Custom name kept');
            Assert.areEqual(
                'Mr. John Smith',
                filled.Household_Formal_Greeting__c,
                'A blank formal greeting is filled'
            );
            Assert.areEqual(
                'John',
                filled.Household_Informal_Greeting__c,
                'A blank informal greeting is filled'
            );

            Account kept = wordingOf(oneTyped.Id);
            Assert.areEqual('The Reverend Smith', kept.Name, 'Custom name kept');
            Assert.areEqual(
                'The Reverend John Smith',
                kept.Household_Formal_Greeting__c,
                'A typed greeting is never replaced'
            );
            Assert.areEqual('John', kept.Household_Informal_Greeting__c, 'The blank one filled');
        }
    }

    @IsTest
    static void theBatchFillsBlankGreetingsOnTwoHundredAndOneCustomNamedHouseholds() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            List<Account> households = new List<Account>();
            for (Integer i = 0; i < 201; i++) {
                households.add(customNamed('Typed ' + i));
            }
            Database.insert(households, AccessLevel.SYSTEM_MODE);
            List<Contact> people = new List<Contact>();
            List<Account> reset = new List<Account>();
            for (Integer i = 0; i < 201; i++) {
                people.add(smith(households[i].Id));
                reset.add(greetings(households[i].Id, 'Typed formal ' + i, null));
            }
            insert people;
            Database.update(reset, AccessLevel.SYSTEM_MODE);

            Test.startTest();
            Database.executeBatch(new HouseholdNamingBatch(), 250);
            Test.stopTest();

            Map<Id, Account> saved = new Map<Id, Account>(
                [
                    SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
                    FROM Account
                    WHERE Id IN :households
                    WITH SYSTEM_MODE
                ]
            );
            for (Integer i = 0; i < 201; i++) {
                Account household = saved.get(households[i].Id);
                Assert.areEqual('Typed ' + i, household.Name, 'Custom name kept');
                Assert.areEqual(
                    'Typed formal ' + i,
                    household.Household_Formal_Greeting__c,
                    'Typed formal greeting kept'
                );
                Assert.areEqual(
                    'John',
                    household.Household_Informal_Greeting__c,
                    'Blank informal greeting filled'
                );
            }
        }
    }

    private static Account customNamed(String name) {
        Account household = HouseholdTestDataFactory.newHousehold(name);
        household.Custom_Name__c = true;
        return household;
    }

    /** Mr. John Smith, saved into `householdId`. */
    private static Contact smith(Id householdId) {
        Contact john = HouseholdTestDataFactory.newContact('Mr.', 'John', 'Smith');
        john.AccountId = householdId;
        return john;
    }

    private static Account greetings(Id householdId, String formal, String informal) {
        return new Account(
            Id = householdId,
            Household_Formal_Greeting__c = formal,
            Household_Informal_Greeting__c = informal
        );
    }

    private static Account wordingOf(Id householdId) {
        return [
            SELECT Name, Household_Formal_Greeting__c, Household_Informal_Greeting__c
            FROM Account
            WHERE Id = :householdId
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void everyHouseholdIsRenamedExceptTheOnesWordedByHand() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account patterned = HouseholdTestDataFactory.newHousehold('Old name');
            Account byHand = HouseholdTestDataFactory.newHousehold('The Reverend and Mrs. Smith');
            byHand.Custom_Name__c = true;
            Database.insert(new List<Account>{ patterned, byHand }, AccessLevel.SYSTEM_MODE);
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
            Database.insert(household, AccessLevel.SYSTEM_MODE);
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
            Database.insert(new List<Account>{ native, ordinary }, AccessLevel.SYSTEM_MODE);
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
