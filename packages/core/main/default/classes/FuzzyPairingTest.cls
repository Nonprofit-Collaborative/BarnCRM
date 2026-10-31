/**
 * FuzzyPairing: people paired by similar names, household aware (R-DP7). A similar name is
 * never enough on its own; within one household only the same name pairs two people with
 * nothing else in common; differing birthdates never pair.
 */
@IsTest(testFor='ApexClass:FuzzyPairing')
private class FuzzyPairingTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static List<Contact> insertPeople(List<Contact> people) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(people, options, AccessLevel.SYSTEM_MODE);
        return people;
    }

    private static Account household(String name) {
        Account household = HouseholdTestDataFactory.newHousehold(name);
        Database.insert(household, AccessLevel.SYSTEM_MODE);
        return household;
    }

    private static List<Id> idsOf(List<Contact> people) {
        return new List<Id>(new Map<Id, Contact>(people).keySet());
    }

    @IsTest
    static void similarNamesSharingAnEmailArePairedWithAReason() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Jonathan',
                        LastName = 'Fuzzy',
                        Email = 'jf@example.org'
                    ),
                    new Contact(
                        FirstName = 'Jonathon',
                        LastName = 'Fuzzy',
                        Email = 'JF@example.org '
                    )
                }
            );

            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(idsOf(people));

            Assert.areEqual(1, pairs.size(), 'One pair, found once from both sides.');
            Assert.isNull(pairs[0].ruleName, 'A name pair names no rule.');
            Assert.isTrue(pairs[0].reason.contains('97%'), pairs[0].reason);
            Assert.isTrue(
                pairs[0].reason.contains(Label.Core_DuplicateManagement_SharedEmail),
                pairs[0].reason
            );
        }
    }

    @IsTest
    static void similarNamesWithNothingSharedAreNotPaired() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Jonathan',
                        LastName = 'Fuzzy',
                        Email = 'one@example.org'
                    ),
                    new Contact(
                        FirstName = 'Jonathon',
                        LastName = 'Fuzzy',
                        Email = 'two@example.org'
                    )
                }
            );

            Assert.areEqual(0, FuzzyPairing.pairsFor(idsOf(people)).size());
        }
    }

    @IsTest
    static void inOneHouseholdOnlyTheSameNamePairsPeopleWithNothingElseShared() {
        System.runAs(TestUsers.admin()) {
            Account home = household('Fuzzy Household');
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'John',
                        LastName = 'Fuzzy',
                        AccountId = home.Id,
                        MailingPostalCode = '12345'
                    ),
                    new Contact(
                        FirstName = 'JOHN',
                        LastName = 'fuzzy',
                        AccountId = home.Id,
                        MailingPostalCode = '12345'
                    ),
                    new Contact(
                        FirstName = 'Daniel',
                        LastName = 'Fuzzy',
                        AccountId = home.Id,
                        MailingPostalCode = '12345'
                    ),
                    new Contact(
                        FirstName = 'Danielle',
                        LastName = 'Fuzzy',
                        AccountId = home.Id,
                        MailingPostalCode = '12345'
                    )
                }
            );

            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(idsOf(people));

            Assert.areEqual(1, pairs.size(), 'Only the two Johns: Daniel and Danielle are family.');
            Assert.areEqual(DuplicateService.pairKey(people[0].Id, people[1].Id), pairs[0].key);
            Assert.areEqual(Label.Core_DuplicateManagement_ReasonSameHousehold, pairs[0].reason);
        }
    }

    @IsTest
    static void differentHouseholdsSharingAPostalCodeArePaired() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Katherine',
                        LastName = 'Fuzzy',
                        AccountId = household('Fuzzy One').Id,
                        MailingPostalCode = '12345-6789'
                    ),
                    new Contact(
                        FirstName = 'Katharine',
                        LastName = 'Fuzzy',
                        AccountId = household('Fuzzy Two').Id,
                        MailingPostalCode = '12345'
                    )
                }
            );

            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(idsOf(people));

            Assert.areEqual(1, pairs.size());
            Assert.isTrue(
                pairs[0].reason.contains(Label.Core_DuplicateManagement_SharedPostalCode),
                pairs[0].reason
            );
        }
    }

    @IsTest
    static void differingBirthdatesAreNeverPaired() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Sam',
                        LastName = 'Fuzzy',
                        Phone = '(555) 010-2000',
                        Birthdate = Date.newInstance(1950, 1, 1)
                    ),
                    new Contact(
                        FirstName = 'Sam',
                        LastName = 'Fuzzy',
                        Phone = '555.010.2000',
                        Birthdate = Date.newInstance(1980, 1, 1)
                    ),
                    new Contact(FirstName = 'Sam', LastName = 'Fuzzy', Phone = '15550102000')
                }
            );

            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(idsOf(people));

            Assert.areEqual(
                2,
                pairs.size(),
                'The undated Sam pairs with each; the two dated do not.'
            );
            for (DuplicateService.Pair pair : pairs) {
                Assert.isTrue(pair.key.contains(people[2].Id), pair.key);
                Assert.isTrue(
                    pair.reason.contains(Label.Core_DuplicateManagement_SharedPhone),
                    pair.reason
                );
            }
        }
    }

    @IsTest
    static void householdsAreNotPaired() {
        System.runAs(TestUsers.admin()) {
            Account first = household('Fuzzy Same');
            Account second = household('Fuzzy Same');

            Assert.areEqual(0, FuzzyPairing.pairsFor(new List<Id>{ first.Id, second.Id }).size());
            Assert.areEqual(0, FuzzyPairing.pairsFor(new List<Id>()).size());
            Assert.areEqual(0, FuzzyPairing.pairsFor(null).size());
        }
    }

    @IsTest
    static void thresholdReadsTheDefaultAndHoldsTheRange() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(FuzzyPairing.DEFAULT_THRESHOLD, FuzzyPairing.thresholdPercent());
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Fuzzy_Match_Threshold__c = 50;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(80, FuzzyPairing.thresholdPercent(), 'Below the range reads as 80.');
            settings.Fuzzy_Match_Threshold__c = 150;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(100, FuzzyPairing.thresholdPercent(), 'Above the range reads as 100.');
            settings.Fuzzy_Match_Threshold__c = null;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(90, FuzzyPairing.thresholdPercent(), 'Blank reads as the default.');
        }
    }

    @IsTest
    static void aThresholdOfOneHundredPairsOnlyEqualNames() {
        System.runAs(TestUsers.admin()) {
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Fuzzy_Match_Threshold__c = 100;
            HouseholdTestDataFactory.save(settings);
            List<Contact> people = insertPeople(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Jonathan',
                        LastName = 'Fuzzy',
                        Email = 'jf@example.org'
                    ),
                    new Contact(
                        FirstName = 'Jonathon',
                        LastName = 'Fuzzy',
                        Email = 'jf@example.org'
                    ),
                    new Contact(
                        FirstName = 'Jonathan.',
                        LastName = 'FUZZY',
                        Email = 'jf@example.org'
                    )
                }
            );

            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(idsOf(people));

            Assert.areEqual(1, pairs.size(), 'Only the two Jonathans are the same name.');
            Assert.isTrue(pairs[0].reason.contains('100%'), pairs[0].reason);
        }
    }

    @IsTest
    static void bulkChunkPairsOnlyTheRealDuplicateAndWarnsAtTheCap() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 251; i++) {
                people.add(
                    new Contact(
                        FirstName = 'Person' + i,
                        LastName = 'Bulkfuzz',
                        Email = 'p' + i + '@example.org'
                    )
                );
            }
            people.add(
                new Contact(FirstName = 'Person7', LastName = 'Bulkfuzz', Email = 'p7@example.org')
            );
            insertPeople(people);
            List<Id> chunk = new List<Id>();
            for (Integer i = 0; i < 50; i++) {
                chunk.add(people[i].Id);
            }

            Test.startTest();
            List<DuplicateService.Pair> pairs = FuzzyPairing.pairsFor(chunk);
            FuzzyPairing.maxCandidates = 10;
            FuzzyPairing.pairsFor(chunk);
            Test.stopTest();

            Assert.areEqual(1, pairs.size(), 'Similar names with different emails are not pairs.');
            Assert.areEqual(DuplicateService.pairKey(people[7].Id, people[251].Id), pairs[0].key);
            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'Duplicate scan: pairing similar names'
                    WITH SYSTEM_MODE
                ],
                'Reaching the cap is logged as a warning.'
            );
        }
    }

    @IsTest
    static void aPersonWhoCannotReadPeopleGetsNoPairsAndNoError() {
        List<Contact> people;
        System.runAs(TestUsers.admin()) {
            people = insertPeople(
                new List<Contact>{
                    new Contact(FirstName = 'Jo', LastName = 'Fuzzy', Email = 'jo@example.org'),
                    new Contact(FirstName = 'Jo', LastName = 'Fuzzy', Email = 'jo@example.org')
                }
            );
        }
        System.runAs(TestUsers.minimumAccessUserWith('Fuzzyless', new List<String>())) {
            Integer failuresBefore = DuplicateService.failureCount;

            Assert.areEqual(0, FuzzyPairing.pairsFor(idsOf(people)).size());
            Assert.areEqual(
                failuresBefore,
                DuplicateService.failureCount,
                'With no name readable there is nothing to compare, which is not a failure.'
            );
        }
    }
}
