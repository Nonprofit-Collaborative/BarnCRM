/**
 * The engine comparison (`RollupEngineComparison`). Core holds no giving objects, so it counts
 * people onto their organization, as `RollupFullRecalcBatchTest` does.
 *
 * These tests have not been executed: no Salesforce org exists in this environment.
 */
@IsTest
private class RollupEngineComparisonTest {
    private static final String KEY = 'Test_People_Per_Organization';
    private static final Integer STORED = 99;

    private static Rollup_Definition__c peopleCount() {
        // Every night, so adding the people below starts no instant run and the stored value
        // stays what the test set.
        Rollup_Definition__c definition = new Rollup_Definition__c(
            Name = 'People per organization',
            Definition_Key__c = KEY,
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_SCHEDULED,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
        insert definition;
        return definition;
    }

    /** Organizations with a stale stored count and one or two people each. */
    private static List<Account> organizations(Integer count) {
        Id organizationType = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get('Organization')
            .getRecordTypeId();
        List<Account> organizations = new List<Account>();
        for (Integer i = 0; i < count; i++) {
            organizations.add(
                new Account(
                    Name = 'Organization ' + i,
                    RecordTypeId = organizationType,
                    NumberOfEmployees = STORED
                )
            );
        }
        insert organizations;
        List<Contact> people = new List<Contact>();
        for (Integer i = 0; i < count; i++) {
            for (Integer j = 0; j <= Math.mod(i, 2); j++) {
                people.add(new Contact(LastName = 'Person ' + j, AccountId = organizations[i].Id));
            }
        }
        insert people;
        return organizations;
    }

    /** Two hundred organizations, the most one run compares per definition. */
    @IsTest
    static void bothEnginesAgreeAndNothingIsSaved() {
        peopleCount();
        List<Account> stale = organizations(200);

        Test.startTest();
        RollupEngineComparison.Report report = RollupEngineComparison.run(
            new Set<String>{ KEY },
            RollupEngineComparison.LARGEST_SAMPLE
        );
        Test.stopTest();

        Assert.areEqual(1, report.definitionsCompared, 'The one definition is compared');
        Assert.areEqual(200, report.valuesCompared, 'Over every organization');
        Assert.areEqual(
            0,
            report.differences.size(),
            'Both engines count the same people: ' + report.summary()
        );
        Assert.isFalse(report.startedBackgroundWork, 'The vendored engine ran in this transaction');
        Assert.isTrue(report.notCompared.isEmpty(), report.summary());
        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Account WHERE Id IN :stale AND NumberOfEmployees = :STORED],
            'Nothing either engine calculated was kept'
        );
        Assert.isFalse(
            AutomationControl.isBypassed('Core_Rollups_Contact'),
            'The bypasses end with the run'
        );
    }

    @IsTest
    static void namedRecordsAreComparedAndAnUnknownKeyIsReported() {
        peopleCount();
        Account organization = organizations(1)[0];
        Contact person = [SELECT Id FROM Contact LIMIT 1];

        Test.startTest();
        RollupEngineComparison.Report report = RollupEngineComparison.compare(
            new Set<Id>{ organization.Id, person.Id },
            new Set<String>{ KEY, 'No_Such_Definition' }
        );
        Test.stopTest();

        Assert.areEqual(1, report.valuesCompared, 'Only the record of the target entity');
        Assert.areEqual(0, report.differences.size(), report.summary());
        Assert.areEqual(
            System.Label.Core_RollupComparison_NoDefinition,
            report.notCompared.get('No_Such_Definition'),
            'A key no active definition has is named, not ignored'
        );
    }

    @IsTest
    static void aDefinitionWithNoRecordsIsReported() {
        peopleCount();

        RollupEngineComparison.Report report = RollupEngineComparison.run(null, null);

        Assert.areEqual(0, report.definitionsCompared, 'There is nothing to compare over');
        Assert.areEqual(
            System.Label.Core_RollupComparison_NoRecords,
            report.notCompared.get(KEY),
            'And the report says so'
        );
    }

    @IsTest
    static void theSummaryNamesEveryFinding() {
        RollupEngineComparison.Report report = new RollupEngineComparison.Report();
        report.definitionsCompared = 2;
        report.valuesCompared = 7;
        RollupEngineComparison.Difference difference = new RollupEngineComparison.Difference();
        difference.definitionKey = KEY;
        difference.targetField = 'NumberOfEmployees';
        difference.recordId = UserInfo.getUserId();
        difference.stored = 1;
        difference.barncrm = 2;
        difference.vendored = 3;
        report.differences.add(difference);
        report.notCompared.put('Other_Key', 'A reason');
        report.notReached.add('Later_Key');

        List<String> lines = report.summary().split('\n');

        Assert.areEqual(4, lines.size(), 'A total, a difference, a skip and the keys left');
        Assert.isTrue(lines[0].contains('7'), lines[0]);
        Assert.isTrue(lines[1].contains(KEY) && lines[1].contains('3'), lines[1]);
        Assert.isTrue(lines[2].contains('Other_Key') && lines[2].contains('A reason'), lines[2]);
        Assert.isTrue(lines[3].contains('Later_Key'), lines[3]);
    }

    @IsTest
    static void numbersAreComparedAsNumbers() {
        Assert.isTrue(RollupEngineComparison.same(3, 3.0), 'An Integer and a Decimal');
        Assert.isTrue(RollupEngineComparison.same(null, null), 'Two blanks');
        Assert.isFalse(RollupEngineComparison.same(0, null), 'Zero is not blank');
        Assert.isTrue(RollupEngineComparison.same('a', 'a'), 'Text');
        Assert.isFalse(RollupEngineComparison.same('a', 'b'), 'Different text');
    }
}
