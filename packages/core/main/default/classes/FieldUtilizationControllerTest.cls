/**
 * FieldUtilizationController: the Field Utilization page of the settings console. Every change
 * needs Manage BarnCRM Settings, and the results compare the latest run with the one before.
 */
@IsTest(testFor='ApexClass:FieldUtilizationController')
private class FieldUtilizationControllerTest {
    private static final String DISMISSAL = Duplicate_Dismissal__c.SObjectType.getDescribe(
            SObjectDescribeOptions.DEFERRED
        )
        .getName();
    private static final String REASON = Duplicate_Dismissal__c.Reason__c.getDescribe().getName();

    private static User maria() {
        return TestDataFactory.createUser('Maria', new List<String>{ 'BarnCRM_Admin' });
    }

    private static List<Duplicate_Dismissal__c> insertDismissals(
        Integer howMany,
        Integer withReason
    ) {
        List<Duplicate_Dismissal__c> rows = new List<Duplicate_Dismissal__c>();
        for (Integer i = 0; i < howMany; i++) {
            rows.add(
                new Duplicate_Dismissal__c(
                    Pair_Key__c = 'barn-pair-' + i,
                    Reason__c = i < withReason ? 'Not the same person' : null
                )
            );
        }
        insert rows;
        return rows;
    }

    /** One run, synchronously, as the batch would do it. */
    private static void countNow(Datetime takenAt) {
        FieldUtilizationService.Plan planned = FieldUtilizationService.plan(
            new List<String>{ DISMISSAL },
            null
        );
        List<Field_Utilization_Snapshot__c> rows = new List<Field_Utilization_Snapshot__c>();
        for (FieldUtilizationService.Item item : planned.items) {
            rows.addAll(
                FieldUtilizationService.count(item, planned.totals.get(item.objectName), takenAt)
            );
        }
        FieldUtilizationService.save(rows);
    }

    private static String messageOf(Exception caught) {
        return caught.getMessage();
    }

    @IsTest
    static void aSecondRunShowsTheChangeSinceTheFirst() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.Results results;
            System.runAs(maria()) {
                List<Duplicate_Dismissal__c> rows = insertDismissals(200, 100);
                countNow(System.now().addDays(-7));
                for (Integer i = 100; i < 150; i++) {
                    rows[i].Reason__c = 'Different people';
                }
                update rows;
                countNow(System.now());

                Test.startTest();
                results = FieldUtilizationController.getResults(DISMISSAL);
                Test.stopTest();
            }

