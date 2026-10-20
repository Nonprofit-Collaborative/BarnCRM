/**
 * The Volunteers Health Check findings (canonical model Part G, "Health Check"): hours waiting
 * for approval, past shifts still Open, schedules short of the horizon (29T), coordinators
 * missing their set and its fix, and shipped volunteer totals turned off. Each is asked of a
 * BarnCRM admin holding Volunteers Admin, the person who runs Health Check; a viewer who may not
 * manage settings, and an org with the module turned off, get none. One test runs Core's whole
 * report to prove Core finds the extension by name.
 */
@IsTest(testFor='ApexClass:VolunteersHealthCheckExtension, ApexClass:VolunteerHealthCheckSelector')
private class VolunteersHealthCheckExtensionTest {
    private static User admin() {
        return TestUsers.adminWith(VolunteersTestData.ADMIN);
    }

    /**
     * `Finding.key` is `@AuraEnabled` only, so another package reads it through JSON, as
     * `GivingHealthCheckExtensionTest` does.
     */
    private static Map<String, Object> byKey(List<HealthCheckService.Finding> findings) {
        Map<String, Object> result = new Map<String, Object>();
        for (HealthCheckService.Finding finding : findings) {
            Map<String, Object> fields = (Map<String, Object>) JSON.deserializeUntyped(
                JSON.serialize(finding)
            );
            result.put((String) fields.get('key'), fields);
        }
        return result;
    }

    private static Map<String, Object> finding(String key) {
        return (Map<String, Object>) byKey(new VolunteersHealthCheckExtension().findings())
            .get(key);
    }

    @IsTest
    static void hoursWaitingLongerThanTheLimitAreCountedAndLinked() {
        System.runAs(admin()) {
            VolunteersTestData.contactModeWithoutAutomaticHouseholds();
            Contact ana = VolunteersTestData.contact('Lee', null);
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            List<Volunteer_Hours__c> entries = new List<Volunteer_Hours__c>();
            for (Integer i = 0; i < 251; i++) {
                entries.add(VolunteersTestData.newHours(ana.Id, pantry.Id, 1));
            }
            insert entries;
            Assert.isNull(finding('volunteer_hours_waiting'), 'Hours entered today are not late');

            // Every entry was entered before tomorrow; the cap stops the count at 250.
            VolunteersHealthCheckExtension.hoursWaitingDays = -1;
            VolunteersHealthCheckExtension.countCap = 250;
            Map<String, Object> late = finding('volunteer_hours_waiting');

            Assert.isNotNull(late, 'Hours waiting longer than the limit are reported');
            Assert.isTrue(((String) late.get('title')).contains('250'), 'The count is capped');
            Assert.areEqual(5, ((List<Object>) late.get('links')).size(), 'Five are linked');
            Assert.isTrue(
                ((String) late.get('fixTarget')).endsWith('Volunteer_Approve_Hours'),
                'The fix opens Approve Hours'
            );
            Assert.areEqual(HealthCheckService.SEVERITY_WARNING, late.get('severity'));
        }
    }

    @IsTest
    static void aShiftThatEndedAWeekAgoAndIsStillOpenIsReported() {
        System.runAs(admin()) {
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            Volunteer_Shift__c old = VolunteersTestData.newShift(
                pantry.Id,
                Datetime.now().addDays(-10),
                3
            );
            Volunteer_Shift__c closed = VolunteersTestData.newShift(
                pantry.Id,
                Datetime.now().addDays(-10),
                3
            );
            closed.Status__c = 'Completed';
            Volunteer_Shift__c recent = VolunteersTestData.newShift(
                pantry.Id,
                Datetime.now().addDays(-2),
                3
            );
            insert new List<Volunteer_Shift__c>{ old, closed, recent };

            Map<String, Object> open = finding('volunteer_past_shifts_open');

            Assert.isNotNull(open, 'The old Open shift is reported');
            Assert.areEqual(
                String.format(
                    Label.Volunteers_HealthCheck_PastShiftsTitleOne,
                    new List<Object>{ '1' }
                ),
                open.get('title'),
                'Only that one, counted in the singular'
            );
            Assert.isTrue(
                ((String) open.get('detail')).endsWith(Label.Volunteers_HealthCheck_FirstListedOne),
                'One shift is linked, in the singular'
            );
            Assert.areEqual(HealthCheckService.SEVERITY_INFO, open.get('severity'));
            Assert.isTrue(
                ((String) open.get('fixTarget'))
                    .endsWith(
                        '/list?filterName=' +
                        NamespaceUtil.qualify(VolunteersHealthCheckExtension.PAST_SHIFTS_LIST_VIEW)
                    ),
                'The fix opens the past shifts still Open list view'
            );
        }
    }

