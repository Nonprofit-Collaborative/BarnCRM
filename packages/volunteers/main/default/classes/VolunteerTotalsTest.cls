/**
 * The volunteer totals (V-03, canonical model Section 29O) computed by the real Rollup Builder
 * engine from the 19 definitions Volunteers ships, the way Giving's rollup tests run its own:
 * the shipped rows are materialized through `RollupService` as the install does, and every total
 * is read back from the record after an ordinary save, never asked for.
 *
 * Only Approved hours count (R-VG6): approving adds an entry to every total, rejecting or
 * reopening takes it out. Slots Filled counts the sign-ups that are not Cancelled (R-VU4).
 */
@IsTest(
    testFor='ApexTrigger:VolunteerHoursTrigger, ApexTrigger:VolunteerSignupTrigger, ApexClass:VolunteersPostInstall'
)
private class VolunteerTotalsTest {
    private static final String HOURS = 'Volunteer_Hours__c';
    private static final String SIGNUPS = 'Volunteer_Signup__c';
    private static final String ROLLUP_ADMIN = 'Rollup_Builder_Admin';

    /** A BarnCRM admin who holds the Volunteers and Rollup Builder admin sets, as installed. */
    private static User admin() {
        return TestUsers.withPermissionSets(
            new List<String>{ TestUsers.CORE_ADMIN, VolunteersTestData.ADMIN, ROLLUP_ADMIN }
        );
    }

    @TestSetup
    static void makeData() {
        System.runAs(admin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Account household = VolunteersTestData.household('The Rivera Family');
            VolunteersTestData.contact('Rivera', household.Id);
            Volunteer_Job__c job = VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.shift(job.Id);
            RollupService.ensureDefaults();
            // Each save recalculates its totals before it returns, so a test can read them after
            // each of several saves. The queued default is the bulk test's path.
            RollupTestSupport.recalculateInTheSave();
        }
    }

    private static Contact rivera() {
        return [
            SELECT
                Id,
                AccountId,
                Volunteer_Hours_Total__c,
                Volunteer_Hours_This_Year__c,
                Volunteer_Hours_Last_Year__c,
                First_Volunteer_Date__c,
                Last_Volunteer_Date__c
            FROM Contact
            WHERE LastName = 'Rivera'
            LIMIT 1
        ];
    }

    private static Account account(Id accountId) {
        return [
            SELECT
                Id,
                Volunteer_Hours_Total__c,
                Volunteer_Hours_This_Year__c,
                Volunteer_Hours_Last_Year__c,
                First_Volunteer_Date__c,
                Last_Volunteer_Date__c
            FROM Account
            WHERE Id = :accountId
        ];
    }

    private static Volunteer_Job__c job() {
        return [
            SELECT Id, Total_Hours__c, Last_Volunteer_Date__c, Rollups_Last_Calculated__c
            FROM Volunteer_Job__c
            LIMIT 1
        ];
    }

    private static Volunteer_Shift__c shift() {
        return [
            SELECT
                Id,
                Volunteer_Job__c,
                Total_Hours__c,
                Slots_Filled__c,
                Slots_Remaining__c,
                Rollups_Last_Calculated__c
            FROM Volunteer_Shift__c
            LIMIT 1
        ];
    }

    /** A blank total counts as zero, so a sum or a count compares without a null check. */
    private static Decimal valueOf(Object total) {
        return total == null ? 0 : (Decimal) total;
    }

    private static Volunteer_Hours__c entry(Id contactId, Decimal hours, Date worked) {
        return entry(shift(), contactId, hours, worked);
    }

    private static Volunteer_Hours__c entry(
        Volunteer_Shift__c onShift,
        Id contactId,
        Decimal hours,
        Date worked
    ) {
        Volunteer_Hours__c record = VolunteersTestData.newHours(
            contactId,
            onShift.Volunteer_Job__c,
            hours
        );
        record.Volunteer_Shift__c = onShift.Id;
        record.Date_Worked__c = worked;
        return record;
    }

