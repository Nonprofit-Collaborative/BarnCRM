/**
 * Tests for CoexistenceService (feature C-07).
 *
 * Maria's org decides the mode; the package only proposes one. These tests cover the
 * proposal, the confirmation, the refusal to overwrite a choice already made, and who is
 * allowed to make one.
 */
@IsTest
private class CoexistenceServiceTest {
    @IsTest
    static void modeIsNullUntilSomebodyConfirmsOne() {
        System.runAs(TestUsers.admin()) {
            System.assertEquals(
                null,
                CoexistenceService.getCurrentMode(),
                'A fresh org has no confirmed coexistence mode.'
            );
        }
    }

    @IsTest
    static void membershipDefaultsToContactMode() {
        System.runAs(TestUsers.admin()) {
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'Contact mode is the default until something changes it.'
            );
        }
    }

    @IsTest
    static void npspOrgGetsNpspCoexistence() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNpsp = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            String applied = CoexistenceService.applyRecommendedIfUnset();
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                applied,
                'NPSP org, NPSP coexistence.'
            );
            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                CoexistenceService.getCurrentMode(),
                'The recommendation is saved, not only returned.'
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'NPSP coexistence keeps contact membership.'
            );
        }
    }

    @IsTest
    static void personAccountsOrgGetsJunctionMembershipWithTheMode() {
        System.runAs(TestUsers.admin()) {
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            String applied = CoexistenceService.applyRecommendedIfUnset();
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MODE_STANDALONE,
                applied,
                'Person Accounts alone name no other product, so the org is Standalone.'
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'Person Accounts require junction membership, applied in the same save.'
            );
        }
    }

    @IsTest
    static void aConfirmedModeIsNeverOverwritten() {
        System.runAs(TestUsers.admin()) {
            CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);

            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasNpsp = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            String applied = CoexistenceService.applyRecommendedIfUnset();
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MODE_STANDALONE,
                applied,
                'Maria chose standalone: detection does not argue with her.'
            );
        }
    }

    @IsTest
    static void setModeAcceptsEveryValidMode() {
        System.runAs(TestUsers.admin()) {
            CoexistenceService.setMode(CoexistenceService.MODE_NPSP);
            System.assertEquals(
                CoexistenceService.MODE_NPSP,
                CoexistenceService.getCurrentMode(),
                'NPSP coexistence can be chosen by hand.'
            );

            CoexistenceService.setMode(CoexistenceService.MODE_NONPROFIT_CLOUD);
            System.assertEquals(
                CoexistenceService.MODE_NONPROFIT_CLOUD,
                CoexistenceService.getCurrentMode(),
                'Nonprofit Cloud coexistence can be chosen by hand.'
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'Choosing Nonprofit Cloud by hand still brings junction membership with it.'
            );
        }
    }

    @IsTest
    static void setModeRejectsAnythingElse() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;
            try {
                CoexistenceService.setMode('Whatever');
            } catch (CoexistenceService.CoexistenceException e) {
                refused = true;
                System.assert(
                    e.getMessage().contains('Whatever'),
                    'The message names the value that was refused.'
                );
            }
            System.assert(refused, 'An unknown mode is refused rather than saved.');
        }
    }

    @IsTest
    static void setModeRejectsBlank() {
        System.runAs(TestUsers.admin()) {
            Boolean refused = false;
            try {
                CoexistenceService.setMode(null);
            } catch (CoexistenceService.CoexistenceException e) {
                refused = true;
            }
            System.assert(refused, 'An empty mode is refused.');
        }
    }

    @IsTest
    static void applyModeAcceptsEveryValidMode() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                CoexistenceService.applyMode(CoexistenceService.MODE_STANDALONE);
                System.assertEquals(
                    CoexistenceService.MODE_STANDALONE,
                    CoexistenceService.getCurrentMode(),
                    'Standalone can be applied by an administrator.'
                );

                CoexistenceService.applyMode(CoexistenceService.MODE_NPSP);
                System.assertEquals(
                    CoexistenceService.MODE_NPSP,
                    CoexistenceService.getCurrentMode(),
                    'NPSP coexistence can be applied by an administrator.'
                );

                CoexistenceService.applyMode(CoexistenceService.MODE_NONPROFIT_CLOUD);
                System.assertEquals(
                    CoexistenceService.MODE_NONPROFIT_CLOUD,
                    CoexistenceService.getCurrentMode(),
                    'Nonprofit Cloud coexistence can be applied by an administrator.'
                );
            }

        }
    }

    @IsTest
    static void applyModeBringsJunctionMembershipWithNonprofitCloud() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                System.assertEquals(
                    CoexistenceService.MEMBERSHIP_CONTACT,
                    CoexistenceService.getMembershipMode(),
                    'Membership starts in contact mode.'
                );

                CoexistenceService.applyMode(CoexistenceService.MODE_NONPROFIT_CLOUD);

                System.assertEquals(
                    CoexistenceService.MEMBERSHIP_JUNCTION,
                    CoexistenceService.getMembershipMode(),
                    'Person Accounts require junction membership, applied in the same save.'
                );
            }

        }
    }

    @IsTest
    static void applyModeRejectsAnythingElse() {
        System.runAs(TestUsers.admin()) {
            User maria = HealthCheckTestHelper.mariaWithManageSettings();

            System.runAs(maria) {
                Boolean refused = false;
                try {
                    CoexistenceService.applyMode('Whatever');
                } catch (CoexistenceService.CoexistenceException e) {
                    refused = true;
                    System.assert(
                        e.getMessage().contains('Whatever'),
                        'The message names the value that was refused.'
                    );
                }
                System.assert(refused, 'An unknown mode is refused rather than saved.');
                System.assertEquals(
                    null,
                    CoexistenceService.getCurrentMode(),
                    'A refused value leaves the org without a mode rather than with a wrong one.'
                );
            }

        }
    }

    @IsTest
    static void applyModeRefusesSomeoneWithoutThePermission() {
        System.runAs(TestUsers.admin()) {
            User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

            System.runAs(priya) {
                Boolean refused = false;
                try {
                    CoexistenceService.applyMode(CoexistenceService.MODE_NPSP);
                } catch (CoexistenceService.CoexistenceException e) {
                    refused = true;
                    System.assertEquals(
                        System.Label.Core_HealthCheck_PermissionRequired,
                        e.getMessage(),
                        'Priya is told what permission she needs and who to ask for it.'
                    );
                }
                System.assert(
                    refused,
                    'Changing how the whole package behaves needs the permission.'
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
    static void anExplicitContactChoiceSurvivesNonprofitCloudDetection() {
        System.runAs(TestUsers.admin()) {
            // Maria's org has Person Accounts switched on but stores everyone as a contact, and
            // she chose the simple way of belonging on purpose. Neither detection nor choosing
            // the Nonprofit Cloud mode by hand is allowed to override that choice.
            SettingsService.saveValues(
                new Map<String, Object>{
                    CoexistenceService.KEY_MEMBERSHIP_MODE => CoexistenceService.MEMBERSHIP_CONTACT
                }
            );
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;

            Test.startTest();
            CoexistenceService.applyRecommendedIfUnset();
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'Detection proposes the flexible way only where nobody has chosen.'
            );

            CoexistenceService.setMode(CoexistenceService.MODE_NONPROFIT_CLOUD);
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MODE_NONPROFIT_CLOUD,
                CoexistenceService.getCurrentMode(),
                'The coexistence mode itself is still set.'
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'And the way of belonging Maria chose is left alone.'
            );
        }
    }

    @IsTest
    static void switchingToTheSimpleWayIsRefusedWhileMembershipRecordsExist() {
        System.runAs(TestUsers.admin()) {
            // In the flexible way, saving a person creates their household and the membership
            // record joining them to it. The simple way cannot see that record, so switching
            // would make the household read as empty.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
            insert HouseholdTestDataFactory.newContact('Maria', 'Garcia');
            System.assertEquals(
                1,
                CoexistenceService.countPeopleWithMembershipRecords(),
                'Maria belongs to her household through a membership record.'
            );

            Test.startTest();
            String refusal = attemptMembershipMode(CoexistenceService.MEMBERSHIP_CONTACT);
            Test.stopTest();

            System.assertNotEquals(null, refusal, 'The switch is refused rather than saved.');
            System.assert(
                refusal.contains('1 people'),
                'The message says how many people would be affected: ' + refusal
            );
            System.assert(
                refusal.contains('migration'),
                'And that a migration is what it would take: ' + refusal
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'Nothing was written on the way to being refused.'
            );
        }
    }

    @IsTest
    static void switchingToTheFlexibleWayIsRefusedWhilePeopleAreLinkedStraightToAHousehold() {
        System.runAs(TestUsers.admin()) {
            // In the simple way, a person sits on their household account. Automatic creation
            // in the flexible way leaves such a person alone, so they would never get a
            // membership record and would belong to no household the flexible way can see.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;
            Contact maria = HouseholdTestDataFactory.newContact('Maria', 'Garcia');
            maria.AccountId = household.Id;
            insert maria;

            Test.startTest();
            String refusal = attemptMembershipMode(CoexistenceService.MEMBERSHIP_JUNCTION);
            Test.stopTest();

            System.assertNotEquals(null, refusal, 'The switch is refused rather than saved.');
            System.assert(
                refusal.contains('1 people'),
                'The message says how many people would be affected: ' + refusal
            );
            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'Nothing was written on the way to being refused.'
            );
        }
    }

    @IsTest
    static void theHealthCheckFixIsRefusedWithTheSameReason() {
        System.runAs(TestUsers.admin()) {
            // The Health Check button goes through applyJunctionMembership, which has to carry
            // the reason back as this class's own exception for the panel to show it.
            HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);
            Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
            insert household;
            Contact maria = HouseholdTestDataFactory.newContact('Maria', 'Garcia');
            maria.AccountId = household.Id;
            insert maria;

            String refusal;
            try {
                CoexistenceService.applyJunctionMembership();
            } catch (CoexistenceService.CoexistenceException e) {
                refusal = e.getMessage();
            }

            System.assertNotEquals(null, refusal, 'The fix is refused rather than applied.');
            System.assert(refusal.contains('1 people'), 'With the count: ' + refusal);
        }
    }

    @IsTest
    static void anOrgWithNoHouseholdDataMaySwitchEitherWay() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            System.assertEquals(
                null,
                attemptMembershipMode(CoexistenceService.MEMBERSHIP_JUNCTION),
                'A fresh org may choose the flexible way.'
            );
            System.assertEquals(
                null,
                attemptMembershipMode(CoexistenceService.MEMBERSHIP_CONTACT),
                'And back to the simple way, because there is nobody to strand.'
            );
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'The last choice is the one in force.'
            );
        }
    }

    /**
     * Tries to save the given way of belonging the way the settings console does, and
     * returns the reason it was refused, or null when it was saved.
     */
    private static String attemptMembershipMode(String mode) {
        try {
            SettingsService.saveValues(
                new Map<String, Object>{ CoexistenceService.KEY_MEMBERSHIP_MODE => mode }
            );
            return null;
        } catch (SettingsService.SettingsException refused) {
            return refused.getMessage();
        }
    }

    @IsTest
    static void junctionMembershipCanBeAppliedOnItsOwn() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            CoexistenceService.applyJunctionMembership();
            Test.stopTest();

            System.assertEquals(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'The membership fix moves household membership to the junction.'
            );
        }
    }
}