            Assert.isNotNull(results.previousTakenAt, 'The run before is found.');
            FieldUtilizationController.FieldRow reasonRow;
            for (FieldUtilizationController.FieldRow row : results.rows) {
                if (row.fieldName == REASON) {
                    reasonRow = row;
                }
            }
            Assert.isNotNull(reasonRow, 'Reason is in the latest results.');
            Assert.areEqual(150, reasonRow.filled, 'Filled in the latest run.');
            Assert.areEqual(200, reasonRow.total, 'Records looked at.');
            Assert.areEqual(75.0, reasonRow.percent, 'The latest share, as a percentage.');
            Assert.areEqual(25.0, reasonRow.change, 'Up 25 points since the run before.');
        }
    }

    @IsTest
    static void theFirstRunHasNoChangeToShow() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.Results results;
            System.runAs(maria()) {
                insertDismissals(200, 50);
                countNow(System.now());
                results = FieldUtilizationController.getResults(DISMISSAL);
            }

            Assert.isNull(results.previousTakenAt, 'There is no earlier run.');
            Assert.areEqual(1, results.rows.size(), 'One countable field.');
            Assert.areEqual(25.0, results.rows[0].percent, '50 of 200.');
            Assert.isNull(results.rows[0].change, 'No change without a run to compare with.');
        }
    }

    @IsTest
    static void savingObjectsKeepsWhatDescribeKnowsAndRefusesTheRest() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.PageView view;
            String refusal;
            System.runAs(maria()) {
                view = FieldUtilizationController.saveObjects(
                    new List<String>{ DISMISSAL, DISMISSAL }
                );
                try {
                    FieldUtilizationController.saveObjects(
                        new List<String>{ 'Not_A_Real_Object__c' }
                    );
                } catch (AuraHandledException caught) {
                    refusal = messageOf(caught);
                }
            }

            Assert.areEqual(
                new List<String>{ DISMISSAL },
                view.tracked,
                'Saved once, as describe names it.'
            );
            Assert.areEqual(
                String.format(
                    System.Label.Core_FieldUtilization_UnknownObject,
                    new List<Object>{ 'Not_A_Real_Object__c' }
                ),
                refusal,
                'An object describe does not know is refused by name (R-FU1).'
            );
            Assert.areEqual(
                DISMISSAL,
                BarnCRM_Settings__c.getOrgDefaults().Field_Utilization_Objects__c,
                'The refused save changed nothing.'
            );
        }
    }

    @IsTest
    static void someoneWithoutThePermissionCannotChangeAnything() {
        System.runAs(TestUsers.admin()) {
            User david = TestDataFactory.createUser('David', new List<String>{ 'BarnCRM_Staff' });
            String refusal;
            System.runAs(david) {
                try {
                    FieldUtilizationController.saveObjects(new List<String>{ DISMISSAL });
                } catch (AuraHandledException caught) {
                    refusal = messageOf(caught);
                }
            }

            Assert.areEqual(
                System.Label.Core_FieldUtilization_PermissionRequired,
                refusal,
                'Refused.'
            );
        }
    }

    @IsTest
    static void anAdministratorCanScheduleAndStopTheWeeklyCount() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.PageView started;
            FieldUtilizationController.PageView stopped;
            // The running user's profile, as the seasonal swap's test does: scheduling Apex is
            // what this test proves, not what a Standard User profile allows.
            User admin = TestDataFactory.createUserOnTheRunningUsersProfile(
                'Maria',
                new List<String>{ 'BarnCRM_Admin' }
            );
            System.runAs(admin) {
                Test.startTest();
                started = FieldUtilizationController.setSchedule(true);
                stopped = FieldUtilizationController.setSchedule(false);
                Test.stopTest();
            }

            Assert.isTrue(started.scheduled, 'Schedule actually schedules it.');
            Assert.isNotNull(started.nextRunAt, 'And says when it next runs.');
            Assert.isFalse(stopped.scheduled, 'Stop actually stops it.');
        }
    }

    @IsTest
    static void countNowNeedsSomethingChosen() {
        System.runAs(TestUsers.admin()) {
            String refusal;
            System.runAs(maria()) {
                try {
                    FieldUtilizationController.runNow();
                } catch (AuraHandledException caught) {
                    refusal = messageOf(caught);
                }
            }

            Assert.areEqual(
                System.Label.Core_FieldUtilization_NothingChosen,
                refusal,
                'Nothing to count.'
            );
        }
    }

    @IsTest
    static void countNowCountsTheChosenObjects() {
        System.runAs(TestUsers.admin()) {
            System.runAs(maria()) {
                insertDismissals(200, 10);
                FieldUtilizationController.saveObjects(new List<String>{ DISMISSAL });
                Test.startTest();
                FieldUtilizationController.runNow();
                Test.stopTest();
            }

            Assert.areEqual(
                10,
                [
                    SELECT Filled_Count__c
                    FROM Field_Utilization_Snapshot__c
                    WHERE Field_Name__c = :REASON
                ]
                .Filled_Count__c,
                'Count now ran the count over the saved objects.'
            );
        }
    }

    @IsTest
    static void thePickerOffersPeopleAccountsAndCustomObjectsButNotTheSnapshots() {
        System.runAs(TestUsers.admin()) {
            FieldUtilizationController.PageView view;
            System.runAs(maria()) {
                view = FieldUtilizationController.getView();
            }

            Set<String> offered = new Set<String>();
            for (FieldUtilizationController.Option option : view.choosable) {
                offered.add(option.value);
            }
            Assert.isTrue(
                offered.contains(
                    Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                ),
                'Account.'
            );
            Assert.isTrue(
                offered.contains(
                    Contact.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                ),
                'Contact.'
            );
            Assert.isTrue(offered.contains(DISMISSAL), 'A custom object.');
            Assert.isFalse(
                offered.contains(
                    Field_Utilization_Snapshot__c.SObjectType.getDescribe(
                            SObjectDescribeOptions.DEFERRED
                        )
                        .getName()
                ),
                'Never its own snapshots.'
            );
            Assert.isTrue(view.canManage, 'Maria holds Manage BarnCRM Settings.');
            Assert.isFalse(view.scheduled, 'Nothing schedules the count on install.');
        }
    }
}