    private static Set<Id> idsOf(List<SObject> records) {
        return new Set<Id>(new Map<Id, SObject>(records).keySet());
    }

    /**
     * Marks the start of the next save, as a separate transaction would in an org: the trigger
     * framework runs a handler once per record per transaction, and a test method is one.
     */
    private static void nextSave() {
        TriggerHandler.clearRunClaims();
    }

    @IsTest
    static void hoursAndSignupsRunTheRollupsAsTheModulesAutomations() {
        System.runAs(admin()) {
            Map<String, Automation_Registry__mdt> byObject = new Map<String, Automation_Registry__mdt>();
            for (Automation_Registry__mdt row : [
                SELECT Object_Name__c, Execution_Order__c, Enabled_By_Default__c, Module__c
                FROM Automation_Registry__mdt
                WHERE
                    Handler_Class__c = 'RollupTriggerHandler'
                    AND Object_Name__c IN :new Set<String>{ HOURS, SIGNUPS }
            ]) {
                byObject.put(row.Object_Name__c, row);
            }
            Assert.areEqual(
                new Set<String>{ HOURS, SIGNUPS },
                byObject.keySet(),
                'Volunteer Hours and Volunteer Sign-up run the real-time rollups'
            );
            for (Automation_Registry__mdt row : byObject.values()) {
                Assert.areEqual(90, row.Execution_Order__c, 'After the module\'s own rules');
                Assert.isTrue(row.Enabled_By_Default__c, 'On from install');
                Assert.areEqual(
                    'Volunteers',
                    row.Module__c,
                    'Turning Volunteers off stops its rollups too (R-VR2)'
                );
            }
        }
    }

    /**
     * Three entries for Ana Rivera: 2 hours today and 4 more today on the shift, 3 hours a year
     * ago. Saved, nothing counts. The coordinator approves the first two: every total holds
     * exactly those two, and the 4 still waiting adds nothing.
     */
    @IsTest
    static void onlyApprovedHoursCount() {
        System.runAs(admin()) {
            Contact person = rivera();
            Date today = Date.today();
            Date aYearAgo = today.addYears(-1);
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>{
                entry(person.Id, 2, today),
                entry(person.Id, 3, aYearAgo),
                entry(person.Id, 4, today)
            };
            insert entries;

            Assert.areEqual(
                0,
                valueOf(rivera().Volunteer_Hours_Total__c),
                'Submitted adds nothing'
            );
            Assert.areEqual(0, valueOf(job().Total_Hours__c), 'Nothing on the job yet');
            Assert.areEqual(0, valueOf(shift().Total_Hours__c), 'Nothing on the shift yet');
            nextSave();

            Test.startTest();
            VolunteerHoursService.StatusChange approved = VolunteerHoursService.approve(
                new Set<Id>{ entries[0].Id, entries[1].Id }
            );
            Test.stopTest();

            Assert.areEqual(2, approved.moved, 'Both entries approved');
            Contact after = rivera();
            Assert.areEqual(5, after.Volunteer_Hours_Total__c, 'Every approved hour');
            Assert.areEqual(2, after.Volunteer_Hours_This_Year__c, 'This fiscal year');
            Assert.areEqual(3, after.Volunteer_Hours_Last_Year__c, 'Last fiscal year');
            Assert.areEqual(aYearAgo, after.First_Volunteer_Date__c, 'The first approved day');
            Assert.areEqual(today, after.Last_Volunteer_Date__c, 'The latest approved day');

            Account household = account(person.AccountId);
            Assert.areEqual(5, household.Volunteer_Hours_Total__c, 'The household total');
            Assert.areEqual(2, household.Volunteer_Hours_This_Year__c, 'Household this year');
            Assert.areEqual(3, household.Volunteer_Hours_Last_Year__c, 'Household last year');
            Assert.areEqual(aYearAgo, household.First_Volunteer_Date__c, 'Household first day');
            Assert.areEqual(today, household.Last_Volunteer_Date__c, 'Household latest day');

            Volunteer_Job__c onJob = job();
            Assert.areEqual(5, onJob.Total_Hours__c, 'Approved hours on the job');
            Assert.areEqual(today, onJob.Last_Volunteer_Date__c, 'The job was last worked today');
            Assert.isNotNull(onJob.Rollups_Last_Calculated__c, 'The job carries its own stamp');
            Volunteer_Shift__c onShift = shift();
            Assert.areEqual(5, onShift.Total_Hours__c, 'Approved hours on the shift');
            Assert.isNotNull(onShift.Rollups_Last_Calculated__c, 'The shift carries its stamp');
        }
    }