    @IsTest
    static void aScheduleIsReportedUntilItsShiftsReachTheHorizon() {
        System.runAs(admin()) {
            VolunteersTestData.shiftHorizonWeeks(2);
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            Date today = ShiftScheduleService.today();
            Shift_Schedule__c schedule = VolunteersTestData.newSchedule(
                pantry.Id,
                'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday',
                today
            );

            Test.startTest();
            insert schedule;
            // The run the save queued has not happened yet, so nothing is created ahead.
            Assert.isNotNull(
                finding('volunteer_schedule_horizon'),
                'A schedule with nothing created yet is short of the horizon'
            );
            Test.stopTest();

            Assert.isNull(
                finding('volunteer_schedule_horizon'),
                'Once its run has created shifts to the horizon it is not reported'
            );
        }
    }

    @IsTest
    static void aScheduleEndingSoonIsMeasuredAgainstItsEndDate() {
        System.runAs(admin()) {
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            Date today = ShiftScheduleService.today();
            Shift_Schedule__c schedule = VolunteersTestData.newSchedule(
                pantry.Id,
                'Monday;Tuesday;Wednesday;Thursday;Friday;Saturday;Sunday',
                today
            );
            schedule.End_Date__c = today.addDays(5);

            Test.startTest();
            insert schedule;
            Test.stopTest();

            Assert.areEqual(
                today.addDays(5),
                [SELECT Created_Through__c FROM Shift_Schedule__c WHERE Id = :schedule.Id]
                .Created_Through__c,
                'The run stops at the End Date'
            );
            Assert.isNull(
                finding('volunteer_schedule_horizon'),
                'Created through its End Date is as far as it goes'
            );
        }
    }

