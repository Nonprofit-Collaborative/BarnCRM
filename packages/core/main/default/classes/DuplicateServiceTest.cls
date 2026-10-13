/**
 * DuplicateService: the rules C-20 owns (canonical model R-DP2 to R-DP5). Which records the
 * platform calls duplicates is the org's own rules' business, so only one test touches the
 * matcher, and it says what it expects under whichever rules the org has switched on.
 */
@IsTest(testFor='ApexClass:DuplicateService')
private class DuplicateServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Id fakeContactId(Integer n) {
        return Id.valueOf('003' + String.valueOf(n).leftPad(12, '0'));
    }

    /** Saved past any duplicate rule that only alerts, as an import that saved anyway would. */
    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, options);
        return records;
    }

    /**
     * The platform requires every suggestion to name an active duplicate rule, so an org with
     * no active rule for people writes none. The tests below that need a written suggestion
     * say so and stop there in such an org.
     */
    private static Boolean peopleRuleActive() {
        return DuplicateSelector.objectsWithActiveRules(new Set<String>{ 'Contact' })
            .contains('Contact');
    }

    private static Boolean nothingWrittenWithoutARule(List<Contact> people) {
        if (peopleRuleActive()) {
            return false;
        }
        Assert.areEqual(
            0,
            DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, null)
                },
                null
            ),
            'With no active rule for people no suggestion can be written (R-DP1).'
        );
        return true;
    }

    private static List<Contact> twoPeople() {
        return (List<Contact>) insertAllowingDuplicates(
            new List<Contact>{
                new Contact(
                    FirstName = 'Maria',
                    LastName = 'Dupcheck',
                    Email = 'maria.dupcheck@example.org'
                ),
                new Contact(
                    FirstName = 'Mariah',
                    LastName = 'Dupcheck',
                    Email = 'mariah.dupcheck@example.org'
                )
            }
        );
    }

    @IsTest
    static void aPairHasOneKeyWhicheverWayRoundItIsNamed() {
        System.runAs(TestUsers.admin()) {
            Id a = fakeContactId(1);
            Id b = fakeContactId(2);
            Assert.areEqual(
                DuplicateService.pairKey(a, b),
                DuplicateService.pairKey(b, a),
                'A with B is B with A.'
            );
            Assert.areEqual(
                new DuplicateService.Pair(b, a, 'Rule').left,
                a,
                'The lower identifier is always on the left.'
            );
            Assert.isNull(DuplicateService.pairKey(a, null), 'Half a pair has no key.');
            Assert.isTrue(
                DuplicateService.pairKey(a, b).length() <= 40,
                'The key fits Pair Key, Text(40).'
            );
        }
    }

    @IsTest
    static void threeRecordsInOneSuggestionMakeThreePairs() {
        System.runAs(TestUsers.admin()) {
            Set<String> keys = DuplicateService.pairKeysAmong(
                new List<Id>{ fakeContactId(1), fakeContactId(2), fakeContactId(3) }
            );
            Assert.areEqual(3, keys.size(), 'AB, AC and BC.');
            Assert.isTrue(
                DuplicateService.pairKeysAmong(null).isEmpty(),
                'Nothing makes no pairs.'
            );
        }
    }

    @IsTest
    static void onlyNewPairsAreRecorded() {
        System.runAs(TestUsers.admin()) {
            Id a = fakeContactId(1);
            Id b = fakeContactId(2);
            Id c = fakeContactId(3);
            List<DuplicateService.Pair> found = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(a, a, 'Rule'),
                new DuplicateService.Pair(a, b, 'Rule'),
                new DuplicateService.Pair(b, a, 'Rule'),
                new DuplicateService.Pair(a, c, 'Rule'),
                null
            };
            List<DuplicateService.Pair> result = DuplicateService.pairsToRecord(
                found,
                new Set<String>{ DuplicateService.pairKey(a, c) }
            );
            Assert.areEqual(
                1,
                result.size(),
                'A record matched to itself, a repeat and a known pair are all dropped.'
            );
            Assert.areEqual(
                DuplicateService.pairKey(a, b),
                result[0].key,
                'The one new pair is kept.'
            );
            Assert.isTrue(
                DuplicateService.pairsToRecord(null, null).isEmpty(),
                'Nothing found, nothing to record.'
            );
        }
    }

    @IsTest
    static void aPairIsWrittenAsTheSuggestionThePlatformWouldWrite() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            Test.startTest();
            Integer written = DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, 'Unknown')
                },
                new Map<String, Id>()
            );
            Test.stopTest();

            Assert.areEqual(1, written, 'One pair, one suggestion.');
            List<DuplicateRecordItem> items = [
                SELECT RecordId, DuplicateRecordSetId
                FROM DuplicateRecordItem
            ];
            Assert.areEqual(2, items.size(), 'A suggestion of exactly two records.');
            Assert.areEqual(
                items[0].DuplicateRecordSetId,
                items[1].DuplicateRecordSetId,
                'Both in the same suggestion.'
            );
            Assert.isTrue(
                DuplicateService.pairsAlreadySuggested(new Set<Id>{ people[0].Id })
                    .contains(DuplicateService.pairKey(people[0].Id, people[1].Id)),
                'The next scan knows the pair is already waiting for a reviewer.'
            );
            Assert.areEqual(
                0,
                DuplicateService.recordPairs(null, null),
                'Nothing to write, nothing written.'
            );
        }
    }

    @IsTest
    static void aDismissedPairIsRememberedAndTheSuggestionGoes() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, null)
                },
                null
            );
            Id setId = [SELECT Id FROM DuplicateRecordSet LIMIT 1].Id;

            Test.startTest();
            Integer dismissed = DuplicateService.dismiss(
                setId,
                '  Twin sisters at the same address  '
            );
            Test.stopTest();

            Assert.areEqual(1, dismissed, 'One pair, one dismissal.');
            Duplicate_Dismissal__c saved = [
                SELECT Pair_Key__c, Reason__c
                FROM Duplicate_Dismissal__c
            ];
            Assert.areEqual(
                DuplicateService.pairKey(people[0].Id, people[1].Id),
                saved.Pair_Key__c,
                'The pair is remembered.'
            );
            Assert.areEqual(
                'Twin sisters at the same address',
                saved.Reason__c,
                'The reason is kept, trimmed.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM DuplicateRecordSet], 'The suggestion is gone.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Contact WHERE Id IN :people],
                'Neither record is touched.'
            );

            List<DuplicateService.Pair> again = DuplicateService.withoutDismissed(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[1].Id, people[0].Id, null)
                }
            );
            Assert.isTrue(again.isEmpty(), 'The next scan passes the pair over.');
        }
    }

    @IsTest
    static void dismissingAPairTwiceWritesOneDismissal() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateService.Pair pair = new DuplicateService.Pair(
                people[0].Id,
                people[1].Id,
                null
            );
            DuplicateService.recordPairs(new List<DuplicateService.Pair>{ pair }, null);
            DuplicateService.dismiss([SELECT Id FROM DuplicateRecordSet LIMIT 1].Id, null);
            DuplicateService.recordPairs(new List<DuplicateService.Pair>{ pair }, null);

            Test.startTest();
            Integer dismissed = DuplicateService.dismiss(
                [SELECT Id FROM DuplicateRecordSet LIMIT 1].Id,
                'Again'
            );
            Test.stopTest();

            Assert.areEqual(0, dismissed, 'A pair already dismissed is not dismissed again.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Duplicate_Dismissal__c],
                'One dismissal per pair, ever.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM DuplicateRecordSet],
                'The suggestion still goes.'
            );
        }
    }

    @IsTest
    static void dismissingNothingSaysTheSuggestionIsGone() {
        System.runAs(TestUsers.admin()) {
            try {
                DuplicateService.dismiss(null, null);
                Assert.fail('A dismissal needs a suggestion.');
            } catch (DuplicateService.DuplicateException expected) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorNoSuggestion,
                    expected.getMessage(),
                    'Said in words.'
                );
            }
        }
    }

    @IsTest
    static void closingASuggestionRemembersNothing() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, null)
                },
                null
            );
            Test.startTest();
            DuplicateService.closeSet([SELECT Id FROM DuplicateRecordSet LIMIT 1].Id);
            DuplicateService.closeSet(null);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM DuplicateRecordSet], 'The suggestion is gone.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Duplicate_Dismissal__c],
                'A merge is not a dismissal.'
            );
        }
    }

    @IsTest
    static void onlyPeopleAndHouseholdPairsAreKept() {
        System.runAs(TestUsers.admin()) {
            List<Account> accounts = (List<Account>) insertAllowingDuplicates(
                new List<Account>{
                    HouseholdTestDataFactory.newHousehold('The Dupcheck Family'),
                    HouseholdTestDataFactory.newHousehold('The Dupcheck Household'),
                    new Account(Name = 'Dupcheck Hardware')
                }
            );
            List<DuplicateService.Pair> pairs = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(accounts[0].Id, accounts[1].Id, null),
                new DuplicateService.Pair(accounts[0].Id, accounts[2].Id, null),
                new DuplicateService.Pair(fakeContactId(1), fakeContactId(2), null)
            };

            Test.startTest();
            List<DuplicateService.Pair> kept = DuplicateService.actionablePairs(pairs);
            Test.stopTest();

            Assert.areEqual(
                2,
                kept.size(),
                'A household paired with an organization is not proposed (R-DP2).'
            );
            Assert.areEqual(pairs[0].key, kept[0].key, 'Two households are kept.');
            Assert.areEqual(pairs[2].key, kept[1].key, 'Two people are kept.');
            Assert.isTrue(
                DuplicateService.actionablePairs(null).isEmpty(),
                'Nothing in, nothing out.'
            );
        }
    }

    @IsTest
    static void aHouseholdThatIsAlsoANonprofitCloudHouseholdIsNotProposed() {
        System.runAs(TestUsers.admin()) {
            List<Account> households = (List<Account>) insertAllowingDuplicates(
                new List<Account>{
                    HouseholdTestDataFactory.newHousehold('The Npccheck Family'),
                    HouseholdTestDataFactory.newHousehold('The Npccheck Family'),
                    HouseholdTestDataFactory.newHousehold('The Npccheck Family')
                }
            );
            // The middle one carries a native household group, as in a Nonprofit Cloud org.
            HouseholdSelector.accountsWithNativeHouseholdGroupsOverride = new Set<Id>{
                households[1].Id
            };
            List<DuplicateService.Pair> pairs = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(households[0].Id, households[1].Id, null),
                new DuplicateService.Pair(households[1].Id, households[2].Id, null),
                new DuplicateService.Pair(households[0].Id, households[2].Id, null)
            };

            Test.startTest();
            List<DuplicateService.Pair> kept = DuplicateService.actionablePairs(pairs);
            Test.stopTest();

            Assert.areEqual(1, kept.size(), 'Only the pair with no native household is kept.');
            Assert.areEqual(pairs[2].key, kept[0].key, 'The two BarnCRM-only households.');
        }
    }

    /**
     * Needs real person accounts: the contact half of one is what the people pass must not
     * propose. Proven only where person accounts exist and the running user can create one.
     */
    @IsTest
    static void aPersonAccountIsNotProposedAsADuplicateOfAContact() {
        System.runAs(TestUsers.admin()) {
            Id personType = OrgShapeDetector.creatablePersonRecordTypeId();
            if (personType == null) {
                Assert.isTrue(
                    DuplicateSelector.personContactIds(new Set<Id>{ fakeContactId(1) }).isEmpty(),
                    'Without person accounts no contact is a person account.'
                );
                return;
            }
            SObject person = Account.SObjectType.newSObject();
            person.put('RecordTypeId', personType);
            person.put('FirstName', 'Paz');
            person.put('LastName', 'Dupcheck');
            insertAllowingDuplicates(new List<SObject>{ person });
            Id personContact = PersonRecordSelector.getPersonContactIds(new Set<Id>{ person.Id })
                .get(person.Id);
            List<Contact> people = twoPeople();
            List<DuplicateService.Pair> pairs = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(people[0].Id, personContact, null),
                new DuplicateService.Pair(people[0].Id, people[1].Id, null)
            };

            Test.startTest();
            List<DuplicateService.Pair> kept = DuplicateService.actionablePairs(pairs);
            Test.stopTest();

            Assert.areEqual(1, kept.size(), 'The pair with a person account is dropped.');
            Assert.areEqual(pairs[1].key, kept[0].key, 'Two contacts are kept.');
        }
    }

    /**
     * The canary for the tests that stop early when no duplicate rule is active: in a scratch
     * org, where Salesforce switches the standard rules on, a run with them off fails here
     * instead of passing with the duplicate feature untested. In any other org (a sandbox or
     * production, where switching the rules off is the administrator's choice) it only says so.
     */
    @IsTest
    static void aScratchOrgKeepsTheStandardRulesOnSoNoDuplicateTestIsSkipped() {
        System.runAs(TestUsers.admin()) {
            // A scratch org is the one kind of org that is a sandbox and expires.
            Organization org = [
                SELECT IsSandbox, TrialExpirationDate
                FROM Organization
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            Boolean scratchOrg = org.IsSandbox && org.TrialExpirationDate != null;
            Set<String> active = DuplicateSelector.objectsWithActiveRules(
                new Set<String>(DuplicateSelector.REVIEWED_OBJECTS)
            );
            if (!scratchOrg) {
                Assert.isNotNull(active, 'Outside a scratch org the rules are the org\'s choice.');
                return;
            }
            Assert.isTrue(
                active.contains('Contact') && active.contains('Account'),
                'A scratch org must keep an active duplicate rule for Contact and for Account, ' +
                    'or the duplicate tests return early and test nothing. Active for: ' +
                    active
            );
        }
    }

    @IsTest
    static void theMatcherIsAskedOnlyWhenThereIsSomethingToAsk() {
        System.runAs(TestUsers.admin()) {
            Assert.isTrue(
                DuplicateService.matchesFor(new List<Id>()).isEmpty(),
                'The platform refuses an empty list; we do not ask.'
            );
        }
    }

    @IsTest
    static void aMatcherFailureIsCountedAndAnsweredWithNothing() {
        System.runAs(TestUsers.admin()) {
            DuplicateService.stubFails = true;
            Integer before = DuplicateService.failureCount;

            Test.startTest();
            List<DuplicateService.Pair> found = DuplicateService.matchesFor(
                new List<Id>{ fakeContactId(1) }
            );
            Test.stopTest();

            Assert.isTrue(
                found.isEmpty(),
                'A failed call finds nothing rather than stopping a scan.'
            );
            Assert.areEqual(
                before + 1,
                DuplicateService.failureCount,
                'And is counted, not hidden.'
            );
        }
    }

    @IsTest
    static void theStubAnswersOnlyForTheRecordsAskedAbout() {
        System.runAs(TestUsers.admin()) {
            DuplicateService.stubMatches = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(fakeContactId(1), fakeContactId(2), null),
                new DuplicateService.Pair(fakeContactId(3), fakeContactId(4), null)
            };
            List<DuplicateService.Pair> found = DuplicateService.matchesFor(
                new List<Id>{ fakeContactId(2) }
            );
            Assert.areEqual(1, found.size(), 'Only the pair that names a record asked about.');
        }
    }

    @IsTest
    static void aSuggestionOfOneRecordIsNotReviewed() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateRecordSet lonely = new DuplicateRecordSet(
                DuplicateRuleId = DuplicateSelector.activeRuleIdByObject(
                        new Set<String>{ 'Contact' }
                    )
                    .get('Contact')
            );
            insert lonely;
            insert new DuplicateRecordItem(
                DuplicateRecordSetId = lonely.Id,
                RecordId = people[0].Id
            );

            try {
                DuplicateService.dismiss(lonely.Id, null);
                Assert.fail('One record is nothing to dismiss.');
            } catch (DuplicateService.DuplicateException expected) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorNotReviewable,
                    expected.getMessage(),
                    'Said in words.'
                );
            }
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Duplicate_Dismissal__c],
                'Nothing is remembered.'
            );
        }
    }

    @IsTest
    static void aMergeMayCloseOnlyTheSuggestionItCameFrom() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, null)
                },
                null
            );
            Id setId = [SELECT Id FROM DuplicateRecordSet LIMIT 1].Id;

            Assert.areEqual(
                setId,
                DuplicateService.requireSetOf(setId, new Set<Id>{ people[1].Id, people[0].Id }).Id,
                'The pair the suggestion names is accepted, whichever way round.'
            );
            try {
                DuplicateService.requireSetOf(setId, new Set<Id>{ people[0].Id, fakeContactId(9) });
                Assert.fail('A different pair is refused.');
            } catch (DuplicateService.DuplicateException expected) {
                Assert.areEqual(
                    Label.Core_Duplicates_ErrorNotThisPair,
                    expected.getMessage(),
                    'Said in words.'
                );
            }
        }
    }

    @IsTest
    static void aDismissalThatLosesARaceStillCountsAsDone() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twoPeople();
            if (nothingWrittenWithoutARule(people)) {
                return;
            }
            DuplicateService.recordPairs(
                new List<DuplicateService.Pair>{
                    new DuplicateService.Pair(people[0].Id, people[1].Id, null)
                },
                null
            );
            // Somebody else's dismissal lands between this one's check and its write.
            insert new Duplicate_Dismissal__c(
                Pair_Key__c = DuplicateService.pairKey(people[0].Id, people[1].Id)
            );
            DuplicateService.skipDismissedCheck = true;

            Test.startTest();
            Integer dismissed = DuplicateService.dismiss(
                [SELECT Id FROM DuplicateRecordSet LIMIT 1].Id,
                'Same decision'
            );
            Test.stopTest();

            Assert.areEqual(0, dismissed, 'The other person wrote the dismissal.');
            Assert.areEqual(1, [SELECT COUNT() FROM Duplicate_Dismissal__c], 'Still one per pair.');
            Assert.areEqual(0, [SELECT COUNT() FROM DuplicateRecordSet], 'The suggestion goes.');
        }
    }

    /**
     * The one test that asks the platform's matcher itself. Two people with the same name and
     * email address are what the standard rule for people is for, so where that rule is active
     * the answer is exactly one pair. Anywhere else the org's own rules decide, which is
     * nothing this test can predict, so it is skipped.
     */
    @IsTest
    static void theStandardRuleForPeopleFindsIdenticalTwinsOnce() {
        System.runAs(TestUsers.admin()) {
            Integer standardRuleActive = [
                SELECT COUNT()
                FROM DuplicateRule
                WHERE DeveloperName = 'Standard_Contact_Duplicate_Rule' AND IsActive = TRUE
            ];
            if (standardRuleActive == 0) {
                // Skipped: Standard_Contact_Duplicate_Rule is not active in this org, so what the
                // matcher answers depends on rules this test cannot know.
                return;
            }
            List<Contact> twins = (List<Contact>) insertAllowingDuplicates(
                new List<Contact>{
                    new Contact(
                        FirstName = 'Dana',
                        LastName = 'Dupcheck',
                        Email = 'dana.dupcheck@example.org'
                    ),
                    new Contact(
                        FirstName = 'Dana',
                        LastName = 'Dupcheck',
                        Email = 'dana.dupcheck@example.org'
                    )
                }
            );

            Test.startTest();
            List<DuplicateService.Pair> found = DuplicateService.pairsToRecord(
                DuplicateService.matchesFor(new List<Id>{ twins[0].Id, twins[1].Id }),
                null
            );
            Test.stopTest();

            Assert.areEqual(1, found.size(), 'Identical twins are exactly one pair.');
            Assert.areEqual(
                DuplicateService.pairKey(twins[0].Id, twins[1].Id),
                found[0].key,
                'And it is these two.'
            );
        }
    }
}