    /**
     * Approving adds, rejecting and reopening take away, and approving again adds back: the
     * totals follow the status, whichever verb moves it.
     */
    @IsTest
    static void rejectingAndReopeningMoveTheTotals() {
        System.runAs(admin()) {
            Contact person = rivera();
            Volunteer_Hours__c two = entry(person.Id, 2, Date.today());
            Volunteer_Hours__c three = entry(person.Id, 3, Date.today());
            insert new List<Volunteer_Hours__c>{ two, three };
            nextSave();

            Test.startTest();
            VolunteerHoursService.approve(new Set<Id>{ two.Id, three.Id });
            Assert.areEqual(5, rivera().Volunteer_Hours_Total__c, 'Both approved');
            nextSave();

            VolunteerHoursService.reopen(new Set<Id>{ two.Id });
            Assert.areEqual(3, rivera().Volunteer_Hours_Total__c, 'Reopened: out of the total');
            Assert.areEqual(3, job().Total_Hours__c, 'And out of the job');
            nextSave();

            VolunteerHoursService.reject(new Set<Id>{ three.Id }, 'Logged twice');
            Assert.areEqual(
                0,
                valueOf(rivera().Volunteer_Hours_Total__c),
                'Rejected: nothing approved is left'
            );
            Assert.areEqual(0, valueOf(shift().Total_Hours__c), 'Nothing on the shift');
            Assert.isNull(rivera().Last_Volunteer_Date__c, 'No approved day is left');
            nextSave();

            VolunteerHoursService.approve(new Set<Id>{ two.Id });
            Test.stopTest();

            Assert.areEqual(2, rivera().Volunteer_Hours_Total__c, 'Approved again: back in');
            Assert.areEqual(2, account(person.AccountId).Volunteer_Hours_Total__c, 'Household');
            Assert.areEqual(2, shift().Total_Hours__c, 'And on the shift');
        }
    }

    /** Slots Filled counts sign-ups that are not Cancelled, through cancel, delete and restore. */
    @IsTest
    static void slotsFilledCountsSignupsThatAreNotCancelled() {
        System.runAs(admin()) {
            Id shiftId = shift().Id;
            List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
            for (Contact person : VolunteersTestData.contacts(3)) {
                signups.add(VolunteersTestData.newSignup(shiftId, person.Id));
            }
            insert signups;
            Assert.areEqual(3, shift().Slots_Filled__c, 'Three booked');
            Assert.areEqual(1, shift().Slots_Remaining__c, 'Four wanted, one to go');
            nextSave();

            Test.startTest();
            update new Volunteer_Signup__c(Id = signups[0].Id, Status__c = 'Cancelled');
            Assert.areEqual(2, shift().Slots_Filled__c, 'A cancelled sign-up frees its place');
            nextSave();

            delete signups[1];
            Assert.areEqual(1, shift().Slots_Filled__c, 'A deleted sign-up stops counting');
            nextSave();

            undelete signups[1];
            Test.stopTest();

            Assert.areEqual(2, shift().Slots_Filled__c, 'A restored sign-up counts again');
            Assert.areEqual(2, shift().Slots_Remaining__c, 'Two still wanted');
        }
    }

    /** The people still waiting in the Rollup Queue for their totals, by Id. */
    private static Set<Id> contactsStillQueued() {
        Set<Id> waiting = new Set<Id>();
        for (Rollup_Queue__c entry : [
            SELECT Record_Ids__c
            FROM Rollup_Queue__c
            WHERE Target_Object__c = 'Contact' AND Status__c = :RollupQueue.STATUS_PENDING
            WITH SYSTEM_MODE
        ]) {
            for (String recordId : entry.Record_Ids__c.split(',')) {
                waiting.add(Id.valueOf(recordId.trim()));
            }
        }
        return waiting;
    }