    @IsTest
    static void aCoordinatorWithoutTheirSetIsNamedAndTheFixGivesIt() {
        User coordinator;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<PermissionSetGroup> groups = [
                SELECT Id
                FROM PermissionSetGroup
                WHERE DeveloperName = 'Volunteer_Coordinator' AND Status = 'Updated'
                LIMIT 1
            ];
            if (groups.isEmpty()) {
                return; // The role is still being computed after a deploy.
            }
            coordinator = TestUsers.standardUser('Coordwithoutset');
            insert new PermissionSetAssignment(
                AssigneeId = coordinator.Id,
                PermissionSetGroupId = groups[0].Id
            );
        }
        String name = [SELECT Name FROM User WHERE Id = :coordinator.Id].Name;
        System.runAs(admin()) {
            Map<String, Object> missing = finding('volunteer_coordinator_access');
            Assert.isNotNull(missing, 'The coordinator without the set is reported');
            Assert.isTrue(((String) missing.get('detail')).contains(name), 'They are named');
            Assert.isTrue(
                ((String) missing.get('fixTarget'))
                    .endsWith(VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS),
                'The fix gives the set'
            );
            VolunteersHealthCheckExtension extension = new VolunteersHealthCheckExtension();
            List<String> scope = extension.fixScope(
                VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS
            );
            Assert.isTrue(scope.contains(name), 'The fix scope names them');
            Assert.isNotNull(
                extension.fixLabel(VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS),
                'The fix has a label'
            );
            Assert.isNull(extension.fixLabel('someoneElsesFix'), 'Another key is not ours');

            Test.startTest();
            String outcome = extension.runFix(
                VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS,
                scope
            );
            Test.stopTest();

            Assert.isTrue(outcome.contains(name), 'The outcome names who is being given it');
            List<String> after = extension.fixScope(
                VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS
            );
            Assert.isFalse(after.contains(name), 'They hold the set now');
        }
    }

    @IsTest
    static void aCoordinatorHoldingVolunteersAdminIsNotReported() {
        User coordinator;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<PermissionSetGroup> groups = [
                SELECT Id
                FROM PermissionSetGroup
                WHERE DeveloperName = 'Volunteer_Coordinator' AND Status = 'Updated'
                LIMIT 1
            ];
            if (groups.isEmpty()) {
                return; // The role is still being computed after a deploy.
            }
            coordinator = TestUsers.standardUserWith(
                'Coordwithadmin',
                new List<String>{ VolunteersTestData.ADMIN }
            );
            insert new PermissionSetAssignment(
                AssigneeId = coordinator.Id,
                PermissionSetGroupId = groups[0].Id
            );
        }
        String name = [SELECT Name FROM User WHERE Id = :coordinator.Id].Name;
        System.runAs(admin()) {
            List<String> scope = new VolunteersHealthCheckExtension()
                .fixScope(VolunteersHealthCheckExtension.FIX_KEY_COORDINATOR_ACCESS);
            Assert.isFalse(
                scope.contains(name),
                'Volunteers Admin can approve hours and work with shifts, so they are not missing it'
            );
        }
    }

    @IsTest
    static void aShippedVolunteerTotalTurnedOffIsReported() {
        // Turning a total off is done in the Rollup Builder, which needs its own admin set.
        User rollupAdmin = TestUsers.withPermissionSets(
            new List<String>{
                TestUsers.CORE_ADMIN,
                VolunteersTestData.ADMIN,
                'Rollup_Builder_Admin'
            }
        );
        System.runAs(rollupAdmin) {
            RollupService.ensureDefaultsDuringInstall('VolunteersHealthCheckExtensionTest');
            List<Rollup_Definition__c> shipped = [
                SELECT Id
                FROM Rollup_Definition__c
                WHERE Definition_Key__c = 'Volunteer_Job_Total_Hours'
            ];
            if (shipped.isEmpty()) {
                return; // Nothing materialized, so there is nothing to turn off.
            }
            Assert.isNull(finding('volunteer_rollups_off'), 'All shipped totals are active');

            update new Rollup_Definition__c(Id = shipped[0].Id, Active__c = false);
            Map<String, Object> off = finding('volunteer_rollups_off');

            Assert.isNotNull(off, 'The total turned off is reported');
            Assert.isTrue(((String) off.get('title')).startsWith('1 '), 'Only that one');
            Assert.isTrue(
                ((String) off.get('fixTarget')).endsWith('Rollup_Builder'),
                'The fix opens Rollup Builder'
            );
        }
    }

    @IsTest
    static void coresReportCarriesTheVolunteersFindings() {
        System.runAs(admin()) {
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            insert VolunteersTestData.newShift(pantry.Id, Datetime.now().addDays(-10), 3);

            Map<String, Object> all = byKey(HealthCheckService.run());

            Assert.isTrue(
                all.containsKey('volunteer_past_shifts_open'),
                'Core finds the Volunteers extension by name and folds its findings in'
            );
            Assert.isFalse(
                all.containsKey('check_failed_volunteers_extension'),
                'The extension did not fail'
            );
        }
    }

    @IsTest
    static void noFindingsForAViewerWhoMayNotManageSettingsOrWhileTurnedOff() {
        User staff = TestUsers.standardUserWith(
            'Healthstaff',
            new List<String>{ VolunteersTestData.CORE_STAFF, 'Volunteers_Staff' }
        );
        System.runAs(admin()) {
            Volunteer_Job__c pantry = VolunteersTestData.job('Pantry');
            insert VolunteersTestData.newShift(pantry.Id, Datetime.now().addDays(-10), 3);
            BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
            settings.Modules_Turned_Off__c = ShiftScheduleService.MODULE_NAME;
            TestDataFactory.saveSettings(settings);

            Assert.isTrue(
                new VolunteersHealthCheckExtension().findings().isEmpty(),
                'Nothing is reported while Volunteers is turned off'
            );
        }
        System.runAs(staff) {
            Assert.isTrue(
                new VolunteersHealthCheckExtension().findings().isEmpty(),
                'A viewer who may not manage settings is asked nothing'
            );
            try {
                VolunteerHealthCheckSelector.hoursWaitingSince(Datetime.now(), 1);
                Assert.fail('The selector refuses them too');
            } catch (VolunteerHealthCheckSelector.NotAllowedException refused) {
                Assert.isNotNull(refused.getMessage(), 'Refused');
            }
        }
    }
}
