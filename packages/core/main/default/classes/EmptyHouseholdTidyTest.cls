/**
 * The nightly empty household tidy-up (R-H12a, ADR-0120, D-89): a household emptied by deleting
 * people is stamped, kept while any of its former members can still be restored, kept for good
 * while anything points at it, and otherwise moved to the Recycle Bin; nothing happens when the
 * org keeps those households.
 */
@IsTest(testFor='ApexClass:EmptyHouseholdTidyBatch, ApexClass:EmptyHouseholdTidyScheduler')
private class EmptyHouseholdTidyTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    /** A contact-mode person in a household of their own, deleted. Answers the household. */
    private static Id deletedPersonsHousehold(Contact person) {
        insert person;
        Id household = [SELECT AccountId FROM Contact WHERE Id = :person.Id].AccountId;
        delete person;
        return household;
    }

    /**
     * Empties these records from the Recycle Bin. A test still reads them with ALL ROWS
     * afterwards, as an org does until the platform removes them physically, so the tidy-up is
     * also told they are gone.
     */
    private static void purge(List<Id> recordIds) {
        Database.emptyRecycleBin(recordIds);
        EmptyHouseholdTidyBatch.purgedForTest.addAll(recordIds);
    }

    private static void runTidyUp() {
        Test.startTest();
        Database.executeBatch(new EmptyHouseholdTidyBatch(), EmptyHouseholdTidyBatch.CHUNK_SIZE);
        Test.stopTest();
    }

    private static Boolean isInRecycleBin(Id accountId) {
        return [SELECT IsDeleted FROM Account WHERE Id = :accountId ALL ROWS].IsDeleted;
    }

    private static void contactMode() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
        HouseholdDependentsExtensions.noneForTest = true;
    }

    @IsTest
    static void aHouseholdWhoseDeletedMemberIsPurgedIsMovedToTheRecycleBin() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            Assert.areEqual(
                Date.today(),
                [SELECT Emptied_By_Deletion__c FROM Account WHERE Id = :household]
                .Emptied_By_Deletion__c,
                'The delete stamps the household it emptied'
            );
            purge(new List<Id>{ maria.Id });

            runTidyUp();

            Assert.isTrue(isInRecycleBin(household), 'Maria cannot come back, so neither stays');
        }
    }

    @IsTest
    static void aHouseholdIsKeptWhileAFormerMemberCanStillBeRestored() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'Deleting it would purge Maria (D-88)');
            undelete maria;
            Account restored = [
                SELECT Member_Count__c, Emptied_By_Deletion__c
                FROM Account
                WHERE Id = :household
            ];
            Assert.areEqual(1, restored.Member_Count__c, 'Maria comes back into her household');
            Assert.isNull(restored.Emptied_By_Deletion__c, 'A member again clears the stamp');
        }
    }

    @IsTest
    static void aHouseholdWithAChildRecordIsKeptAndStillReportedAsEmpty() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            purge(new List<Id>{ maria.Id });
            // Any record pointing at the household keeps it, whatever its object.
            Account foundation = AddressTestDataFactory.newOrganization('Garcia Foundation');
            foundation.ParentId = household;
            insert foundation;

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'A linked record keeps the household');
            Assert.areEqual(
                1,
                DataHygieneService.run(DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS).count,
                'It stays on the list of empty households to review'
            );
        }
    }

    @IsTest
    static void aHouseholdAModuleCreditsRecordsToIsKept() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            purge(new List<Id>{ maria.Id });
            HouseholdDependentsExtensions.overrides.put(
                HouseholdDependentsExtensions.EXTENSION_CLASSES[0],
                new HouseholdDependentsExtensions.EveryHouseholdDependent()
            );

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'Gifts keep their household (ADR-0070)');
        }
    }

    @IsTest
    static void nothingIsRemovedWhenTheOrgKeepsTheseHouseholds() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Keep_Households_Of_Deleted_People__c = true;
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            purge(new List<Id>{ maria.Id });

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'The setting keeps every household');
        }
    }

    @IsTest
    static void nothingIsRemovedWhileHouseholdUpkeepIsOff() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            purge(new List<Id>{ maria.Id });
            FeatureSwitchService.markNewInstall();

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'A feature that is off does no work');
        }
    }

    @IsTest
    static void aHouseholdEmptiedByAMoveIsNeverStamped() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Delete_Empty_Households__c = false;
            HouseholdTestDataFactory.save(settings);
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Account other = HouseholdTestDataFactory.newHousehold('The Lee Family');
            insert other;
            maria.AccountId = other.Id;
            update maria;

            runTidyUp();

            Account left = [
                SELECT Emptied_By_Deletion__c, IsDeleted
                FROM Account
                WHERE Id = :household
                ALL ROWS
            ];
            Assert.isNull(left.Emptied_By_Deletion__c, 'Only a delete stamps a household');
            Assert.isFalse(left.IsDeleted, 'A move is governed by Delete Empty Households');
        }
    }

    @IsTest
    static void junctionModeWaitsForTheMembershipRowsToLeaveTheRecycleBin() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            HouseholdDependentsExtensions.noneForTest = true;
            Account household = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            insert household;
            Contact luis = HouseholdTestDataFactory.newContact('Mr.', 'Luis', 'Rivera');
            insert luis;
            insert new Household_Member__c(Household__c = household.Id, Contact__c = luis.Id);
            delete luis;
            Assert.isNotNull(
                [SELECT Emptied_By_Deletion__c FROM Account WHERE Id = :household.Id]
                .Emptied_By_Deletion__c,
                'The delete stamps the household in junction mode too'
            );

            EmptyHouseholdTidyBatch tidy = new EmptyHouseholdTidyBatch();
            tidy.execute(null, new List<Account>{ new Account(Id = household.Id) });
            Assert.isFalse(isInRecycleBin(household.Id), 'His membership row is still restorable');
            Assert.areEqual(1, tidy.keptForRecycleBin, 'Kept for the Recycle Bin');

            List<Id> purged = new List<Id>{ luis.Id };
            for (Household_Member__c row : [
                SELECT Id
                FROM Household_Member__c
                WHERE Household__c = :household.Id AND IsDeleted = TRUE
                ALL ROWS
            ]) {
                purged.add(row.Id);
            }
            purge(purged);

            runTidyUp();

            Assert.isTrue(isInRecycleBin(household.Id), 'Nothing of Luis is left to restore');
        }
    }

    @IsTest
    static void anEndedMembershipOfSomebodyElseKeepsTheHouseholdInJunctionMode() {
        System.runAs(TestUsers.admin()) {
            HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
            HouseholdDependentsExtensions.noneForTest = true;
            Account household = HouseholdTestDataFactory.newHousehold('The Rivera Family');
            insert household;
            Contact luis = HouseholdTestDataFactory.newContact('Mr.', 'Luis', 'Rivera');
            Contact ana = HouseholdTestDataFactory.newContact('Ms.', 'Ana', 'Rivera');
            insert new List<Contact>{ luis, ana };
            insert new List<Household_Member__c>{
                new Household_Member__c(Household__c = household.Id, Contact__c = luis.Id),
                new Household_Member__c(
                    Household__c = household.Id,
                    Contact__c = ana.Id,
                    Start_Date__c = Date.today().addYears(-2),
                    End_Date__c = Date.today().addYears(-1)
                )
            };
            delete luis;
            List<Id> purged = new List<Id>{ luis.Id };
            for (Household_Member__c row : [
                SELECT Id
                FROM Household_Member__c
                WHERE Household__c = :household.Id AND IsDeleted = TRUE
                ALL ROWS
            ]) {
                purged.add(row.Id);
            }
            purge(purged);

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household.Id), 'Ana\'s ended membership is its history');
            Assert.areEqual(
                1,
                DataHygieneService.run(DataHygieneService.HOUSEHOLDS_WITHOUT_MEMBERS).count,
                'It stays on the list of empty households to review'
            );
        }
    }

    @IsTest
    static void ownAddressesImportRowsAndRowsOfDeletedPeopleDoNotKeepAHousehold() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            insert maria;
            Id household = [SELECT AccountId FROM Contact WHERE Id = :maria.Id].AccountId;
            Address__c home = new Address__c(
                Account__c = household,
                Type__c = 'Home',
                Street__c = '1 Main St',
                City__c = 'Springfield'
            );
            insert home;
            Import_Batch__c batch = ImportTestDataFactory.batch(
                ImportTestDataFactory.template(
                    ImportTestDataFactory.donorMapping(),
                    ImportTemplateService.RULE_EMAIL
                )
            );
            insert new Import_Row__c(
                Import_Batch__c = batch.Id,
                Row_Number__c = 2,
                Raw_Values_JSON__c = '{}',
                Household__c = household
            );
            // A membership row whose person is gone names nobody and goes with the household.
            Contact bob = HouseholdTestDataFactory.newContact('Mr.', 'Bob', 'Stone');
            insert bob;
            Household_Member__c orphan = new Household_Member__c(
                Household__c = household,
                Contact__c = bob.Id
            );
            insert orphan;
            delete new List<Contact>{ maria, bob };
            Assert.isNull(
                [SELECT Contact__c FROM Household_Member__c WHERE Id = :orphan.Id].Contact__c,
                'The row now names nobody'
            );
            purge(new List<Id>{ maria.Id, bob.Id });

            runTidyUp();

            Assert.isTrue(isInRecycleBin(household), 'Its own records do not keep it');
            Assert.isTrue(
                [SELECT IsDeleted FROM Address__c WHERE Id = :home.Id ALL ROWS].IsDeleted,
                'Its address goes to the Recycle Bin with it, not left without an owner'
            );
        }
    }

    @IsTest
    static void aChunkLargerThanTheBatchSizeIsTidiedInOneGo() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            List<Contact> people = HouseholdTestDataFactory.manyContacts(260, 'Bulk');
            insert people;
            Set<Id> householdIds = new Set<Id>();
            for (Contact person : [SELECT AccountId FROM Contact WHERE Id IN :people]) {
                householdIds.add(person.AccountId);
            }
            Assert.areEqual(260, householdIds.size(), 'Each person has a household');
            delete people;
            purge(new List<Id>(new Map<Id, Contact>(people).keySet()));
            List<Account> scope = [
                SELECT Id
                FROM Account
                WHERE Id IN :householdIds AND Emptied_By_Deletion__c != NULL
            ];
            Assert.areEqual(260, scope.size(), 'One bulk delete stamps every household');

            Test.startTest();
            EmptyHouseholdTidyBatch tidy = new EmptyHouseholdTidyBatch();
            tidy.execute(null, scope);
            tidy.finish(null);
            Test.stopTest();

            Assert.areEqual(
                260,
                tidy.removed,
                'Every household is removed. Kept for the bin ' +
                    tidy.keptForRecycleBin +
                    ', kept with dependents ' +
                    tidy.keptWithDependents
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Account WHERE Id IN :householdIds],
                'None is left outside the Recycle Bin'
            );
        }
    }

    @IsTest
    static void aRelationshipThatCannotBeReadKeepsEveryHouseholdAndIsLogged() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Contact maria = HouseholdTestDataFactory.newContact('Ms.', 'Maria', 'Garcia');
            Id household = deletedPersonsHousehold(maria);
            purge(new List<Id>{ maria.Id });
            EmptyHouseholdTidyBatch.relationshipsOverride = new List<String>{
                'Contacts',
                'No_Such_Relationship__r'
            };

            runTidyUp();

            Assert.isFalse(isInRecycleBin(household), 'Not knowing is not answering no');
            List<Error_Log__c> entries = [
                SELECT Message__c
                FROM Error_Log__c
                WHERE Context__c = 'EmptyHouseholdTidyBatch'
            ];
            Assert.areEqual(1, entries.size(), 'The unreadable relationship is logged once');
            Assert.isTrue(
                entries[0].Message__c.contains('No_Such_Relationship__r'),
                'It is named: ' + entries[0].Message__c
            );
        }
    }

    @IsTest
    static void aRefusedDeleteIsLoggedOncePerChunk() {
        System.runAs(TestUsers.admin()) {
            contactMode();
            Account gone = HouseholdTestDataFactory.newHousehold('The Gone Family');
            insert gone;
            delete gone;
            EmptyHouseholdTidyBatch.relationshipsOverride = new List<String>();

            Test.startTest();
            EmptyHouseholdTidyBatch tidy = new EmptyHouseholdTidyBatch();
            tidy.execute(null, new List<Account>{ new Account(Id = gone.Id) });
            Test.stopTest();

            Assert.areEqual(0, tidy.removed, 'Nothing was removed');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = 'EmptyHouseholdTidyBatch'],
                'The refusal is logged'
            );
        }
    }

    @IsTest
    static void bookkeepingRelationshipsAreNotDependents() {
        // runs-as: deploying user (describe only, no records and no permission checks)
        Assert.isTrue(EmptyHouseholdTidyBatch.isBookkeeping('AccountShare'));
        Assert.isTrue(EmptyHouseholdTidyBatch.isBookkeeping('AccountHistory'));
        Assert.isTrue(EmptyHouseholdTidyBatch.isBookkeeping('FeedItem'));
        // A subquery on this big-object-backed history faults past any catch (found on oi-test).
        Assert.isTrue(EmptyHouseholdTidyBatch.isBookkeeping('RecordActionHistory'));
        Assert.isTrue(EmptyHouseholdTidyBatch.isBookkeeping('Archive__b'));
        Assert.isFalse(EmptyHouseholdTidyBatch.isBookkeeping('Contact'));
        List<String> relationships = EmptyHouseholdTidyBatch.dependentRelationships();
        Assert.isTrue(relationships.contains('Contacts'), 'Live members keep a household');
        Assert.isFalse(relationships.contains('Shares'), 'Sharing rows do not');
        Assert.isFalse(relationships.contains('RecordActionHistories'), 'Nor action history');
        for (
            String own : new List<String>{
                'Addresses__r',
                'Household_Members__r',
                'Import_Rows_Household__r'
            }
        ) {
            Assert.isFalse(relationships.contains(own), own + ' is the household\'s own');
        }
    }

    @IsTest
    static void theTidyUpIsScheduledOnceAndListedAsANightlyJob() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Id first = EmptyHouseholdTidyScheduler.start();
            Id second = EmptyHouseholdTidyScheduler.start();
            Test.stopTest();

            Assert.areEqual(first, second, 'Starting again finds the job already there.');
            Boolean listed = false;
            for (NightlyJob job : NightlyJobs.all()) {
                if (job instanceof NightlyJobs.EmptyHouseholdTidyJob) {
                    listed = job.isScheduled();
                }
            }
            Assert.isTrue(listed, 'Health Check sees it among the nightly jobs, scheduled.');
        }
    }

    @IsTest
    static void theScheduleStartsTheBatch() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            new EmptyHouseholdTidyScheduler().execute(null);
            Test.stopTest();
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name = 'EmptyHouseholdTidyBatch'],
                'The nightly run starts one batch'
            );
        }
    }
}
