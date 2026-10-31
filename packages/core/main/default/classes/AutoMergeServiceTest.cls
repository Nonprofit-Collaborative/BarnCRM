/**
 * Auto-merge (R-DP9, R-DP10): only exact pairs, the kept person stays with their family, the
 * merge rules write the winning values, every merge is journaled, and undo restores the real
 * record, its values and its related records, saying what it could not.
 *
 * The review list needs an active duplicate rule to hold a suggestion, which a test cannot
 * switch on, so the pairs are given through AutoMergeService.pairsForTest.
 */
@IsTest(testFor='ApexClass:AutoMergeService')
private class AutoMergeServiceTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static Contact insertPerson(Contact person) {
        Database.DMLOptions options = new Database.DMLOptions();
        options.DuplicateRuleHeader.allowSave = true;
        Database.insert(person, options, AccessLevel.SYSTEM_MODE);
        return person;
    }

    private static Contact person(String firstName, String email) {
        return new Contact(FirstName = firstName, LastName = 'Automerge', Email = email);
    }

    /** The person's live membership rows (empty outside junction mode). */
    private static Set<Id> membershipIds(Id personId) {
        return new Map<Id, Household_Member__c>(
                [SELECT Id FROM Household_Member__c WHERE Contact__c = :personId WITH SYSTEM_MODE]
            )
            .keySet();
    }

    private static Merge_Journal__c journalFor(Id mergedId) {
        return [
            SELECT
                Id,
                Run_Id__c,
                Survivor_Id__c,
                Merged_Id__c,
                Merged_Name__c,
                Status__c,
                Changed_Values__c,
                Moved_Records__c,
                Notes__c
            FROM Merge_Journal__c
            WHERE Merged_Id__c = :mergedId
            WITH SYSTEM_MODE
        ];
    }

    private static Boolean isDeleted(Id contactId) {
        return [SELECT IsDeleted FROM Contact WHERE Id = :contactId WITH SYSTEM_MODE ALL ROWS]
        .IsDeleted;
    }

    @IsTest
    static void exactNeedsTheSameNameAndTheRulesValue() {
        System.runAs(TestUsers.admin()) {
            Contact a = new Contact(
                FirstName = 'Ann',
                LastName = 'Lee',
                Email = 'ann@example.org',
                Phone = '555-010-2000'
            );
            Contact b = new Contact(
                FirstName = 'ann ',
                LastName = 'LEE',
                Email = 'ANN@example.org',
                Phone = '(555) 010 2000'
            );
            Assert.isTrue(AutoMergeService.isExact(a, b, AutoMergeService.NAME_AND_EMAIL));
            Assert.isTrue(AutoMergeService.isExact(a, b, AutoMergeService.NAME_AND_PHONE));
            Assert.isTrue(AutoMergeService.isExact(a, b, AutoMergeService.NAME_EMAIL_AND_PHONE));
            Assert.isFalse(
                AutoMergeService.isExact(a, b, AutoMergeService.NAME_AND_BIRTHDATE),
                'No birthdate on either is not a match.'
            );
            b.Email = 'other@example.org';
            Assert.isFalse(AutoMergeService.isExact(a, b, AutoMergeService.NAME_AND_EMAIL));
            Assert.isFalse(AutoMergeService.isExact(a, b, AutoMergeService.NAME_EMAIL_AND_PHONE));
            a.Birthdate = Date.newInstance(1970, 5, 1);
            b.Birthdate = Date.newInstance(1971, 5, 1);
            Assert.isFalse(
                AutoMergeService.isExact(a, b, AutoMergeService.NAME_AND_PHONE),
                'Differing birthdates are never exact.'
            );
            Contact noFirst = new Contact(LastName = 'Lee', Email = 'ann@example.org');
            Assert.isFalse(
                AutoMergeService.isExact(noFirst, noFirst.clone(), AutoMergeService.NAME_AND_EMAIL),
                'A first name is needed.'
            );
            Contact jon = new Contact(
                FirstName = 'Jon',
                LastName = 'Lee',
                Email = 'ann@example.org'
            );
            Assert.isFalse(AutoMergeService.isExact(a, jon, AutoMergeService.NAME_AND_EMAIL));
        }
    }

    @IsTest
    static void theExactRuleFollowsTheSetting() {
        System.runAs(TestUsers.admin()) {
            Assert.areEqual(AutoMergeService.NAME_AND_EMAIL, AutoMergeService.exactRule());
            BarnCRM_Settings__c settings = BarnCRM_Settings__c.getOrgDefaults();
            settings.Auto_Merge_Exact_Match__c = AutoMergeService.NAME_AND_BIRTHDATE;
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(AutoMergeService.NAME_AND_BIRTHDATE, AutoMergeService.exactRule());
            settings.Auto_Merge_Exact_Match__c = 'Anything';
            HouseholdTestDataFactory.save(settings);
            Assert.areEqual(AutoMergeService.NAME_AND_EMAIL, AutoMergeService.exactRule());
        }
    }

    @IsTest
    static void thePersonWithTheBiggerHouseholdIsKept() {
        System.runAs(TestUsers.admin()) {
            Account family = HouseholdTestDataFactory.newHousehold('Automerge Family');
            Database.insert(family, AccessLevel.SYSTEM_MODE);
            Contact alone = insertPerson(person('Rae', 'rae@example.org'));
            Contact withFamily = person('Rae', 'rae@example.org');
            withFamily.AccountId = family.Id;
            insertPerson(withFamily);
            Contact spouse = person('Sam', 'sam@example.org');
            spouse.AccountId = family.Id;
            insertPerson(spouse);
            AutoMergeService.pairsForTest = new List<List<Id>>{
                new List<Id>{ alone.Id, withFamily.Id },
                new List<Id>{ alone.Id, spouse.Id }
            };

            List<AutoMergeService.Candidate> found = AutoMergeService.candidates();

            Assert.areEqual(1, found.size(), 'Rae and Sam are not an exact match.');
            Assert.areEqual(withFamily.Id, found[0].survivorId, 'Rae stays with her family.');
            Assert.areEqual(alone.Id, found[0].mergedId);
        }
    }

    @IsTest
    static void aMergeIsJournaledAndUndoRestoresTheRealRecord() {
        System.runAs(TestUsers.admin()) {
            Contact kept = insertPerson(person('Lou', 'lou@example.org'));
            Contact other = person('Lou', 'LOU@example.org');
            other.Title = 'Treasurer';
            insertPerson(other);
            Address__c work = new Address__c(
                Contact__c = other.Id,
                Type__c = 'Work',
                Street__c = '9 Side St'
            );
            Database.insert(work, AccessLevel.SYSTEM_MODE);
            AutoMergeService.pairsForTest = new List<List<Id>>{ new List<Id>{ kept.Id, other.Id } };
            Set<Id> keptMemberships = membershipIds(kept.Id);
            Set<Id> otherMemberships = membershipIds(other.Id);

            Integer merged = AutoMergeService.mergeAll(AutoMergeService.candidates(), 'run-1');

            Assert.areEqual(1, merged);
            Assert.isTrue(isDeleted(other.Id), 'The other person is merged away.');
            Assert.areEqual(
                'Treasurer',
                [SELECT Title FROM Contact WHERE Id = :kept.Id WITH SYSTEM_MODE].Title,
                'Not blank fills the blank.'
            );
            Assert.areEqual(
                kept.Id,
                [SELECT Contact__c FROM Address__c WHERE Id = :work.Id WITH SYSTEM_MODE].Contact__c
            );
            Merge_Journal__c journal = journalFor(other.Id);
            Assert.areEqual(AutoMergeService.MERGED, journal.Status__c);
            Assert.areEqual('run-1', journal.Run_Id__c);
            Assert.isTrue(journal.Changed_Values__c.contains('Title'), journal.Changed_Values__c);
            Assert.isTrue(
                journal.Moved_Records__c.contains(String.valueOf(work.Id)),
                journal.Moved_Records__c
            );

            Test.startTest();
            AutoMergeService.undo(new List<Merge_Journal__c>{ journal });
            Test.stopTest();

            Assert.isFalse(
                isDeleted(other.Id),
                'Undo restores the same record from the Recycle Bin.'
            );
            Assert.isNull(
                [SELECT Title FROM Contact WHERE Id = :kept.Id WITH SYSTEM_MODE].Title,
                'The value goes back.'
            );
            Assert.areEqual(
                other.Id,
                [SELECT Contact__c FROM Address__c WHERE Id = :work.Id WITH SYSTEM_MODE].Contact__c,
                'The address moves back.'
            );
            Assert.areEqual(
                keptMemberships,
                membershipIds(kept.Id),
                'The kept person leaves the household they joined only through the merge.'
            );
            Assert.areEqual(
                otherMemberships,
                membershipIds(other.Id),
                'The restored person has their own memberships back.'
            );
            Merge_Journal__c undone = journalFor(other.Id);
            Assert.areEqual(AutoMergeService.UNDONE, undone.Status__c, undone.Notes__c);
        }
    }

    @IsTest
    static void undoSaysWhatItCouldNotRestore() {
        System.runAs(TestUsers.admin()) {
            Contact kept = insertPerson(person('Max', 'max@example.org'));
            Contact other = person('Max', 'max@example.org');
            other.Title = 'Chair';
            insertPerson(other);
            Address__c work = new Address__c(
                Contact__c = other.Id,
                Type__c = 'Work',
                Street__c = '1 Gone Rd'
            );
            Database.insert(work, AccessLevel.SYSTEM_MODE);
            AutoMergeService.pairsForTest = new List<List<Id>>{ new List<Id>{ kept.Id, other.Id } };
            AutoMergeService.mergeAll(AutoMergeService.candidates(), 'run-2');
            update as system new Contact(Id = kept.Id, Title = 'President');
            delete as system work;

            AutoMergeService.undo(new List<Merge_Journal__c>{ journalFor(other.Id) });

            Merge_Journal__c journal = journalFor(other.Id);
            Assert.areEqual(AutoMergeService.PARTLY_UNDONE, journal.Status__c);
            Assert.isTrue(journal.Notes__c.contains('Title'), journal.Notes__c);
            Assert.isTrue(journal.Notes__c.contains('Address__c'), journal.Notes__c);
            Assert.isFalse(isDeleted(other.Id), 'The person is still restored.');
            Assert.areEqual(
                'President',
                [SELECT Title FROM Contact WHERE Id = :kept.Id WITH SYSTEM_MODE].Title,
                'A later change is kept.'
            );
        }
    }

    @IsTest
    static void undoFailsForAPersonNoLongerInTheRecycleBin() {
        System.runAs(TestUsers.admin()) {
            Contact kept = insertPerson(person('Kim', 'kim@example.org'));
            Contact other = insertPerson(person('Kim', 'kim@example.org'));
            AutoMergeService.pairsForTest = new List<List<Id>>{ new List<Id>{ kept.Id, other.Id } };
            AutoMergeService.mergeAll(AutoMergeService.candidates(), 'run-3');
            Database.emptyRecycleBin(new List<Id>{ other.Id });

            AutoMergeService.undo(new List<Merge_Journal__c>{ journalFor(other.Id) });

            Merge_Journal__c journal = journalFor(other.Id);
            Assert.areEqual(AutoMergeService.UNDO_FAILED, journal.Status__c);
            Assert.isTrue(journal.Notes__c.contains('Kim Automerge'), journal.Notes__c);
        }
    }

    @IsTest
    static void aPairThatChangedSinceThePreviewIsSkipped() {
        System.runAs(TestUsers.admin()) {
            Contact kept = insertPerson(person('Eve', 'eve@example.org'));
            Contact other = insertPerson(person('Eve', 'eve@example.org'));
            AutoMergeService.pairsForTest = new List<List<Id>>{ new List<Id>{ kept.Id, other.Id } };
            List<String> refs = new List<String>{ AutoMergeService.candidates()[0].ref };
            update as system new Contact(Id = other.Id, Email = 'changed@example.org');

            Assert.isTrue(AutoMergeService.candidatesFor(refs).isEmpty(), 'Read again, not exact.');
            Assert.isFalse(isDeleted(other.Id));
        }
    }

    @IsTest
    static void aPersonWhoCannotDeletePeopleMergesNothing() {
        Contact kept;
        Contact other;
        System.runAs(TestUsers.admin()) {
            kept = insertPerson(person('Ray', 'ray@example.org'));
            other = insertPerson(person('Ray', 'ray@example.org'));
        }
        System.runAs(TestUsers.standardUserWith(
            'Automergeless',
            new List<String>{ 'BarnCRM_Read_Only' }
        )) {
            AutoMergeService.pairsForTest = new List<List<Id>>{ new List<Id>{ kept.Id, other.Id } };
            List<AutoMergeService.Candidate> found = AutoMergeService.candidates();
            Integer merged = AutoMergeService.mergeAll(found, 'run-4');

            Assert.areEqual(0, merged, 'User mode: no delete access, no merge.');
        }
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(isDeleted(other.Id));
        }
    }

    @IsTest
    static void aPreviewOfManyPairsStaysWithinLimits() {
        System.runAs(TestUsers.admin()) {
            List<Contact> people = new List<Contact>();
            for (Integer i = 0; i < 251; i++) {
                people.add(person('Bulk' + i, 'bulk' + i + '@example.org'));
                people.add(person('Bulk' + i, 'bulk' + i + '@example.org'));
            }
            Database.DMLOptions options = new Database.DMLOptions();
            options.DuplicateRuleHeader.allowSave = true;
            Database.insert(people, options, AccessLevel.SYSTEM_MODE);
            AutoMergeService.pairsForTest = new List<List<Id>>();
            for (Integer i = 0; i < people.size(); i += 2) {
                AutoMergeService.pairsForTest.add(new List<Id>{ people[i].Id, people[i + 1].Id });
            }

            Test.startTest();
            List<AutoMergeService.Candidate> found = AutoMergeService.candidates();
            Integer queries = Limits.getQueries();
            Test.stopTest();

            Assert.areEqual(251, found.size());
            Assert.isTrue(queries < 10, 'A preview reads in a few queries: ' + queries);
        }
    }
}
