/**
 * DuplicateScanBatch: the scan over records already in the org (R-DP3). Which records an org's
 * rules call duplicates is the org's business, so these tests set the matcher's answer
 * (DuplicateService.stubMatches) and assert exactly what the scan does with it: it writes only
 * new, actionable pairs, counts a chunk it could not check, and never touches the records.
 *
 * The platform requires every suggestion to name an active duplicate rule, and a test cannot
 * switch one on. A test that must write a suggestion therefore stops, with an assertion that
 * nothing was written, in an org with no active rule for its object.
 */
@IsTest
private class DuplicateScanBatchTest {
    private static List<SObject> insertAllowingDuplicates(List<SObject> records) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(records, options);
        return records;
    }

    private static Boolean ruleActiveFor(String objectName) {
        return DuplicateSelector.objectsWithActiveRules(new Set<String>{ objectName })
            .contains(objectName);
    }

    private static List<Contact> twins(String firstName) {
        String email = firstName.toLowerCase() + '.dupscan@example.org';
        return (List<Contact>) insertAllowingDuplicates(
            new List<Contact>{
                new Contact(FirstName = firstName, LastName = 'Dupscan', Email = email),
                new Contact(FirstName = firstName, LastName = 'Dupscan', Email = email)
            }
        );
    }

    /** The matcher's answer for this pair, found from both sides as the platform reports it. */
    private static void matcherAnswers(Id first, Id second) {
        DuplicateService.stubMatches = new List<DuplicateService.Pair>{
            new DuplicateService.Pair(first, second, null),
            new DuplicateService.Pair(second, first, null)
        };
    }

    @IsTest
    static void aChunkRecordsEachNewPairOnceAndASecondPassAddsNothing() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twins('Rosa');
            matcherAnswers(people[0].Id, people[1].Id);
            Map<String, Id> rules = DuplicateSelector.activeRuleIdsByName(
                new Set<String>{ 'Contact' }
            );

            Test.startTest();
            Integer first = DuplicateScanBatch.scanChunk(people, rules);
            Integer second = DuplicateScanBatch.scanChunk(people, rules);
            Test.stopTest();

            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Contact WHERE Id IN :people],
                'The scan changes no record.'
            );
            if (!ruleActiveFor('Contact')) {
                // Skipped: no active rule for people in this org, so no suggestion can be written.
                Assert.areEqual(0, first + second, 'With no active rule nothing is written.');
                return;
            }
            Assert.areEqual(1, first, 'A pair found from both sides is one suggestion.');
            Assert.areEqual(
                0,
                second,
                'A pair already waiting for a reviewer is not written twice.'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM DuplicateRecordSet], 'Exactly one suggestion.');
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM DuplicateRecordItem],
                'Of exactly two records.'
            );
        }
    }

    @IsTest
    static void aDismissedPairIsNotWrittenAgain() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twins('Iris');
            matcherAnswers(people[0].Id, people[1].Id);
            insert new Duplicate_Dismissal__c(
                Pair_Key__c = DuplicateService.pairKey(people[0].Id, people[1].Id)
            );

            Test.startTest();
            Integer written = DuplicateScanBatch.scanChunk(
                people,
                DuplicateSelector.activeRuleIdsByName(new Set<String>{ 'Contact' })
            );
            Test.stopTest();

            Assert.areEqual(0, written, 'A pair somebody dismissed is passed over (R-DP5).');
            Assert.areEqual(0, [SELECT COUNT() FROM DuplicateRecordSet], 'Nothing is written.');
        }
    }

    @IsTest
    static void onlyAPairOfHouseholdsIsWritten() {
        System.runAs(TestUsers.admin()) {
            List<Account> accounts = (List<Account>) insertAllowingDuplicates(
                new List<Account>{
                    HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                    HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                    new Account(Name = 'The Dupscan Family')
                }
            );
            DuplicateService.stubMatches = new List<DuplicateService.Pair>{
                new DuplicateService.Pair(accounts[0].Id, accounts[1].Id, null),
                new DuplicateService.Pair(accounts[0].Id, accounts[2].Id, null),
                new DuplicateService.Pair(accounts[1].Id, accounts[2].Id, null)
            };

            Test.startTest();
            Integer written = DuplicateScanBatch.scanChunk(accounts, null);
            Test.stopTest();

            if (!ruleActiveFor('Account')) {
                // Skipped: no active rule for accounts in this org, so no suggestion can be written.
                Assert.areEqual(0, written, 'With no active rule nothing is written.');
                return;
            }
            Assert.areEqual(1, written, 'Only the two households are paired (R-DP2).');
            Set<Id> named = new Set<Id>();
            for (DuplicateRecordItem item : [SELECT RecordId FROM DuplicateRecordItem]) {
                named.add(item.RecordId);
            }
            Assert.areEqual(
                new Set<Id>{ accounts[0].Id, accounts[1].Id },
                named,
                'The organization is in no suggestion.'
            );
        }
    }

    @IsTest
    static void theHouseholdPassReadsOnlyHouseholdsAndSaysWhatItFound() {
        System.runAs(TestUsers.admin()) {
            List<Account> accounts = (List<Account>) insertAllowingDuplicates(
                new List<Account>{
                    HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                    HouseholdTestDataFactory.newHousehold('The Dupscan Family'),
                    new Account(Name = 'Dupscan Hardware')
                }
            );
            matcherAnswers(accounts[0].Id, accounts[1].Id);
            DuplicateScanBatch batch = new DuplicateScanBatch('Account', null);

            Test.startTest();
            List<SObject> scope = new List<SObject>();
            Database.QueryLocatorIterator rows = batch.start(null).iterator();
            while (rows.hasNext()) {
                scope.add(rows.next());
            }
            batch.execute(null, scope);
            batch.finish(null);
            Test.stopTest();
            Test.getEventBus().deliver();

            Set<Id> read = new Map<Id, SObject>(scope).keySet();
            Assert.isTrue(read.contains(accounts[0].Id), 'A household is read.');
            Assert.isFalse(read.contains(accounts[2].Id), 'An organization is never read (R-DP2).');
            Assert.areEqual(0, batch.failedChunks, 'Nothing failed.');
            Assert.areEqual(
                ruleActiveFor('Account') ? 1 : 0,
                batch.written,
                'The one pair of households is written, where the org has a rule to name.'
            );
            List<Error_Log__c> summary = [
                SELECT Severity__c
                FROM Error_Log__c
                WHERE Context__c = :DuplicateScanBatch.LOG_CONTEXT
            ];
            Assert.areEqual(1, summary.size(), 'A finished scan says so once.');
            Assert.areEqual(
                ErrorLogger.SEVERITY_INFO,
                summary[0].Severity__c,
                'A clean scan is Info.'
            );
        }
    }

    @IsTest
    static void aChunkThatCouldNotBeCheckedIsCountedAndTheSummaryWarns() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = twins('Lena');
            DuplicateService.stubFails = true;
            DuplicateScanBatch batch = new DuplicateScanBatch('Contact', null);

            Test.startTest();
            batch.execute(null, people);
            batch.finish(null);
            Test.stopTest();
            Test.getEventBus().deliver();

            Assert.areEqual(1, batch.failedChunks, 'The chunk the matcher refused is counted.');
            Assert.areEqual(0, batch.written, 'Nothing is written for it.');
            List<Error_Log__c> summary = [
                SELECT Severity__c
                FROM Error_Log__c
                WHERE Context__c = :DuplicateScanBatch.LOG_CONTEXT
            ];
            Assert.areEqual(1, summary.size(), 'One summary.');
            Assert.areEqual(
                ErrorLogger.SEVERITY_WARNING,
                summary[0].Severity__c,
                'A scan with a chunk it could not check never reads as a clean result.'
            );
        }
    }

    @IsTest
    static void peopleStoredAsAccountsAreLeftOutOnlyWhereTheyExist() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(
                HouseholdService.isPersonAccountOrg(),
                DuplicateScanBatch.queryFor('Contact').contains('WHERE'),
                'The people pass leaves out person accounts, and names the field only where it exists.'
            );
            Assert.isTrue(
                DuplicateScanBatch.queryFor('Account').contains(':householdType'),
                'The account pass reads households only.'
            );
        }
    }

    @IsTest
    static void aScanStartsOnlyWhenThereIsARuleToRun() {
        System.runAs(TestUsers.admin()) {
            Boolean anyActive = ruleActiveFor('Contact') || ruleActiveFor('Account');
            Test.startTest();
            Id jobId = DuplicateScanBatch.start();
            // No stopTest: a scan chains its second object, which a test method cannot run.
            Assert.areEqual(
                anyActive,
                jobId != null,
                'A scan starts exactly when a rule is active (R-DP3).'
            );
        }
    }
}
