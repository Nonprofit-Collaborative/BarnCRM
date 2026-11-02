/**
 * The Funders sample data (C-10): three grants to Core's sample organizations, counted on the
 * card, removed again with real grants left alone, and nothing loaded where there are no sample
 * organizations.
 */
@IsTest(testFor='ApexClass:FundersSampleData, ApexClass:GrantSampleDataLoader')
private class FundersSampleDataTest {
    @TestSetup
    static void makeAdmin() {
        TestUsers.adminWith(GrantTestData.ADMIN);
    }

    private static User admin() {
        return TestUsers.adminWith(GrantTestData.ADMIN);
    }

    /** Three of Core's sample organizations. */
    private static void sampleOrganizations() {
        List<Account> organizations = new List<Account>();
        for (Integer i = 0; i < 3; i++) {
            Account organization = (Account) TestDataFactory.pastDuplicateRules(
                AccountKindsTestData.organization('Sample Org ' + i)
            );
            organization.Sample_Data__c = true;
            organizations.add(organization);
        }
        insert organizations;
    }

    private static void loadEverything() {
        FundersSampleData.LoadStages stages = new FundersSampleData.LoadStages();
        for (Integer stage = 0; stage < stages.stageCount(); stage++) {
            stages.runStage(stage);
        }
    }

    private static void removeEverything() {
        FundersSampleData.RemoveStages stages = new FundersSampleData.RemoveStages();
        Integer stageCount = stages.stageCount();
        for (Integer stage = 0; stage < stageCount; stage++) {
            stages.runStage(stage);
        }
    }

    @IsTest
    static void theCardCountsTheSampleGrants() {
        System.runAs(admin()) {
            sampleOrganizations();

            Test.startTest();
            loadEverything();
            Test.stopTest();

            FundersSampleData module = new FundersSampleData();
            Assert.areEqual(3, module.countLoaded(), 'Three sample grants are counted');
            Assert.isTrue(module.hasSampleRecords(), 'The card sees them');
            Grant__c awarded = [
                SELECT Amount_Awarded__c, Decision_Date__c
                FROM Grant__c
                WHERE Stage__c = :GrantService.STAGE_AWARDED
            ];
            Assert.areEqual(35000, awarded.Amount_Awarded__c, 'The award is filled in');
            Assert.areEqual(
                3,
                [
                    SELECT COUNT()
                    FROM Grant_Requirement__c
                    WHERE Grant__c = :awarded.Id
                    WITH SYSTEM_MODE
                ],
                'The award has its three requirements'
            );
        }
    }

    @IsTest
    static void eachStageIsLoadedAndTheRemovalLeavesRealGrants() {
        System.runAs(admin()) {
            sampleOrganizations();
            Account real = GrantTestData.funder('Real Foundation');
            insert GrantTestData.grant('Real grant', real.Id, GrantService.STAGE_PROSPECT);

            Test.startTest();
            loadEverything();
            Map<String, Integer> byStage = new Map<String, Integer>();
            for (Grant__c grant : [SELECT Stage__c FROM Grant__c WHERE Sample_Data__c = TRUE]) {
                Integer seen = byStage.get(grant.Stage__c);
                byStage.put(grant.Stage__c, seen == null ? 1 : seen + 1);
            }
            removeEverything();
            Test.stopTest();

            Assert.areEqual(
                new Map<String, Integer>{
                    GrantService.STAGE_PROSPECT => 1,
                    GrantService.STAGE_APPLIED => 1,
                    GrantService.STAGE_AWARDED => 1
                },
                byStage,
                'One grant at each point of the pipeline'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Grant__c WHERE Sample_Data__c = TRUE]);
            Assert.areEqual(1, [SELECT COUNT() FROM Grant__c], 'The real grant stays');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Grant_Requirement__c WITH SYSTEM_MODE],
                'The sample requirements went with their grant'
            );
        }
    }

    @IsTest
    static void coreFindsTheModuleAndNothingLoadsWithoutSampleOrganizations() {
        System.runAs(admin()) {
            Object built = Type.forName('FundersSampleData').newInstance();
            Assert.isTrue(built instanceof SampleDataModule, 'Core builds it by its name.');
            FundersSampleData module = (FundersSampleData) built;
            Assert.areEqual('Funders', module.moduleName(), 'The name startAfter looks for.');
            Assert.isFalse(String.isBlank(module.countLabel()), 'The card has its wording.');
            Assert.areEqual(
                'FundersSampleData.LoadStages',
                new FundersSampleData.LoadStages().name()
            );
            Assert.areEqual(
                'FundersSampleData.RemoveStages',
                new FundersSampleData.RemoveStages().name()
            );

            Test.startTest();
            loadEverything();
            new FundersSampleData.LoadStages().finish();
            new FundersSampleData.RemoveStages().finish();
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Grant__c],
                'No sample organizations, no grants'
            );
            Assert.isFalse(module.hasSampleRecords());
        }
    }

    @IsTest
    static void enqueueLoadAndRemoveStartCoresBatches() {
        System.runAs(admin()) {
            Test.startTest();
            new FundersSampleData().enqueueLoad();
            new FundersSampleData().enqueueRemove();
            Test.stopTest();

            Assert.isTrue(
                [
                    SELECT COUNT()
                    FROM AsyncApexJob
                    WHERE ApexClass.Name IN ('SampleDataStageBatch', 'SampleDataRemoveBatch')
                ] >= 2,
                'Both run in Core\'s batches.'
            );
        }
    }
}
