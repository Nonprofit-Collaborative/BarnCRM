/**
 * Approval is a status moved by a service (R-VG5 to R-VG8): hours start Submitted, only a
 * coordinator with Manage Volunteers approves, rejects or reopens them, and no other save can
 * move the status.
 */
@IsTest(
    testFor='ApexClass:VolunteerHoursService, ApexClass:VolunteerHoursWriter, ApexClass:VolunteerSettings, ApexTrigger:VolunteerHoursTrigger'
)
private class VolunteerHoursServiceTest {
    @TestSetup
    static void makeData() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            VolunteersTestData.contact('Rivera', null);
            VolunteersTestData.job('Food pantry sort');
        }
    }

    private static Volunteer_Hours__c entry() {
        return VolunteersTestData.newHours(
            [SELECT Id FROM Contact LIMIT 1].Id,
            [SELECT Id FROM Volunteer_Job__c LIMIT 1].Id,
            3
        );
    }

    private static Volunteer_Hours__c reread(Id hoursId) {
        return [
            SELECT Id, Status__c, Approved_By__c, Approved_Date__c, Rejection_Reason__c, Hours__c
            FROM Volunteer_Hours__c
            WHERE Id = :hoursId
        ];
    }

    private static String saveError(SObject record, Boolean isInsert) {
        try {
            if (isInsert) {
                insert record;
            } else {
                update record;
            }
        } catch (DmlException refused) {
            return refused.getDmlMessage(0);
        }
        return '';
    }

    @IsTest
    static void settingsReadAsShippedUntilSaved() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Assert.isTrue(VolunteerSettings.hoursRequireApproval(), 'Approval ships on.');
            Assert.isTrue(VolunteerSettings.attendanceCreatesHours(), 'Attendance hours ship on.');
            Assert.areEqual(8, VolunteerSettings.shiftHorizonWeeks(), 'The horizon ships at 8.');

            OrgSettingsSystemWriter.save(
                Volunteer_Settings__c.SObjectType,
                new Map<Schema.SObjectField, Object>{
                    Volunteer_Settings__c.Shift_Horizon_Weeks__c => 40
                }
            );
            SettingsService.clearCaches();
            Assert.areEqual(8, VolunteerSettings.shiftHorizonWeeks(), 'Out of range reads as 8.');
            Assert.isTrue(
                VolunteerSettings.hoursRequireApproval(),
                'A first save of another key keeps approval on (ADR-0035).'
            );

            VolunteersTestData.volunteerSettings(false, false);
            Assert.isFalse(VolunteerSettings.hoursRequireApproval(), 'A saved false is false.');
            Assert.isFalse(VolunteerSettings.attendanceCreatesHours(), 'A saved false is false.');
        }
    }

    @IsTest
    static void newHoursStartSubmitted() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();

            Test.startTest();
            List<Database.SaveResult> results = VolunteerHoursService.submit(
                new List<Volunteer_Hours__c>{ hours }
            );
            Test.stopTest();

            Assert.isTrue(results[0].isSuccess(), 'Submitting saves the entry.');
            Volunteer_Hours__c saved = reread(hours.Id);
            Assert.areEqual('Submitted', saved.Status__c, 'Hours wait for a coordinator.');
            Assert.isNull(saved.Approved_By__c, 'Nobody has approved them yet.');
        }
    }

    @IsTest
    static void approvalOffSavesHoursApprovedByTheSaver() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            VolunteersTestData.volunteerSettings(false, true);
            Volunteer_Hours__c hours = entry();

            Test.startTest();
            insert hours;
            Test.stopTest();

            Volunteer_Hours__c saved = reread(hours.Id);
            Assert.areEqual('Approved', saved.Status__c, 'With approval off hours count at once.');
            Assert.areEqual(UserInfo.getUserId(), saved.Approved_By__c, 'Approved by the saver.');
            Assert.isNotNull(saved.Approved_Date__c, 'At the save time.');
        }
    }

    @IsTest
    static void namingAnotherStatusOnANewEntryIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();
            hours.Status__c = 'Approved';

            Test.startTest();
            String message = saveError(hours, true);
            Test.stopTest();

            Assert.areEqual(
                Label.Volunteers_Hours_StatusThroughApproval,
                message,
                'New hours cannot arrive already approved while approval is on.'
            );
        }
    }

    @IsTest
    static void aStatusChangeOutsideTheServiceIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();
            insert hours;

            Test.startTest();
            String byStatus = saveError(
                new Volunteer_Hours__c(Id = hours.Id, Status__c = 'Approved'),
                false
            );
            String byApprover = saveError(
                new Volunteer_Hours__c(Id = hours.Id, Approved_By__c = UserInfo.getUserId()),
                false
            );
            Test.stopTest();

            Assert.areEqual(
                Label.Volunteers_Hours_StatusThroughApproval,
                byStatus,
                'Even an administrator approves through the service (R-VG5).'
            );
            Assert.areEqual(
                Label.Volunteers_Hours_StatusThroughApproval,
                byApprover,
                'Approved By is the service\'s to write.'
            );
            Assert.areEqual('Submitted', reread(hours.Id).Status__c, 'Nothing moved.');
        }
    }

    @IsTest
    static void approveRejectAndReopen() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();
            insert hours;
            Set<Id> ids = new Set<Id>{ hours.Id };

            Test.startTest();
            Assert.areEqual(1, VolunteerHoursService.approve(ids), 'One entry approved.');
            Volunteer_Hours__c approved = reread(hours.Id);
            Assert.areEqual(
                0,
                VolunteerHoursService.approve(ids),
                'Approving twice moves nothing.'
            );

            String locked = saveError(new Volunteer_Hours__c(Id = hours.Id, Hours__c = 5), false);

            Assert.areEqual(1, VolunteerHoursService.reject(ids, '  Wrong day  '), 'Rejected.');
            Volunteer_Hours__c rejected = reread(hours.Id);

            Assert.areEqual(1, VolunteerHoursService.reopen(ids), 'Reopened.');
            Volunteer_Hours__c reopened = reread(hours.Id);
            update new Volunteer_Hours__c(Id = hours.Id, Hours__c = 5);
            Test.stopTest();

            Assert.areEqual('Approved', approved.Status__c, 'Approved.');
            Assert.areEqual(UserInfo.getUserId(), approved.Approved_By__c, 'By the coordinator.');
            Assert.isNotNull(approved.Approved_Date__c, 'Now.');
            Assert.isTrue(
                locked.contains('Approved hours are locked'),
                'An approved entry is locked (R-VG7): ' + locked
            );
            Assert.areEqual('Rejected', rejected.Status__c, 'Rejected.');
            Assert.areEqual('Wrong day', rejected.Rejection_Reason__c, 'The reason is kept.');
            Assert.areEqual(UserInfo.getUserId(), rejected.Approved_By__c, 'Who rejected it.');
            Assert.areEqual('Submitted', reopened.Status__c, 'Back to Submitted.');
            Assert.isNull(reopened.Approved_By__c, 'Nobody has decided it now.');
            Assert.isNull(reopened.Approved_Date__c, 'No decision date.');
            Assert.isNull(reopened.Rejection_Reason__c, 'No reason.');
            Assert.areEqual(5, reread(hours.Id).Hours__c, 'A reopened entry can be corrected.');
        }
    }

    @IsTest
    static void rejectingWithoutAReasonIsRefused() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();
            insert hours;
            String message = '';

            Test.startTest();
            try {
                VolunteerHoursService.reject(new Set<Id>{ hours.Id }, ' ');
            } catch (VolunteerHoursService.VolunteerHoursException refused) {
                message = refused.getMessage();
            }
            Test.stopTest();

            Assert.areEqual(
                Label.Volunteers_Hours_RejectionReasonRequired,
                message,
                'Rejecting says why (R-VG8).'
            );
            Assert.areEqual('Submitted', reread(hours.Id).Status__c, 'Nothing moved.');
        }
    }

    @IsTest
    static void aUserWithoutManageVolunteersCannotApprove() {
        Id hoursId;
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c hours = entry();
            insert hours;
            hoursId = hours.Id;
        }
        String message = '';

        Test.startTest();
        System.runAs(TestUsers.admin()) {
            Assert.isFalse(
                VolunteerHoursService.canManage(),
                'BarnCRM Admin alone does not manage volunteers.'
            );
            try {
                VolunteerHoursService.approve(new Set<Id>{ hoursId });
            } catch (VolunteerHoursService.VolunteerHoursException refused) {
                message = refused.getMessage();
            }
        }
        Test.stopTest();

        Assert.areEqual(
            Label.Volunteers_Hours_NeedManagePermission,
            message,
            'Approving needs Manage Volunteers (R-VG5).'
        );
    }

    @IsTest
    static void twoHundredFiftyOneEntriesAreApprovedInOneGo() {
        System.runAs(TestUsers.adminWith(VolunteersTestData.ADMIN)) {
            Volunteer_Hours__c template = entry();
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            for (Integer i = 0; i < 251; i++) {
                entries.add(template.clone());
            }
            insert entries;

            Test.startTest();
            Integer moved = VolunteerHoursService.approve(
                new Map<Id, Volunteer_Hours__c>(entries).keySet()
            );
            Test.stopTest();

            Assert.areEqual(251, moved, 'Every entry approved.');
            Assert.areEqual(
                251,
                [
                    SELECT COUNT()
                    FROM Volunteer_Hours__c
                    WHERE Status__c = 'Approved' AND Approved_By__c != NULL
                ],
                'All of them approved, by the coordinator.'
            );
        }
    }
}
