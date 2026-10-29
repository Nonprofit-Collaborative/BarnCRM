/**
 * A save recalculates only the rollups its change can affect (ADR-0099
 * `0099-rollups-recalculate-only-what-a-save-changed.md`, rollup review ROLLUPS-4), in the save
 * and in the Rollup Queue.
 *
 * Three definitions write each organization: a staff count from its people (Contact, real
 * time), a child organization count from accounts (a source a contact save never touches), and
 * an every night count of its people. A contact save may move only the first. The other two
 * write Annual Revenue, which starts at 999: had either run, it would hold its count instead.
 */
@IsTest(testFor='ApexClass:RollupChanges, ApexClass:RollupService, ApexClass:RollupQueue')
private class RollupMarkedDefinitionsTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith('Rollup_Builder_Admin');
    }

    private static final Integer ORGANIZATIONS = 10;
    private static final Integer PEOPLE = 200;
    private static final Decimal UNTOUCHED = 999;

    private static Rollup_Definition__c staffCount() {
        return new Rollup_Definition__c(
            Name = 'Staff count',
            Definition_Key__c = 'Test_Marked_Staff_Count',
            Source_Object__c = 'Contact',
            Relationship_Path__c = 'AccountId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'NumberOfEmployees',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    /** Reads Account rows: a contact save cannot change it. */
    private static Rollup_Definition__c childCount() {
        return new Rollup_Definition__c(
            Name = 'Child organizations',
            Definition_Key__c = 'Test_Marked_Child_Count',
            Source_Object__c = 'Account',
            Relationship_Path__c = 'ParentId',
            Aggregate__c = 'COUNT',
            Target_Object__c = 'Account',
            Target_Field__c = 'AnnualRevenue',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Active__c = true
        );
    }

    /** Reads contacts, but waits for the nightly run. */
    private static Rollup_Definition__c nightlyStaffCount() {
        Rollup_Definition__c nightly = staffCount();
        nightly.Name = 'Staff count every night';
        nightly.Definition_Key__c = 'Test_Marked_Nightly_Staff_Count';
        nightly.Target_Field__c = 'AnnualRevenue';
        nightly.Mode__c = RollupService.MODE_SCHEDULED;
        return nightly;
    }

    private static List<Account> organizations() {
        Id organizationType = AccountKindsTestData.organizationRecordTypeId();
        List<Account> created = new List<Account>();
        for (Integer i = 0; i < ORGANIZATIONS; i++) {
            created.add(
                new Account(
                    Name = 'Organization ' + i,
                    RecordTypeId = organizationType,
                    AnnualRevenue = UNTOUCHED
                )
            );
        }
        insert created;
        return created;
    }

    private static List<Contact> people(List<Account> employers) {
        List<Contact> created = new List<Contact>();
        for (Integer i = 0; i < PEOPLE; i++) {
            created.add(
                new Contact(
                    LastName = 'Person ' + i,
                    AccountId = employers[Math.mod(i, ORGANIZATIONS)].Id
                )
            );
        }
        return created;
    }

    private static void assertOnlyTheStaffCountRan(List<Account> employers) {
        for (Account organization : [
            SELECT NumberOfEmployees, AnnualRevenue
            FROM Account
            WHERE Id IN :new Map<Id, Account>(employers).keySet()
        ]) {
            Assert.areEqual(
                PEOPLE / ORGANIZATIONS,
                organization.NumberOfEmployees,
                'The staff count the save moved is recalculated'
            );
            Assert.areEqual(
                UNTOUCHED,
                organization.AnnualRevenue,
                'The child count and the every night count did not run'
            );
        }
    }

    @IsTest
    static void aSaveRecalculatesOnlyTheDefinitionsThatMarkedItsTargets() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
            insert new List<Rollup_Definition__c>{ staffCount(), childCount() };
            List<Account> employers = organizations();

            Test.startTest();
            insert people(employers);
            Test.stopTest();

            assertOnlyTheStaffCountRan(employers);
        }
    }

    @IsTest
    static void anEveryNightDefinitionWaitsForTheNightlyRun() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateInTheSave();
            insert new List<Rollup_Definition__c>{ staffCount(), nightlyStaffCount() };
            List<Account> employers = organizations();

            Test.startTest();
            insert people(employers);
            Test.stopTest();

            assertOnlyTheStaffCountRan(employers);
        }
    }

    /** Queued by default: the entry names the definition, and the processor runs only it. */
    @IsTest
    static void aQueuedEntryNamesItsDefinitionsAndTheProcessorRunsOnlyThose() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            RollupTestSupport.recalculateJustAfterTheSave();
            Rollup_Definition__c staff = staffCount();
            insert new List<Rollup_Definition__c>{ staff, childCount() };
            List<Account> employers = organizations();

            Test.startTest();
            insert people(employers);
            List<Rollup_Queue__c> queued = [
                SELECT Target_Object__c, Definition_Ids__c
                FROM Rollup_Queue__c
                WHERE Status__c = :RollupQueue.STATUS_PENDING
            ];
            Test.stopTest();

            Assert.isFalse(queued.isEmpty(), 'The save queued its organizations');
            for (Rollup_Queue__c entry : queued) {
                Assert.areEqual(
                    String.valueOf(staff.Id),
                    entry.Definition_Ids__c,
                    'Naming only the staff count'
                );
            }
            assertOnlyTheStaffCountRan(employers);
        }
    }

    /** An entry naming no definition, as one written before the upgrade, runs every one. */
    @IsTest
    static void anEntryNamingNoDefinitionRunsEveryDefinition() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            // People first, so their save marks nothing: no definition exists yet.
            List<Account> employers = organizations();
            insert people(employers);
            insert new List<Rollup_Definition__c>{ staffCount(), childCount() };

            Test.startTest();
            RollupQueue.add(
                new Map<String, Set<Id>>{ 'Account' => new Map<Id, Account>(employers).keySet() }
            );
            Test.stopTest();

            for (Account organization : [
                SELECT NumberOfEmployees, AnnualRevenue
                FROM Account
                WHERE Id IN :new Map<Id, Account>(employers).keySet()
            ]) {
                Assert.areEqual(PEOPLE / ORGANIZATIONS, organization.NumberOfEmployees, 'Staff');
                Assert.areEqual(0, organization.AnnualRevenue, 'And the child count ran too');
            }
        }
    }

    /** A definition switched off while its entry waits is skipped; the rest still runs. */
    @IsTest
    static void aDefinitionSwitchedOffWhileQueuedIsSkipped() {
        System.runAs(TestUsers.adminWith('Rollup_Builder_Admin')) {
            List<Account> employers = organizations();
            insert people(employers);
            Rollup_Definition__c staff = staffCount();
            Rollup_Definition__c children = childCount();
            insert new List<Rollup_Definition__c>{ staff, children };
            update new Rollup_Definition__c(Id = children.Id, Active__c = false);
            Set<Id> employerIds = new Map<Id, Account>(employers).keySet();

            Test.startTest();
            RollupQueue.add(
                new Map<String, Set<Id>>{ 'Account' => employerIds },
                new Map<String, Set<Id>>{ 'Account' => new Set<Id>{ staff.Id, children.Id } }
            );
            Test.stopTest();

            assertOnlyTheStaffCountRan(employers);
        }
    }
}
