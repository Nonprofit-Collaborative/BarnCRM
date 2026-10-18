/**
 * The Approve Hours screen's controller (V-02, R-VG5): the list a page at a time and narrowed
 * by job and dates, the three verbs through the service, a bulk approval of 251 entries, and
 * what a user without Manage Volunteers gets. Run as users holding the packaged Volunteers
 * permission sets for each role, so the sets are what is tested.
 */
@IsTest(
    testFor='ApexClass:VolunteerHoursApprovalController, ApexClass:VolunteerHoursSelector, ApexClass:VolunteerHoursService'
)
private class VolunteerHoursApprovalControllerTest {
    private static final String COORDINATOR = 'ApprovalCoordinator';
    private static final String STAFFER = 'ApprovalStaffer';
    private static final String READER = 'ApprovalReader';
    private static final String SUBMITTED = 'Submitted';

    @TestSetup
    static void makeData() {
        TestUsers.standardUserWith(
            COORDINATOR,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Coordinator' }
        );
        TestUsers.standardUserWith(
            STAFFER,
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
        );
        TestUsers.standardUserWith(
            READER,
            new List<String>{ 'BarnCRM_Read_Only', 'Volunteers_Read_Only' }
        );
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.contact('Rivera', null);
            VolunteersTestData.job('Food pantry sort');
            VolunteersTestData.job('Garden');
        }
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND IsActive = TRUE LIMIT 1];
    }

    private static Id jobId(String name) {
        return [SELECT Id FROM Volunteer_Job__c WHERE Name = :name LIMIT 1].Id;
    }

    /** Submitted entries on the job, one a day from 1 March 2026, entered by an admin. */
    private static List<Volunteer_Hours__c> entries(Integer howMany, String jobName) {
        List<Volunteer_Hours__c> created = new List<Volunteer_Hours__c>();
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Id personId = [SELECT Id FROM Contact LIMIT 1].Id;
            Id onJob = jobId(jobName);
            for (Integer i = 0; i < howMany; i++) {
                Volunteer_Hours__c entry = VolunteersTestData.newHours(personId, onJob, 2);
                entry.Date_Worked__c = Date.newInstance(2026, 3, 1).addDays(Math.mod(i, 28));
                created.add(entry);
            }
            insert created;
        }
        return created;
    }

    private static List<Id> idsOf(List<Volunteer_Hours__c> records) {
        return new List<Id>(new Map<Id, Volunteer_Hours__c>(records).keySet());
    }

    private static String refusal(System.Callable attempt) {
        try {
            attempt.call(null, null);
        } catch (AuraHandledException refused) {
            return refused.getMessage();
        }
        return '';
    }

    @IsTest
    static void aCoordinatorPagesThroughTheQueueAndNarrowsIt() {
        entries(55, 'Food pantry sort');
        entries(2, 'Garden');
        VolunteerHoursApprovalController.HoursPage first;
        VolunteerHoursApprovalController.HoursPage second;
        VolunteerHoursApprovalController.HoursPage garden;
        VolunteerHoursApprovalController.HoursPage firstWeek;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            first = VolunteerHoursApprovalController.getHours(null, null, null, null, null, null);
            VolunteerHoursApprovalController.HoursRow last = first.rows[first.rows.size() - 1];
            second = VolunteerHoursApprovalController.getHours(
                SUBMITTED,
                null,
                null,
                null,
                last.dateWorked,
                last.recordId
            );
            garden = VolunteerHoursApprovalController.getHours(
                SUBMITTED,
                jobId('Garden'),
                null,
                null,
                null,
                null
            );
            firstWeek = VolunteerHoursApprovalController.getHours(
                SUBMITTED,
                jobId('Food pantry sort'),
                Date.newInstance(2026, 3, 1),
                Date.newInstance(2026, 3, 7),
                null,
                null
            );
        }
        Test.stopTest();

        Assert.isTrue(first.canManage, 'A coordinator holds Manage Volunteers.');
        Assert.areEqual(50, first.rows.size(), 'One page is fifty rows.');
        Assert.isTrue(first.hasMore, 'And says there is more.');
        Assert.areEqual(7, second.rows.size(), 'The next page holds the rest.');
        Assert.isFalse(second.hasMore, 'And no more after it.');
        Set<Id> seen = new Set<Id>();
        for (VolunteerHoursApprovalController.HoursRow row : first.rows) {
            seen.add(row.recordId);
        }
        for (VolunteerHoursApprovalController.HoursRow row : second.rows) {
            Assert.isFalse(seen.contains(row.recordId), 'No row appears on two pages.');
        }
        Assert.areEqual(2, garden.rows.size(), 'The job filter narrows the list.');
        Assert.areEqual('Garden', garden.rows[0].jobName, 'And names the job.');
        Assert.areEqual(14, firstWeek.rows.size(), 'Two entries a day for the first week.');
        Assert.areEqual(SUBMITTED, firstWeek.rows[0].status, 'Each row carries its status.');
    }

    @IsTest
    static void aCoordinatorApprovesTwoHundredFiftyOneEntriesAtOnce() {
        List<Id> ids = idsOf(entries(251, 'Food pantry sort'));
        VolunteerHoursApprovalController.ActionResult result;
        User coordinator = user(COORDINATOR);

        Test.startTest();
        System.runAs(coordinator) {
            result = VolunteerHoursApprovalController.approve(ids);
        }
        Test.stopTest();

        Assert.areEqual(251, result.moved, 'Every entry moved.');
        Assert.isTrue(result.refused.isEmpty(), 'None refused: ' + result.refused);
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Volunteer_Hours__c
                    WHERE Status__c = 'Approved' AND Approved_By__c = :coordinator.Id
                ],
                'Each records the coordinator as who approved it.'
            );
        }
    }

    @IsTest
    static void aCoordinatorRejectsWithAReasonAndReopens() {
        List<Id> ids = idsOf(entries(3, 'Garden'));
        String noReason;
        VolunteerHoursApprovalController.ActionResult rejected;
        VolunteerHoursApprovalController.ActionResult reopened;
        VolunteerHoursApprovalController.HoursPage rejectedList;

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            noReason = refusal(new Attempt('reject', ids, ' '));
            rejected = VolunteerHoursApprovalController.reject(ids, 'Wrong date');
            rejectedList = VolunteerHoursApprovalController.getHours(
                'Rejected',
                null,
                null,
                null,
                null,
                null
            );
            reopened = VolunteerHoursApprovalController.reopen(new List<Id>{ ids[0], ids[1] });
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Volunteers_Hours_RejectionReasonRequired,
            noReason,
            'A rejection needs a reason.'
        );
        Assert.areEqual(3, rejected.moved, 'All three rejected.');
        Assert.areEqual(3, rejectedList.rows.size(), 'They are on the Rejected list.');
        Assert.areEqual('Wrong date', rejectedList.rows[0].rejectionReason, 'With the reason.');
        Assert.areEqual(2, reopened.moved, 'Two reopened.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Status__c = :SUBMITTED],
                'Reopened entries are Submitted again.'
            );
        }
    }

    @IsTest
    static void withoutManageVolunteersTheListIsReadOnlyAndTheVerbsAreRefused() {
        List<Id> ids = idsOf(entries(2, 'Garden'));
        VolunteerHoursApprovalController.HoursPage stafferPage;
        VolunteerHoursApprovalController.HoursPage readerPage;
        String stafferApprove;
        String stafferReopen;

        Test.startTest();
        System.runAs(user(STAFFER)) {
            stafferPage = VolunteerHoursApprovalController.getHours(
                null,
                null,
                null,
                null,
                null,
                null
            );
            stafferApprove = refusal(new Attempt('approve', ids, null));
            stafferReopen = refusal(new Attempt('reopen', ids, null));
        }
        System.runAs(user(READER)) {
            readerPage = VolunteerHoursApprovalController.getHours(
                null,
                null,
                null,
                null,
                null,
                null
            );
        }
        Test.stopTest();

        Assert.isFalse(stafferPage.canManage, 'A staffer may not approve.');
        Assert.areEqual(
            Label.Volunteers_Hours_NeedManagePermission,
            stafferApprove,
            'Approving is refused, naming the permission.'
        );
        Assert.areEqual(
            Label.Volunteers_Hours_NeedManagePermission,
            stafferReopen,
            'So is reopening.'
        );
        Assert.isFalse(readerPage.canManage, 'Read Only may not approve.');
        Assert.isTrue(readerPage.rows.isEmpty(), 'And sees no hours entries.');
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.areEqual(
                2,
                [SELECT COUNT() FROM Volunteer_Hours__c WHERE Status__c = :SUBMITTED],
                'Nothing moved.'
            );
        }
    }

    @IsTest
    static void aRequestWithNothingTooMuchOrAnUnknownStatusIsRefused() {
        List<Id> tooMany = new List<Id>();
        Id sample = idsOf(entries(1, 'Garden'))[0];
        for (Integer i = 0; i <= VolunteerHoursApprovalController.MAX_PER_CALL; i++) {
            tooMany.add(sample);
        }
        String nothing;
        String overLimit;
        String unknownStatus = '';

        Test.startTest();
        System.runAs(user(COORDINATOR)) {
            nothing = refusal(new Attempt('approve', new List<Id>(), null));
            overLimit = refusal(new Attempt('approve', tooMany, null));
            try {
                VolunteerHoursApprovalController.getHours('Pending', null, null, null, null, null);
            } catch (AuraHandledException refused) {
                unknownStatus = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(Label.Volunteers_Approve_NothingSelected, nothing, 'Nothing selected.');
        Assert.isTrue(
            overLimit.contains(String.valueOf(VolunteerHoursApprovalController.MAX_PER_CALL)),
            'Too many names the limit: ' + overLimit
        );
        Assert.areEqual(
            Label.Volunteers_Approve_ActionFailed,
            unknownStatus,
            'A status the screen does not offer is refused.'
        );
    }

    /** One verb call, so each refusal is caught the same way. */
    private class Attempt implements System.Callable {
        private String verb;
        private List<Id> ids;
        private String reason;

        Attempt(String verb, List<Id> ids, String reason) {
            this.verb = verb;
            this.ids = ids;
            this.reason = reason;
        }

        public Object call(String action, Map<String, Object> args) {
            if (verb == 'approve') {
                return VolunteerHoursApprovalController.approve(ids);
            }
            if (verb == 'reject') {
                return VolunteerHoursApprovalController.reject(ids, reason);
            }
            return VolunteerHoursApprovalController.reopen(ids);
        }
    }
}