    /**
     * 251 people each give an hour and a half on one shift, approval off so each counts as it is
     * saved, and 251 sign up, one save for each list. The job and the shift are right when the
     * saves finish. The 251 people are more than one queue run takes (200), so the run a test can
     * see writes 200 and leaves the rest queued for the next, which in an org follows at once.
     */
    @IsTest
    static void twoHundredFiftyOnePeopleInOneSave() {
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, false);
            List<Contact> people = VolunteersTestData.contacts(251);
            Volunteer_Shift__c onShift = shift();
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
            for (Contact person : people) {
                entries.add(entry(onShift, person.Id, 1.5, Date.today()));
                signups.add(VolunteersTestData.newSignup(onShift.Id, person.Id));
            }

            Test.startTest();
            insert entries;
            insert signups;
            Test.stopTest();

            Assert.areEqual(376.5, shift().Total_Hours__c, '251 times 1.5 on the shift');
            Assert.areEqual(376.5, job().Total_Hours__c, 'And on the job');
            Assert.areEqual(251, shift().Slots_Filled__c, 'Every sign-up counts');
            Set<Id> written = idsOf(
                [
                    SELECT Id
                    FROM Contact
                    WHERE Id IN :idsOf(people) AND Volunteer_Hours_Total__c = 1.5
                ]
            );
            Set<Id> queued = contactsStillQueued();
            Assert.isTrue(written.size() >= 200, 'At least one full queue run is written');
            Assert.isFalse(written.removeAll(queued), 'Nobody is both written and waiting');
            written.addAll(queued);
            Assert.areEqual(
                idsOf(people),
                written,
                'Every person has their total, or is queued for it'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WITH SYSTEM_MODE],
                'Nothing failed'
            );
        }
    }

    /**
     * A staff member (the Team Member role's sets) enters hours with approval off: the totals
     * move although Staff can edit none of them, because the engine writes them, not the user.
     */
    @IsTest
    static void staffSavesMoveTotalsTheyCannotEdit() {
        User staffer = TestUsers.standardUserWith(
            'Staffer',
            new List<String>{ 'BarnCRM_Staff', 'Rollup_Builder_User', 'Volunteers_Staff' }
        );
        Contact person = rivera();
        Id jobId = job().Id;
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, false);
            update new Contact(Id = person.Id, OwnerId = staffer.Id);
        }

        Test.startTest();
        System.runAs(staffer) {
            Assert.isFalse(
                Schema.SObjectType.Contact.fields.Volunteer_Hours_Total__c.isUpdateable(),
                'Staff cannot type a total'
            );
            insert VolunteersTestData.newHours(person.Id, jobId, 2);
        }
        Test.stopTest();

        System.runAs(admin()) {
            Assert.areEqual(2, rivera().Volunteer_Hours_Total__c, 'The staffer\'s hours count');
            Assert.areEqual(2, job().Total_Hours__c, 'On the job too');
        }
    }

    /**
     * A coordinator (Standard User profile, Volunteers Coordinator) approves Submitted hours:
     * the person's totals move although Coordinator can edit none of them.
     */
    @IsTest
    static void coordinatorApprovalsMoveTotalsTheyCannotEdit() {
        User coordinator = TestUsers.standardUserWith(
            'Coordinator',
            new List<String>{ 'BarnCRM_Staff', 'Rollup_Builder_User', 'Volunteers_Coordinator' }
        );
        Contact person = rivera();
        // One day for the entry and the check: the admin user's time zone can be a day ahead.
        Date worked = Date.today();
        Volunteer_Hours__c hours = entry(person.Id, 3, worked);
        System.runAs(admin()) {
            update new Contact(Id = person.Id, OwnerId = coordinator.Id);
            insert hours;
        }
        nextSave();

        Test.startTest();
        VolunteerHoursService.StatusChange approved;
        System.runAs(coordinator) {
            Assert.isFalse(
                Schema.SObjectType.Contact.fields.Volunteer_Hours_Total__c.isUpdateable(),
                'Coordinator cannot type a total'
            );
            approved = VolunteerHoursService.approve(new Set<Id>{ hours.Id });
        }
        Test.stopTest();

        Assert.areEqual(1, approved.moved, 'The coordinator approved the entry');
        System.runAs(admin()) {
            Contact after = rivera();
            Assert.areEqual(3, after.Volunteer_Hours_Total__c, 'The person\'s total moved');
            Assert.areEqual(worked, after.Last_Volunteer_Date__c, 'And the latest day');
            Assert.areEqual(3, account(after.AccountId).Volunteer_Hours_Total__c, 'Household');
            Assert.areEqual(3, job().Total_Hours__c, 'And the job');
        }
    }

    /**
     * Every role reads the totals and none can type one (Part G access table): Coordinator,
     * Staff and Read Only, on the Standard User profile with the sets their BarnCRM role gives.
     */
    @IsTest
    static void everyRoleReadsTheTotalsAndNoneTypesThem() {
        Map<String, List<String>> setsByRole = new Map<String, List<String>>{
            'Coordinator' => new List<String>{
                'BarnCRM_Staff',
                'Rollup_Builder_User',
                'Volunteers_Coordinator'
            },
            'Staffer' => new List<String>{
                'BarnCRM_Staff',
                'Rollup_Builder_User',
                'Volunteers_Staff'
            },
            'Reader' => new List<String>{
                'BarnCRM_Read_Only',
                'Rollup_Builder_User',
                'Volunteers_Read_Only'
            }
        };
        Integer checked = 0;
        Test.startTest();
        for (String role : setsByRole.keySet()) {
            System.runAs(TestUsers.standardUserWith(role, setsByRole.get(role))) {
                List<Schema.DescribeFieldResult> totals = new List<Schema.DescribeFieldResult>{
                    Schema.SObjectType.Contact.fields.Volunteer_Hours_Total__c,
                    Schema.SObjectType.Account.fields.Last_Volunteer_Date__c,
                    Schema.SObjectType.Volunteer_Job__c.fields.Total_Hours__c,
                    Schema.SObjectType.Volunteer_Shift__c.fields.Slots_Filled__c
                };
                for (Schema.DescribeFieldResult total : totals) {
                    Assert.isTrue(total.isAccessible(), role + ' reads ' + total.getName());
                    Assert.isFalse(total.isUpdateable(), role + ' cannot type ' + total.getName());
                    checked++;
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(12, checked, 'Four totals checked for each of the three roles');
    }

    /**
     * Where people are person accounts, hours name the Account side and its totals are on the
     * account (Section 29O, Account scope). Skipped in an org without person accounts.
     */
    @IsTest
    static void aPersonAccountGetsItsOwnTotals() {
        System.runAs(admin()) {
            Account person = VolunteersTestData.personAccount('Lopez');
            if (person == null) {
                Assert.areEqual(
                    1,
                    [
                        SELECT COUNT()
                        FROM Rollup_Definition__c
                        WHERE Definition_Key__c = 'Account_Volunteer_Hours_Total'
                    ],
                    'The account totals are installed even where no person is an account'
                );
                return;
            }
            Volunteer_Hours__c hours = entry(null, 3, Date.today());
            hours.Account__c = person.Id;
            insert hours;
            nextSave();

            Test.startTest();
            VolunteerHoursService.approve(new Set<Id>{ hours.Id });
            Test.stopTest();

            Account after = account(person.Id);
            Assert.areEqual(3, after.Volunteer_Hours_Total__c, 'The person account\'s total');
            Assert.areEqual(3, after.Volunteer_Hours_This_Year__c, 'This year');
            Assert.areEqual(Date.today(), after.Last_Volunteer_Date__c, 'Latest day');
            Assert.areEqual(3, shift().Total_Hours__c, 'And on the shift');
        }
    }
}
