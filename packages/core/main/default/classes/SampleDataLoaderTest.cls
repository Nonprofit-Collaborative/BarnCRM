/**
 * Tests SampleDataLoader and the two load stages against a small inline JSON payload
 * injected through the @TestVisible jsonOverride hook, so the tests never depend on the
 * real SampleData static resource or its size.
 *
 * The stages are called directly (SampleDataLoadQueueable.loadHouseholdsAndOrganizations
 * and loadContactChunk) rather than through the queueable chain, because an Apex test
 * context runs only the first enqueued job. One test still enqueues the first queueable
 * inside Test.startTest and Test.stopTest and asserts stage one's effects only.
 */
@IsTest
private class SampleDataLoaderTest {
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

    /** Runs both stages in order, the way the queueable chain does in an org. */
    private static SampleDataSet loadEverything(String jsonBody) {
        SampleDataSet data = SampleDataSet.parse(jsonBody);
        SampleDataLoadQueueable.loadHouseholdsAndOrganizations(data);
        for (Integer chunk = 0; chunk < data.chunkCount(); chunk++) {
            SampleDataLoadQueueable.loadContactChunk(data, chunk);
        }
        return data;
    }

    /** Runs all three stages, the way the whole chain does in an org. */
    private static SampleDataSet loadEverythingIncludingConnections(String jsonBody) {
        SampleDataSet data = loadEverything(jsonBody);
        SampleDataConnectionQueueable.loadConnections(data);
        return data;
    }

    /**
     * A module sample data set that records what Core asked it to do, standing in for the
     * Giving implementation, which Core cannot compile against.
     */
    private class StubModule implements SampleDataModule {
        private Integer loaded;
        private Integer removeCalls = 0;

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

        public void enqueueLoad() {
            // Nothing to start: what Core does with a module's load is asserted in
            // SampleDataModulesTest, and these tests are about the remove path.
            return;
        }

        public Integer removeNext() {
            removeCalls++;
            Integer removed = loaded;
            loaded = 0;
            return removed;
        }
    }

    /**
     * Starts the remove, then runs every chunk of the chain in this transaction, the way the
     * chain's jobs run one after another in an org. Returns what remove() answered.
     */
    private static SampleDataLoader.Counts removeEverything() {
        SampleDataLoader.Counts started = SampleDataLoader.remove();
        Integer chunks = 0;
        while (SampleDataLoader.removeNextChunk()) {
            chunks++;
            System.assert(chunks < 50, 'the remove chain ends');
        }
        return started;
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
    static void testFirstQueueableRunsTheHouseholdStage() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            // The only chaining-dependent assertion the platform allows: a test context runs
            // the first enqueued job and nothing it enqueues, so only stage one's effects
            // exist afterwards.
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
                'the contact stage is a second queueable, which a test context does not run'
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

            SampleDataLoadQueueable.loadHouseholdsAndOrganizations(data);

            System.assertEquals(
                100,
                SampleDataLoadQueueable.loadContactChunk(data, 0),
                'the first chunk should insert a full 100 contacts'
            );
            System.assertEquals(
                100,
                SampleDataLoadQueueable.loadContactChunk(data, 1),
                'the second chunk should insert a full 100 contacts'
            );
            System.assertEquals(
                50,
                SampleDataLoadQueueable.loadContactChunk(data, 2),
                'the last chunk should insert the remaining 50 contacts'
            );
            System.assertEquals(
                0,
                SampleDataLoadQueueable.loadContactChunk(data, 3),
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
    static void testRemoveInJunctionModeTakesTheMembershipRowsWithIt() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            SettingsService.clearCaches();
            loadEverything(buildJson(2, 2, false));

            SampleDataLoader.Counts removed = removeEverything();

            System.assertEquals(2, removed.householdCount, 'both sample households are removed');
            System.assertEquals(4, removed.contactCount, 'every sample person is removed');
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
    static void testRemoveStartsAChainThatDeletesOneChunkPerJob() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));

            Test.startTest();
            SampleDataLoader.Counts started = SampleDataLoader.remove();
            Test.stopTest();

            System.assertEquals(true, started.removing, 'the card is told the remove is running');
            System.assertEquals(false, started.loaded, 'and not to offer Load or Remove meanwhile');
            System.assertEquals(1, started.householdCount, 'it answers the counts as they stood');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE],
                'the first job deleted the first chunk, the people'
            );
        }
    }

    @IsTest
    static void testRemoveDeletesTwoHundredPeopleInChunks() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            Account sampleOrganization = new Account(Name = 'Sample org', Sample_Data__c = true);
            insert sampleOrganization;
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 200; i++) {
                people.add(
                    new Contact(
                        LastName = 'Sample' + i,
                        AccountId = sampleOrganization.Id,
                        Sample_Data__c = true
                    )
                );
            }
            insert people;

            Test.startTest();
            Boolean first = SampleDataLoader.removeNextChunk();
            Integer afterFirst = [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE];
            Boolean second = SampleDataLoader.removeNextChunk();
            Integer afterSecond = [SELECT COUNT() FROM Contact WHERE Sample_Data__c = TRUE];
            Boolean third = SampleDataLoader.removeNextChunk();
            Boolean fourth = SampleDataLoader.removeNextChunk();
            Test.stopTest();

            System.assert(first && second && third, 'each chunk reports that it deleted something');
            System.assertEquals(
                200 - SampleDataLoader.REMOVE_CHUNK_SIZE,
                afterFirst,
                'one chunk deletes one chunk of people'
            );
            System.assertEquals(0, afterSecond, 'the second deletes the rest');
            System.assertEquals(
                0,
                [SELECT COUNT() FROM Account WHERE Id = :sampleOrganization.Id],
                'the accounts go once the people are gone'
            );
            System.assertEquals(false, fourth, 'then the chain stops');
        }
    }

    @IsTest
    static void testLoadAndRemoveRefuseWhileARemoveIsRunning() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(1, 1, false));
            SampleDataLoader.runningJobOverride = false;
            SampleDataLoader.runningRemoveOverride = true;

            String loadMessage;
            try {
                SampleDataLoader.load();
            } catch (SampleDataException e) {
                loadMessage = e.getMessage();
            }
            String removeMessage;
            try {
                SampleDataLoader.remove();
            } catch (SampleDataException e) {
                removeMessage = e.getMessage();
            }
            SampleDataLoader.Counts status = SampleDataLoader.status();

            System.assertEquals(Label.Core_SampleData_RemoveInProgress, loadMessage);
            System.assertEquals(Label.Core_SampleData_RemoveInProgress, removeMessage);
            System.assertEquals(true, status.removing, 'status says the remove is running');
            System.assertEquals(false, status.loaded, 'a set being removed is not loaded');
        }
    }

    @IsTest
    static void testRemoveDeletesEverythingFlagged() {
        System.runAs(TestUsers.adminWithInstalledModules()) {
            loadEverything(buildJson(2, 2, false));

            SampleDataLoader.Counts removed = removeEverything();
            System.assertEquals(2, removed.householdCount);
            System.assertEquals(1, removed.organizationCount);
            System.assertEquals(4, removed.contactCount);

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

            removeEverything();

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

            SampleDataLoader.Counts removed = removeEverything();

            System.assert(
                module.removeCalls > 1,
                'the module is asked again until it answers that nothing is left'
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
}
