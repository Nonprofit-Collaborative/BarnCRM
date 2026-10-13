/**
 * Tests for HealthCheckController (feature C-11).
 *
 * Reading the report needs nothing. Acting on a finding needs the Manage BarnCRM Settings
 * custom permission, and the controller checks it rather than trusting the component, so
 * both sides of that check are covered here.
 *
 * Both sides run as a named user. The user running the tests in a deployed org is an
 * administrator holding every packaged permission set, so a method that means "without the
 * permission" and does not run as Priya is asking the question of somebody who has it.
 */
@IsTest
private class HealthCheckControllerTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    @IsTest
    static void anyoneCanReadTheReport() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                OrgShapeDetector.overrideShape = npspShape();

                Test.startTest();
                HealthCheckService.Report report = HealthCheckController.getReport();
                Test.stopTest();

                System.assertNotEquals(
                    null,
                    report,
                    'The report is readable without any permission.'
                );
                System.assertNotEquals(null, report.findings, 'It carries its findings.');
                System.assertEquals(
                    CoexistenceService.MODE_NPSP,
                    report.recommendedMode,
                    'It says what this org shape calls for.'
                );
                System.assertEquals(
                    false,
                    report.canManageSettings,
                    'Priya has not been given the permission, and the report says so.'
                );
            }

        }
    }

    @IsTest
    static void applyingTheRecommendationNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                OrgShapeDetector.overrideShape = npspShape();

                Boolean refused = false;
                try {
                    HealthCheckController.applyRecommendedMode();
                } catch (AuraHandledException e) {
                    refused = true;
                }

                System.assert(
                    refused,
                    'Without the permission, the fix is refused rather than applied.'
                );
                System.assertEquals(
                    null,
                    CoexistenceService.getCurrentMode(),
                    'Nothing was written on the way to being refused.'
                );
            }

        }
    }

    @IsTest
    static void switchingMembershipNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                OrgShapeDetector.overrideShape = personAccountsShape();

                Boolean refused = false;
                try {
                    HealthCheckController.applyJunctionMembership();
                } catch (AuraHandledException e) {
                    refused = true;
                }

                System.assert(refused, 'Without the permission, the membership fix is refused.');
                System.assertEquals(
                    CoexistenceService.MEMBERSHIP_CONTACT,
                    CoexistenceService.getMembershipMode(),
                    'And membership is left where it was rather than switched.'
                );
            }

        }
    }

    @IsTest
    static void withThePermissionTheRecommendationIsApplied() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                OrgShapeDetector.overrideShape = npspShape();

                Test.startTest();
                HealthCheckService.Report report = HealthCheckController.applyRecommendedMode();
                Test.stopTest();

                System.assertEquals(
                    true,
                    report.canManageSettings,
                    'Maria holds the permission, so she sees the fix buttons.'
                );
                System.assertEquals(
                    CoexistenceService.MODE_NPSP,
                    CoexistenceService.getCurrentMode(),
                    'Taking the recommendation saves it.'
                );
                System.assertEquals(
                    false,
                    report.modeNeedsAttention,
                    'Once applied, the mode no longer needs attention.'
                );
            }

        }
    }

    @IsTest
    static void withThePermissionMembershipIsSwitched() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                OrgShapeDetector.overrideShape = personAccountsShape();

                Test.startTest();
                HealthCheckController.applyJunctionMembership();
                Test.stopTest();

                System.assertEquals(
                    CoexistenceService.MEMBERSHIP_JUNCTION,
                    CoexistenceService.getMembershipMode(),
                    'The membership fix does what its button says.'
                );
            }

        }
    }

    @IsTest
    static void turningOnAutomaticHouseholdsNeedsThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                OrgShapeDetector.overrideShape = personAccountsShape();

                Boolean refused = false;
                try {
                    HealthCheckController.enableAutomaticHouseholds();
                } catch (AuraHandledException e) {
                    refused = true;
                }

                System.assert(refused, 'Without the permission, the households fix is refused.');
            }

        }
    }

    @IsTest
    static void withThePermissionAutomaticHouseholdsAreTurnedOn() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                OrgShapeDetector.overrideShape = personAccountsShape();

                Test.startTest();
                HealthCheckController.enableAutomaticHouseholds();
                Test.stopTest();

                SettingsService.clearCaches();
                System.assertEquals(
                    true,
                    SettingsService.getSettings().Auto_Create_Households__c,
                    'The households fix does what its button says.'
                );
            }

        }
    }

    private static OrgShapeDetector.OrgShape npspShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        return shape;
    }

    private static OrgShapeDetector.OrgShape personAccountsShape() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        return shape;
    }
}
