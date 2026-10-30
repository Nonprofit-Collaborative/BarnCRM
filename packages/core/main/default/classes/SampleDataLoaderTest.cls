/**
 * Tests SampleDataLoader and the two load stages against a small inline JSON payload
 * injected through the @TestVisible jsonOverride hook, so the tests never depend on the
 * real SampleData static resource or its size.
 *
 * The stages are called directly (SampleDataLoadStages.loadHouseholdsAndOrganizations
 * and loadContactChunk) rather than through the stage batch, because an Apex test context
 * runs only one execute of a batch. One test still starts the batch inside Test.startTest
 * and Test.stopTest and asserts stage one's effects only. SampleDataStageBatchTest covers
 * the stage sequence and the hand-offs.
 */
@IsTest(testFor='ApexClass:SampleDataLoader')
private class SampleDataLoaderTest {
    @TestSetup
    static void createTestUser() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            AccountKindsTestData.useRecordTypeTheUserCanUse();
        }
    }

    /**
     * Builds a minimal but structurally faithful sample data JSON string: householdCount
     * households, each with membersPerHousehold members, plus one organization. When
     * customNameFirst is true the first household carries a custom name so both the
     * computed-name and custom-name insert paths are exercised across the suite.
     */
    private static String buildJson(
        Integer householdCount,
        Integer membersPerHousehold,
        Boolean customNameFirst
    ) {
        List<Object> households = new List<Object>();
        Integer emailIndex = 1;

        for (Integer h = 0; h < householdCount; h++) {
            Boolean isCustomName = customNameFirst && h == 0;
            List<Object> members = new List<Object>();
            for (Integer m = 0; m < membersPerHousehold; m++) {
                Map<String, Object> member = buildMember(h, m, emailIndex);
                if (h == 0 && m == membersPerHousehold - 1) {
                    member.put('deceased', true);
                }
                members.add(member);
                emailIndex++;
            }
            households.add(buildHousehold(h, isCustomName, members));
        }

        Map<String, Object> root = new Map<String, Object>();
        root.put('households', households);
        root.put('organizations', new List<Object>{ buildOrganization() });
        return JSON.serialize(root);
    }

    private static Map<String, Object> buildMember(
        Integer householdIndex,
        Integer memberIndex,
        Integer emailIndex
    ) {
        Map<String, Object> member = new Map<String, Object>();
        member.put('key', 'H' + householdIndex + '-' + (memberIndex + 1));
        member.put('firstName', 'Test' + emailIndex);
        member.put('lastName', 'Household' + householdIndex);
        member.put('salutation', 'Mr.');
        member.put('householdRole', memberIndex == 0 ? 'Head' : 'Other');
        member.put('email', 'test' + emailIndex + '@example.org');
        member.put('phone', '(555) 555-0100');
        member.put('mailingStreet', '1 Test St');
        member.put('mailingCity', 'Testville');
        member.put('mailingState', 'CA');
        member.put('mailingPostalCode', '90000');
        member.put('birthdate', '1980-01-01');
        if (memberIndex == 0) {
            member.put('preferredName', 'Testy');
        }
        return member;
    }

    private static Map<String, Object> buildHousehold(
        Integer householdIndex,
        Boolean isCustomName,
        List<Object> members
    ) {
        Map<String, Object> address = new Map<String, Object>();
        address.put('street', '1 Test St');
        address.put('city', 'Testville');
        address.put('state', 'CA');
        address.put('postalCode', '90000');

        Map<String, Object> household = new Map<String, Object>();
        household.put('key', 'H' + householdIndex);
        household.put('customName', isCustomName);
        household.put('name', isCustomName ? 'The Test Family' : null);
        household.put('anniversary', isCustomName ? '2001-06-01' : null);
        household.put('address', address);
        household.put('members', members);
        return household;
    }

    private static Map<String, Object> buildOrganization() {
        Map<String, Object> organization = new Map<String, Object>();
        organization.put('key', 'O1');
        organization.put('name', 'Test Foundation');
        organization.put('website', 'https://www.example.org');
        organization.put('phone', '(555) 555-0199');
        return organization;
    }

    /**
     * The same payload as buildJson, with one connection between people in two different
     * households and one affiliation to the organization, so the third stage has work to do.
     */
    private static String buildJsonWithConnections() {
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
            buildJson(2, 2, false)
        );

        Map<String, Object> relationship = new Map<String, Object>();
        relationship.put('person', 'H0-1');
        relationship.put('relatedPerson', 'H1-1');
        relationship.put('type', 'Friend');
        relationship.put('status', 'Current');
        relationship.put('startDate', '2020-04-01');
        relationship.put('description', 'Met through the volunteer programme.');

        Map<String, Object> affiliation = new Map<String, Object>();
        affiliation.put('person', 'H0-1');
        affiliation.put('organization', 'O1');
        affiliation.put('role', 'Board Member');
        affiliation.put('status', 'Current');
        affiliation.put('isPrimary', true);
        affiliation.put('startDate', '2019-01-15');

        root.put('relationships', new List<Object>{ relationship });
        root.put('affiliations', new List<Object>{ affiliation });
        return JSON.serialize(root);
    }

    /** Runs both stages in order, the way the stage batch does in an org. */
    private static SampleDataSet loadEverything(String jsonBody) {
        SampleDataSet data = SampleDataSet.parse(jsonBody);
        SampleDataLoadStages.loadHouseholdsAndOrganizations(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            SampleDataLoadStages.loadContactChunk(data, chunk);
        }
        return data;
    }

    /** Runs all three stages, the way the whole stage batch does in an org. */
    private static SampleDataSet loadEverythingIncludingConnections(String jsonBody) {
        SampleDataSet data = loadEverything(jsonBody);
        SampleDataConnections.loadConnections(data);
        return data;
    }

    /**
     * A module sample data set that records what Core asked it to do, standing in for the
     * Giving implementation, which Core cannot compile against.
     */
    private class StubModule implements SampleDataModule {
        private Integer loaded;
        private Integer removeCalls = 0;
        /** Sample records the module's removal kept, as Volunteers keeps ones real records use. */
        private Boolean keptSome = false;

        private StubModule(Integer loaded) {
            this.loaded = loaded;
        }

        public String moduleName() {
            return 'Stub';
        }

        public String countLabel() {
            return 'Stub records';
        }

        public Integer countLoaded() {
            return loaded;
        }

        public Boolean hasSampleRecords() {
            return loaded > 0 || keptSome;
        }

        public void enqueueLoad() {
            // Nothing to start: what Core does with a module's load is asserted in
            // SampleDataModulesTest, and these tests are about the remove path.
            return;
        }

        public void enqueueRemove() {
            removeCalls++;
            loaded = 0;
        }
    }

    /** Runs every stage of Core's removal in order, the way the removal batch does in an org. */
    private static void runCoreRemoval() {
        SampleDataRemoveStages stages = new SampleDataRemoveStages();
        Integer count = stages.stageCount();
        for (Integer stage = 0; stage < count; stage++) {
            stages.runStage(stage);
        }
    }

    @IsTest
    static void testStagesInsertHouseholdsOrganizationsAndContacts() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(3, 2, true));

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(3, status.householdCount, 'three households should be inserted');
            System.assertEquals(1, status.organizationCount, 'one organization should be inserted');
            System.assertEquals(6, status.contactCount, 'three households of two members each');
            System.assertEquals(
                true,
                status.loaded,
                'status should report loaded once both stages run'
            );
            System.assertEquals(false, status.loading, 'no load job should still be queued');
        }
    }

    @IsTest
    static void testLoadBatchRunsTheHouseholdStage() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // The only batch-dependent assertion the platform allows: a test context runs one
            // execute of a batch, so only stage one's effects exist afterwards.
            SampleDataLoader.jsonOverride = buildJson(2, 2, false);

            Test.startTest();
            SampleDataLoader.load();
            Test.stopTest();

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(2, status.householdCount, 'stage one should insert the households');
            System.assertEquals(
                1,
                status.organizationCount,
                'stage one should insert the organization'
            );
            System.assertEquals(
                0,
                status.contactCount,
                'the contact stage is a second batch execute, which a test context does not run'
            );
        }
    }

    @IsTest
    static void testContactChunksAtOneHundred() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // Five households of fifty members each: 250 contacts, three chunks of 100, 100
            // and 50, matching the governor-limit rule in plan Section 7.2.
            SampleDataSet data = SampleDataSet.parse(buildJson(5, 50, false));
            System.assertEquals(250, data.members.size(), 'the payload should hold 250 members');
            System.assertEquals(3, data.chunkCount(), '250 contacts should need three chunks');

            SampleDataLoadStages.loadHouseholdsAndOrganizations(data);

            System.assertEquals(
                100,
                SampleDataLoadStages.loadContactChunk(data, 0),
                'the first chunk should insert a full 100 contacts'
            );
            System.assertEquals(
                100,
                SampleDataLoadStages.loadContactChunk(data, 1),
                'the second chunk should insert a full 100 contacts'
            );
            System.assertEquals(
                50,
                SampleDataLoadStages.loadContactChunk(data, 2),
                'the last chunk should insert the remaining 50 contacts'
            );
            System.assertEquals(
                0,
                SampleDataLoadStages.loadContactChunk(data, 3),
                'a chunk past the end should insert nothing'
            );

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(5, status.householdCount);
            System.assertEquals(250, status.contactCount, 'all 250 contacts should be inserted');
            System.assertEquals(true, status.loaded);
        }
    }

    @IsTest
    static void testLoadThrowsWhenAlreadyLoaded() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            SampleDataLoader.jsonOverride = buildJson(1, 1, false);

            Boolean threw = false;
            try {
                SampleDataLoader.load();
            } catch (SampleDataException e) {
                threw = true;
                System.assertEquals(
                    Label.Core_SampleData_AlreadyLoaded,
                    e.getMessage(),
                    'the already-loaded error should use the packaged label'
                );
            }
            System.assertEquals(true, threw, 'loading twice should throw SampleDataException');
        }
    }

    @IsTest
    static void testLoadRefusesWhenTheUserCannotUseTheOrganizationRecordType() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = buildJson(1, 1, false);
            AccountKinds.usableOverride = false;

            String message;
            try {
                SampleDataLoader.load();
            } catch (SampleDataException e) {
                message = e.getMessage();
            }
            System.assertEquals(
                String.format(
                    Label.Core_SampleData_OrganizationRecordTypeUnavailable,
                    new List<String>{ AccountKinds.organizationRecordTypeLabel() }
                ),
                message,
                'the admin is told which record type and how to fix it, before any job starts'
            );
            System.assertEquals(
                false,
                SampleDataLoader.hasRunningLoadJob(),
                'no load job is started'
            );
        }
    }

    @IsTest
    static void testJunctionModeJoinsEveryPersonWithAMembershipRow() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            SettingsService.clearCaches();

            loadEverything(buildJson(2, 2, false));

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(2, status.householdCount, 'both households should be inserted');
            System.assertEquals(
                4,
                status.contactCount,
                'both households of two people should load'
            );
            System.assertEquals(
                4,
                [SELECT COUNT() FROM Household_Member__c WHERE End_Date__c = NULL],
                'every sample person should be joined by a household member record'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE AND AccountId != NULL],
                'in junction mode the membership row is the join, not the contact household field'
            );
            for (Account household : [
                SELECT Member_Count__c
                FROM Account
                WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Household'
            ]) {
                System.assertEquals(
                    2,
                    household.Member_Count__c,
                    'the household counts the people the membership rows joined to it'
                );
            }
        }
    }

    @IsTest
    static void testJunctionModeIsReportedToTheCard() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            SettingsService.clearCaches();

            System.assertEquals(
                true,
                SampleDataLoader.status().junctionMembership,
                'the card is told the org keeps membership in household member records'
            );
        }
    }

    @IsTest
    static void testContactModeIsStillJoinedThroughTheContactHousehold() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            SettingsService.clearCaches();

            loadEverything(buildJson(2, 2, false));

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'contact membership writes no membership rows (R-M1)'
            );
            System.assertEquals(
                4,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE AND AccountId != NULL],
                'every sample person is on their household'
            );
            System.assertEquals(
                false,
                SampleDataLoader.status().junctionMembership,
                'the card is told this org keeps membership on the contact'
            );
        }
    }

    @IsTest
    static void testEverySampleHouseholdStartsWithItsFirstPersonAsPrimaryContact() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            SettingsService.clearCaches();

            Test.startTest();
            loadEverything(buildJson(3, 2, false));
            Test.stopTest();

            List<Account> households = [
                SELECT Id, Primary_Contact__r.Sample_Data_Key__c, Primary_Contact__r.AccountId
                FROM Account
                WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Household'
            ];
            System.assertEquals(3, households.size(), 'three sample households');
            for (Account household : households) {
                System.assert(
                    household.Primary_Contact__r != null &&
                    household.Primary_Contact__r.Sample_Data_Key__c.endsWith('-1'),
                    'the first person in the file is the Primary Contact, as a household made ' +
                        'by adding its first person has: ' +
                        household
                );
                System.assertEquals(
                    household.Id,
                    household.Primary_Contact__r.AccountId,
                    'and is one of its members'
                );
            }
        }
    }

    @IsTest
    static void testSampleHouseholdsArriveNamedWhileHouseholdUpkeepIsOff() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // A new install: no feature on, so the household triggers do not run.
            TestSettings.newInstall();
            Assert.isFalse(
                FeatureSwitchService.isOn(FeatureSwitchService.HOUSEHOLD_UPKEEP),
                'Household Upkeep is off for this test'
            );

            Test.startTest();
            loadEverything(buildJson(2, 2, false));
            Test.stopTest();

            List<Account> households = [
                SELECT
                    Name,
                    Member_Count__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c
                FROM Account
                WHERE Sample_Data__c = TRUE AND RecordType.DeveloperName = 'Household'
            ];
            Assert.areEqual(2, households.size(), 'two sample households');
            for (Account household : households) {
                Assert.areNotEqual('Household', household.Name, 'named from its people');
                Assert.areEqual(2, household.Member_Count__c, 'both people counted');
                Assert.isTrue(
                    String.isNotBlank(household.Household_Formal_Greeting__c),
                    'a formal greeting is set'
                );
                Assert.isTrue(
                    String.isNotBlank(household.Household_Informal_Greeting__c),
                    'an informal greeting is set'
                );
            }
        }
    }

    @IsTest
    static void testCustomNamedSampleHouseholdKeepsItsNameAndGetsGreetings() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // Upkeep off: the case QA v15 found, a custom-named household with no greetings.
            TestSettings.newInstall();

            Test.startTest();
            loadEverything(buildJson(2, 2, true));
            Test.stopTest();

            Account custom = [
                SELECT
                    Name,
                    Member_Count__c,
                    Household_Formal_Greeting__c,
                    Household_Informal_Greeting__c
                FROM Account
                WHERE Sample_Data_Key__c = 'H0'
            ];
            Assert.areEqual('The Test Family', custom.Name, 'a custom name is kept (R-H8)');
            Assert.areEqual(2, custom.Member_Count__c, 'its people are counted');
            Assert.isTrue(
                String.isNotBlank(custom.Household_Formal_Greeting__c),
                'it has a formal greeting'
            );
            Assert.isTrue(
                String.isNotBlank(custom.Household_Informal_Greeting__c),
                'it has an informal greeting'
            );
        }
    }

    @IsTest
    static void testRemoveInJunctionModeTakesTheMembershipRowsWithIt() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            SettingsService.clearCaches();
            loadEverything(buildJson(2, 2, false));

            SampleDataLoader.Counts before = SampleDataLoader.status();
            System.assertEquals(2, before.householdCount, 'both sample households are loaded');
            System.assertEquals(4, before.contactCount, 'every sample person is loaded');

            runCoreRemoval();

            System.assertEquals(
                0,
                [SELECT COUNT() FROM Household_Member__c],
                'the membership rows go with the households they belonged to'
            );
            SampleDataLoader.Counts afterStatus = SampleDataLoader.status();
            System.assertEquals(0, afterStatus.householdCount);
            System.assertEquals(0, afterStatus.contactCount);
            System.assertEquals(false, afterStatus.loaded);
        }
    }

    @IsTest
    static void testLoadRefusesWhileALoadIsRunning() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.jsonOverride = buildJson(1, 1, false);
            SampleDataLoader.runningJobOverride = true;

            Boolean threw = false;
            try {
                SampleDataLoader.load();
            } catch (SampleDataException e) {
                threw = true;
                System.assertEquals(
                    Label.Core_SampleData_LoadInProgress,
                    e.getMessage(),
                    'a second load should be refused with the load-in-progress label'
                );
            }
            System.assertEquals(true, threw, 'loading during a running load should throw');
        }
    }

    @IsTest
    static void testLoadAndRemoveRefuseWhileARemovalIsRunning() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            SampleDataLoader.runningRemoveOverride = true;

            Integer refused = 0;
            try {
                SampleDataLoader.remove();
            } catch (SampleDataException e) {
                refused++;
                System.assertEquals(Label.Core_SampleData_RemoveInProgress, e.getMessage());
            }
            try {
                SampleDataLoader.load();
            } catch (SampleDataException e) {
                refused++;
                System.assertEquals(Label.Core_SampleData_RemoveInProgress, e.getMessage());
            }
            System.assertEquals(2, refused, 'neither starts while a removal runs');

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(true, status.removing, 'the card is told a removal is running');
            System.assertEquals(false, status.loaded, 'a removal in progress is not loaded');
            System.assertEquals(1, status.householdCount, 'the refused calls delete nothing');
        }
    }

    @IsTest
    static void testRemoveRefusesWhileALoadIsRunning() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            SampleDataLoader.runningJobOverride = true;

            Boolean threw = false;
            try {
                SampleDataLoader.remove();
            } catch (SampleDataException e) {
                threw = true;
                System.assertEquals(
                    Label.Core_SampleData_LoadInProgress,
                    e.getMessage(),
                    'removing during a load should be refused with the load-in-progress label'
                );
            }
            System.assertEquals(true, threw, 'removing during a running load should throw');

            SampleDataLoader.runningJobOverride = false;
            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(
                1,
                status.householdCount,
                'the refused remove should delete nothing'
            );
        }
    }

    @IsTest
    static void testStatusReportsLoadingWhileAJobRuns() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            SampleDataLoader.runningJobOverride = true;

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(true, status.loading, 'status should report a running load');
            System.assertEquals(false, status.loaded, 'a running load is not a finished load');
        }
    }

    @IsTest
    static void testRemoveDeletesEverythingFlagged() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(2, 2, false));
            // An org with Giving installed would hand the removal to Giving first.
            SampleDataModules.moduleOverride = new List<SampleDataModule>();

            Test.startTest();
            SampleDataLoader.Counts removed = SampleDataLoader.remove();
            Test.stopTest();
            System.assertEquals(2, removed.householdCount);
            System.assertEquals(1, removed.organizationCount);
            System.assertEquals(4, removed.contactCount);
            System.assertEquals(true, removed.removing, 'the card is told the removal started');
            System.assertEquals(false, removed.loaded);
            System.assertEquals(
                true,
                SampleDataStageBatch.started[0] instanceof SampleDataRemoveStages,
                'with no module installed the batch runs Core\'s own removal stages'
            );

            // A test runs one stage of the batch; run the rest the way the batch does in an org.
            runCoreRemoval();

            SampleDataLoader.Counts afterStatus = SampleDataLoader.status();
            System.assertEquals(
                0,
                afterStatus.householdCount,
                'households should be gone after remove'
            );
            System.assertEquals(
                0,
                afterStatus.organizationCount,
                'organizations should be gone after remove'
            );
            System.assertEquals(
                0,
                afterStatus.contactCount,
                'contacts should be gone after remove'
            );
            System.assertEquals(false, afterStatus.loaded);
        }
    }

    @IsTest
    static void testRemoveLeavesRecordsTheLoaderDidNotCreate() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverythingIncludingConnections(buildJsonWithConnections());
            Account ownRecord = new Account(Name = 'A real household');
            insert ownRecord;
            Contact ownPerson = new Contact(LastName = 'Real', AccountId = ownRecord.Id);
            insert ownPerson;
            Contact ownOtherPerson = new Contact(LastName = 'Alsoreal', AccountId = ownRecord.Id);
            insert ownOtherPerson;
            Relationship__c ownRelationship = new Relationship__c(
                Contact__c = ownPerson.Id,
                Related_Contact__c = ownOtherPerson.Id,
                Type__c = 'Friend',
                Status__c = 'Current'
            );
            insert ownRelationship;
            Affiliation__c ownAffiliation = new Affiliation__c(
                Contact__c = ownPerson.Id,
                Organization__c = ownRecord.Id,
                Role__c = 'Board Member',
                Status__c = 'Current'
            );
            insert ownAffiliation;

            runCoreRemoval();

            System.assertEquals(
                1,
                [SELECT COUNT() FROM Account WHERE Id = :ownRecord.Id],
                'a household the admin entered is not touched'
            );
            System.assertEquals(
                2,
                [SELECT COUNT() FROM Contact WHERE Id IN (:ownPerson.Id, :ownOtherPerson.Id)],
                'people the admin entered are not touched'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Relationship__c WHERE Id = :ownRelationship.Id],
                'a connection the admin entered is not touched'
            );
            System.assertEquals(
                1,
                [SELECT COUNT() FROM Affiliation__c WHERE Id = :ownAffiliation.Id],
                'an affiliation the admin entered is not touched'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Relationship__c WHERE Sample_Data__c = TRUE],
                'every connection the loader created is gone'
            );
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Affiliation__c WHERE Sample_Data__c = TRUE],
                'every affiliation the loader created is gone'
            );
        }
    }

    @IsTest
    static void testConnectionStageLoadsRelationshipsAndAffiliations() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverythingIncludingConnections(buildJsonWithConnections());

            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(
                1,
                status.relationshipCount,
                'the payload names one connection between two households'
            );
            System.assertEquals(1, status.affiliationCount, 'the payload names one affiliation');

            Relationship__c saved = [
                SELECT Contact__c, Related_Contact__c, Type__c, Sample_Data__c
                FROM Relationship__c
                WHERE Sample_Data__c = TRUE
                LIMIT 1
            ];
            System.assertEquals(
                'Friend',
                saved.Type__c,
                'the connection keeps the type it was given'
            );
            System.assertNotEquals(
                saved.Contact__c,
                saved.Related_Contact__c,
                'a connection joins two different people'
            );

            Affiliation__c affiliation = [
                SELECT Contact__c, Organization__c, Role__c
                FROM Affiliation__c
                WHERE Sample_Data__c = TRUE
                LIMIT 1
            ];
            System.assertEquals(
                'Board Member',
                affiliation.Role__c,
                'the affiliation keeps the role it was given'
            );
            System.assertNotEquals(
                null,
                affiliation.Organization__c,
                'the affiliation found the sample organization by its key'
            );
        }
    }

    @IsTest
    static void testEveryPersonAndHouseholdKeepsItsGeneratorKey() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(2, 2, false));

            System.assertEquals(
                2,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c LIKE 'H%'
                ],
                'each household carries the key the generator gave it'
            );
            System.assertEquals(
                4,
                [
                    SELECT COUNT()
                    FROM Contact
                    WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c != NULL
                ],
                'each person carries the key a module sample set finds them by'
            );
            System.assertEquals(
                1,
                [
                    SELECT COUNT()
                    FROM Account
                    WHERE Sample_Data__c = TRUE AND Sample_Data_Key__c = 'O1'
                ],
                'the organization carries its own key'
            );
        }
    }

    @IsTest
    static void testRemoveAsksEveryModuleToRemoveItsOwnRecords() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            StubModule module = new StubModule(12);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ module };

            Test.startTest();
            SampleDataLoader.Counts removed = SampleDataLoader.remove();
            Test.stopTest();

            System.assertEquals(
                1,
                module.removeCalls,
                'the module is asked once to remove its own'
            );
            System.assertEquals(
                0,
                SampleDataStageBatch.started.size(),
                'Core\'s own removal waits for the module to hand back'
            );
            System.assertEquals(
                1,
                removed.moduleCounts.size(),
                'the counts returned name the module that was removed'
            );
            System.assertEquals(
                12,
                removed.moduleCounts[0].recordCount,
                'the count reported is what the module held before it was emptied'
            );
            System.assertEquals(
                0,
                SampleDataLoader.status().moduleCounts[0].recordCount,
                'the module has nothing left after the remove'
            );
        }
    }

    @IsTest
    static void testStatusReportsEachModuleCountWithItsOwnLabel() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ new StubModule(709) };

            SampleDataLoader.Counts status = SampleDataLoader.status();

            System.assertEquals(1, status.moduleCounts.size(), 'one installed module is reported');
            System.assertEquals('Stub', status.moduleCounts[0].name);
            System.assertEquals(
                'Stub records',
                status.moduleCounts[0].label,
                'the card is given the module its own wording for the number'
            );
            System.assertEquals(709, status.moduleCounts[0].recordCount);
        }
    }

    @IsTest
    static void testStatusReportsNotLoadedBeforeAnyLoad() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            SampleDataLoader.Counts status = SampleDataLoader.status();
            System.assertEquals(0, status.householdCount);
            System.assertEquals(0, status.organizationCount);
            System.assertEquals(0, status.contactCount);
            System.assertEquals(false, status.loaded);
            System.assertEquals(false, status.loading);
        }
    }

    @IsTest
    static void testRemoveStaysOfferedWhileAModuleKeptSampleRecords() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            StubModule module = new StubModule(12);
            SampleDataModules.moduleOverride = new List<SampleDataModule>{ module };
            SampleDataLoader.remove();
            runCoreRemoval();
            module.keptSome = true;

            SampleDataLoader.Counts status = SampleDataLoader.status();
            Assert.areEqual(0, status.householdCount, 'Core\'s own sample records are gone');
            Assert.isTrue(
                status.loaded,
                'Still loaded while the module kept some, so Remove sample data stays offered'
            );
            SampleDataLoader.jsonOverride = buildJson(1, 1, false);
            try {
                SampleDataLoader.load();
                Assert.fail('A load is refused while a module still has sample records');
            } catch (SampleDataException refused) {
                Assert.areEqual(Label.Core_SampleData_AlreadyLoaded, refused.getMessage());
            }

            module.keptSome = false;
            Assert.isFalse(
                SampleDataLoader.status().loaded,
                'Not loaded once the admin has dealt with what the module kept'
            );
        }
    }
}
