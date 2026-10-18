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
        Volunteer_Shift__c onShift = shift();
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
        return new Map<Id, SObject>(records).keySet();
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

    /**
     * 251 people each give an hour and a half on one shift, approval off so each counts as it is
     * saved, and 251 sign up: the totals arrive through the queued path every save takes by
     * default, one save for each list.
     */
    @IsTest
    static void twoHundredFiftyOnePeopleInOneSave() {
        System.runAs(admin()) {
            RollupTestSupport.recalculateJustAfterTheSave();
            VolunteersTestData.volunteerSettings(false, false);
            List<Contact> people = VolunteersTestData.contacts(251);
            Volunteer_Shift__c onShift = shift();
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            List<Volunteer_Signup__c> signups = new List<Volunteer_Signup__c>();
            for (Contact person : people) {
                entries.add(entry(person.Id, 1.5, Date.today()));
                signups.add(VolunteersTestData.newSignup(onShift.Id, person.Id));
            }

            Test.startTest();
            insert entries;
            insert signups;
            Test.stopTest();

            Assert.areEqual(376.5, shift().Total_Hours__c, '251 times 1.5 on the shift');
            Assert.areEqual(376.5, job().Total_Hours__c, 'And on the job');
            Assert.areEqual(251, shift().Slots_Filled__c, 'Every sign-up counts');
            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Contact
                    WHERE Id IN :idsOf(people) AND Volunteer_Hours_Total__c = 1.5
                ],
                'Every person has their own total'
            );
        }
    }

    /**
     * A staff member (the Team Member role's sets) enters hours with approval off: the totals
     * move although Staff can edit none of them, and the Read Only role reads them.
     */
    @IsTest
    static void staffSavesMoveTotalsTheyCannotEdit() {
        User staffer = TestUsers.standardUserWith(
            'Staffer',
            new List<String>{ 'BarnCRM_Staff', 'Rollup_Builder_User', 'Volunteers_Staff' }
        );
        User reader = TestUsers.standardUserWith(
            'Reader',
            new List<String>{ 'BarnCRM_Read_Only', 'Rollup_Builder_User', 'Volunteers_Read_Only' }
        );
        Contact person = rivera();
        System.runAs(admin()) {
            VolunteersTestData.volunteerSettings(false, false);
            update new Contact(Id = person.Id, OwnerId = staffer.Id);
        }

        Test.startTest();
        System.runAs(staffer) {
            insert VolunteersTestData.newHours(person.Id, job().Id, 2);
            Assert.isFalse(
                Schema.SObjectType.Contact.fields.Volunteer_Hours_Total__c.isUpdateable(),
                'Staff cannot type a total'
            );
        }
        Test.stopTest();

        System.runAs(reader) {
            Assert.isTrue(
                Schema.SObjectType.Contact.fields.Volunteer_Hours_Total__c.isAccessible(),
                'Read Only sees the totals on a person'
            );
            Assert.isTrue(
                Schema.SObjectType.Volunteer_Job__c.fields.Total_Hours__c.isAccessible(),
                'And on a job'
            );
        }
        System.runAs(admin()) {
            Assert.areEqual(2, rivera().Volunteer_Hours_Total__c, 'The staffer\'s hours count');
            Assert.areEqual(2, job().Total_Hours__c, 'On the job too');
        }
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
