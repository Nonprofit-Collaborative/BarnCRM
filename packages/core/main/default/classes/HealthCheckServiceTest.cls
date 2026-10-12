/**
 * Tests for HealthCheckService (feature C-11), one per finding path.
 *
 * Org shape is forced through the detector's test override so that every path runs on every
 * org shape in the CI matrix, and the two access counts through the service's own override,
 * so that a finding is asserted against numbers the test chose rather than against whoever
 * happens to hold a permission set in the org the tests run in.
 */
@IsTest
private class HealthCheckServiceTest {
    @IsTest
    static void npspOrgReportsNpspDetectedAndRecommendsIt() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        HealthCheckService.Finding orgShape = find(findings, 'org_shape');
        System.assertNotEquals(null, orgShape, 'The report always opens with the org shape.');
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_NpspDetected),
            'An org with NPSP installed is told, in those words, that NPSP was detected.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_CoexistenceMode_Npsp),
            'The org shape finding names the mode it recommends.'
        );
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            CoexistenceService.applyRecommendedIfUnset(),
            'The C-11 criterion: NPSP detected means the mode defaults to NPSP coexistence.'
        );
    }

    @IsTest
    static void personAccountsOrgReportsWhatItFound() {
        OrgShapeDetector.overrideShape = shape(false, true, true, true);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        HealthCheckService.Finding orgShape = find(findings, 'org_shape');
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_PersonAccountsDetected),
            'Person Accounts are named in the org shape card.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_IndustriesDetected),
            'Nonprofit Cloud objects are named in the org shape card.'
        );
        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_SalesObjectsDetected),
            'Standard Sales and Service Cloud objects are named too.'
        );
    }

    @IsTest
    static void freshOrgSaysNothingElseIsInstalled() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding orgShape = find(HealthCheckService.run(), 'org_shape');

        System.assert(
            orgShape.detail.contains(System.Label.Core_HealthCheck_NothingDetected),
            'A fresh org is told it is a fresh org, not given an empty list.'
        );
    }

    @IsTest
    static void modeUnsetIsAWarningWithAOneClickFix() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_unset'
        );

        System.assertNotEquals(null, finding, 'An unconfirmed mode is reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Not confirming a mode is worth knowing about, not an error.'
        );
        System.assertEquals(
            HealthCheckService.FIX_APPLY_RECOMMENDED_MODE,
            finding.fixTarget,
            'The fix applies the recommendation.'
        );
    }

    @IsTest
    static void modeThatDoesNotMatchTheOrgIsAWarning() {
        CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_mismatch'
        );

        System.assertNotEquals(null, finding, 'A mode that does not match the org is reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'A mismatch may be deliberate, so it is a warning.'
        );
    }

    @IsTest
    static void modeThatMatchesTheOrgIsReportedAsFine() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_NPSP);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'coexistence_mode_match'
        );

        System.assertNotEquals(null, finding, 'Health Check says when something is right.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'A matching mode is information.'
        );
    }

    @IsTest
    static void contactMembershipWithPersonAccountsIsAnError() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'membership_mode_person_accounts'
        );

        System.assertNotEquals(null, finding, 'This combination is always reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_ERROR,
            finding.severity,
            'Contact membership in a Person Accounts org is broken, not merely untidy.'
        );
        System.assertEquals(
            HealthCheckService.FIX_APPLY_JUNCTION_MEMBERSHIP,
            finding.fixTarget,
            'The fix switches household membership to the junction.'
        );
    }

    @IsTest
    static void contactMembershipChosenOnPurposeIsNotAnErrorWhileEveryoneIsAContact() {
        // Maria's org has Person Accounts on but stores everyone as a contact, and she chose
        // the simple way herself. That is a choice, not a fault, until people stored as
        // accounts appear. No test org in the CI matrix has any, so this is the quiet case.
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertEquals(
            null,
            find(findings, 'membership_mode_person_accounts'),
            'A way of belonging chosen on purpose is not reported as the default not fitting.'
        );
        System.assertEquals(
            null,
            find(findings, 'membership_mode_people_as_accounts'),
            'And with nobody stored as an account there is nothing to warn about.'
        );
    }

    @IsTest
    static void membershipRecordsTheSimpleWayCannotSeeAreAnError() {
        // Membership records exist, and the setting has been moved to the simple way by a
        // route the settings write does not guard, here a direct upsert. The households now
        // read as empty and nothing else says why.
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        insert HouseholdTestDataFactory.newContact('Maria', 'Garcia');
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_CONTACT);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'membership_data_hidden'
        );

        System.assertNotEquals(null, finding, 'Membership the mode cannot see is reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_ERROR,
            finding.severity,
            'People vanishing from their households is broken, not untidy.'
        );
        System.assert(
            finding.detail.contains('1 people'),
            'The finding says how many people are affected: ' + finding.detail
        );
        System.assertEquals(
            HealthCheckService.SECTION_HOUSEHOLDS,
            finding.fixTarget,
            'The fix opens the household settings, where the way of belonging lives.'
        );
    }

    @IsTest
    static void peopleLinkedStraightToAHouseholdTheFlexibleWayCannotSeeAreAnError() {
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();
        Account household = HouseholdTestDataFactory.newHousehold('The Garcia Family');
        insert household;
        Contact maria = HouseholdTestDataFactory.newContact('Maria', 'Garcia');
        maria.AccountId = household.Id;
        insert maria;

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'membership_data_hidden'
        );

        System.assertNotEquals(null, finding, 'A person the mode cannot see is reported.');
        System.assert(
            finding.detail.contains('1 people'),
            'The finding says how many people are affected: ' + finding.detail
        );
    }

    @IsTest
    static void membershipEveryoneCanSeeIsNotReported() {
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);
        insert HouseholdTestDataFactory.newContact('Maria', 'Garcia');

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'membership_data_hidden'),
            'Membership records in the flexible way are exactly what that way reads.'
        );
    }

    @IsTest
    static void junctionMembershipWithPersonAccountsIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        CoexistenceService.setMode(CoexistenceService.MODE_AGENTFORCE_NONPROFIT);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'membership_mode_person_accounts'),
            'Once membership is on the junction there is nothing to report.'
        );
    }

    /**
     * The state ADR-0037 closes, and the finding that makes it impossible to sit in it
     * silently: membership on the junction, automatic creation off, so no new person gets a
     * household and nothing else in the product says so.
     */
    @IsTest
    static void junctionMembershipWithNoCreationPathIsAnError() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        HouseholdTestDataFactory.junctionSettingsWithoutAutomaticHouseholds();

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'household_creation_disabled'
        );

        System.assertNotEquals(null, finding, 'The state is always reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_ERROR,
            finding.severity,
            'Nobody is getting a household, which is broken rather than untidy.'
        );
        System.assertEquals(
            HealthCheckService.CATEGORY_SETTINGS,
            finding.category,
            'It is a settings finding: the setting is what has to change.'
        );
        System.assertEquals(
            HealthCheckService.FIX_ENABLE_AUTOMATIC_HOUSEHOLDS,
            finding.fixTarget,
            'And the fix turns automatic household creation on.'
        );
    }

    @IsTest
    static void junctionMembershipWithAutomaticHouseholdsIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, true, false, false);
        HouseholdTestDataFactory.settings(HouseholdTestDataFactory.MODE_JUNCTION);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'household_creation_disabled'),
            'Every new person is getting a household, so there is nothing to report.'
        );
    }

    /**
     * Contact mode is left alone by this check on purpose: the person still has a household
     * field anyone can fill in, and turning creation off there is an ordinary preference.
     */
    @IsTest
    static void contactMembershipWithAutomaticHouseholdsOffIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        Nonprofit_Settings__c settings = HouseholdTestDataFactory.settings(
            HouseholdTestDataFactory.MODE_CONTACT
        );
        settings.Auto_Create_Households__c = false;
        HouseholdTestDataFactory.save(settings);

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'household_creation_disabled'),
            'This check is about the mode with no household field to fall back on.'
        );
    }

    @IsTest
    static void industriesObjectsWithoutConnectAreReported() {
        OrgShapeDetector.overrideShape = shape(false, false, true, false);

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'connect_module_absent'
        );

        System.assertNotEquals(null, finding, 'The gift mirror is worth mentioning once.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Nothing is broken, so this is information.'
        );
        System.assertEquals(
            null,
            finding.fixTarget,
            'There is nothing to click: Connect is a separate install in v0.6.'
        );
    }

    @IsTest
    static void multiCurrencyIsAWarning() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.isMultiCurrency = true;
        OrgShapeDetector.overrideShape = orgShape;

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'multi_currency');

        System.assertNotEquals(null, finding, 'Multi-currency is detected and reported.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Multi-currency is unsupported in v1 but does not break anything.'
        );
        System.assertEquals(
            HealthCheckService.CATEGORY_LICENSES,
            finding.category,
            'Currency belongs with the license findings.'
        );
    }

    @IsTest
    static void anOrgWithNobodyInTheAdminRoleIsAnError() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(0, 0);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'no_nonprofit_admin'
            );

            System.assertNotEquals(
                null,
                finding,
                'An org where nobody can administer Open Impact is told so.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_ERROR,
                finding.severity,
                'Nobody able to administer the app is an error.'
            );
            System.assertEquals(
                HealthCheckService.SECTION_ACCESS,
                finding.fixTarget,
                'The fix opens the Access page.'
            );
        }
    }

    @IsTest
    static void anOrgThatIsSetUpProperlyIsToldNothingAboutAccess() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(1, 0);

            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            System.assertEquals(
                null,
                find(findings, 'no_nonprofit_admin'),
                'One administrator is enough: there is nothing to say about it.'
            );
            System.assertEquals(
                null,
                find(findings, 'users_without_access'),
                'Everyone can see the app, so nobody is reported as locked out.'
            );
        }
    }

    @IsTest
    static void anAdministratorAssignedDirectlyStillCounts() {
        List<PermissionSet> packaged = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = :HealthCheckService.PERMISSION_SET_ADMIN
            LIMIT 1
        ];
        System.assert(
            !packaged.isEmpty(),
            'The Nonprofit Admin permission set is not in this org. It ships with the access ' +
            'feature (C-06), which has to merge before this test means anything.'
        );

        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        System.assertEquals(
            1,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE AssigneeId = :maria.Id AND PermissionSetId = :packaged[0].Id
            ],
            'Maria holds the admin permission set directly rather than through a group.'
        );

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'no_nonprofit_admin'),
                'Someone given the admin permission set by hand is still an administrator.'
            );
        }
    }

    @IsTest
    static void usersWithNoRoleAreCounted() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            HealthCheckService.accessCountsOverride = new FixedAccessCounts(1, 3);

            HealthCheckService.Finding finding = find(
                HealthCheckService.run(),
                'users_without_access'
            );

            System.assertNotEquals(
                null,
                finding,
                'Active people holding no packaged role are counted and reported.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'People who cannot see the app is a warning, not an error.'
            );
            System.assert(
                finding.detail.contains('3'),
                'The finding reports the number of people that were counted: ' + finding.detail
            );
        }
    }

    @IsTest
    static void someoneWhoCannotSeeTheAnswerIsNotGivenAWrongOne() {
        User priya = HealthCheckTestHelper.priyaWithoutManageSettings();

        System.runAs(priya) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);
            List<HealthCheckService.Finding> findings = HealthCheckService.run();

            System.assertEquals(
                null,
                find(findings, 'no_nonprofit_admin'),
                'Priya sees her own assignments and nothing else, so the count would be wrong.'
            );
            System.assertEquals(
                null,
                find(findings, 'users_without_access'),
                'The same is true of counting who cannot see the app.'
            );
            System.assertEquals(
                null,
                find(findings, 'error_log_new'),
                'And of counting errors she may not be allowed to read.'
            );

            HealthCheckService.Finding gate = find(findings, 'access_checks_need_admin');
            System.assertNotEquals(
                null,
                gate,
                'She is told why the access checks are missing rather than left guessing.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_INFO,
                gate.severity,
                'Not being an administrator is information, not a fault.'
            );
            System.assertNotEquals(
                null,
                find(findings, 'org_shape'),
                'Everything that does not depend on seeing other people still runs.'
            );
        }
    }

    @IsTest
    static void pausedAutomationIsReportedWhileItLasts() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        // The pause is not an editable setting with a shipped Setting Definition row: Maria sets
        // it from the Automation panel, and the settings service rightly refuses a key no row
        // names. The factory writes the same field the way the product does.
        Nonprofit_Settings__c paused = TestDataFactory.pausedSettings(2);
        // A pause set from the page has its resume scheduled with it (R-A5).
        AutomationResumeJob.scheduleAt(paused.Automation_Paused_Until__c);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'automation_paused');

        System.assertNotEquals(null, finding, 'A pause is always visible while it is on.');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Pausing is a normal thing to do during a load.'
        );
        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'automation_running'),
            'Automation cannot be both paused and running.'
        );
    }

    @IsTest
    static void aPauseNothingWillEndIsAWarning() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        // Written straight to the setting with no resume job, as a pause from before C-23 was.
        TestDataFactory.pausedSettings(2);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        HealthCheckService.Finding finding = find(findings, 'automation_paused_no_resume');

        Assert.isNotNull(finding, 'A pause with no automatic resume is reported.');
        Assert.areEqual(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Nothing will record its end, so it is a warning.'
        );
        Assert.areEqual(
            HealthCheckService.SECTION_AUTOMATION,
            finding.fixTarget,
            'The fix is the Automation page, where Resume is.'
        );
        Assert.isNull(find(findings, 'automation_paused'), 'One finding about the pause, not two.');
    }

    @IsTest
    static void aPauseEndingBeyondTheLongestOfferedIsAWarningEvenWithAJob() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        TestDataFactory.pausedSettings(AutomationControl.LONGEST_PAUSE_HOURS + 24);
        AutomationResumeJob.scheduleAt(System.now().addHours(1));

        HealthCheckService.Finding finding = find(
            HealthCheckService.run(),
            'automation_paused_no_resume'
        );

        Assert.isNotNull(finding, 'No page pause ends this late, so the job is not its end.');
        Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning.');
    }

    @IsTest
    static void aScheduledDigestThatStoppedRunningIsAWarning() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        Nonprofit_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Error_Digest_Last_Run__c = System.now()
            .addDays(-HealthCheckSettingsChecks.DIGEST_STALE_DAYS - 1);
        TestDataFactory.saveSettings(settings);
        ErrorDigestScheduler.start();

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'error_digest_stale');

        Assert.isNotNull(finding, 'Scheduled, but silent for three days.');
        Assert.areEqual(HealthCheckService.SEVERITY_WARNING, finding.severity, 'A warning.');
        Assert.areEqual(
            SettingSections.ERROR_LOG,
            finding.fixTarget,
            'Fixed where it is scheduled.'
        );
    }

    @IsTest
    static void aDigestThatRanTodayOrIsNotScheduledIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        Nonprofit_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Error_Digest_Last_Run__c = System.now()
            .addDays(-HealthCheckSettingsChecks.DIGEST_STALE_DAYS - 1);
        TestDataFactory.saveSettings(settings);

        Assert.isNull(
            find(HealthCheckService.run(), 'error_digest_stale'),
            'Not scheduled: an old last run means somebody stopped it.'
        );

        settings.Error_Digest_Last_Run__c = System.now().addHours(-3);
        TestDataFactory.saveSettings(settings);
        ErrorDigestScheduler.start();
        Assert.isNull(
            find(HealthCheckService.run(), 'error_digest_stale'),
            'Scheduled and ran this morning.'
        );
    }

    @IsTest
    static void automationThatIsRunningIsSaidSo() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'automation_running');

        System.assertNotEquals(
            null,
            finding,
            'Maria is told automation is running, so silence never has to be interpreted.'
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'Working normally is information.'
        );
    }

    @IsTest
    static void expiredPauseIsNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        TestDataFactory.pausedSettings(-1);

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertEquals(
            null,
            find(findings, 'automation_paused'),
            'A pause that has expired is not news.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'automation_running'),
            'Once the pause expires, automation is running again.'
        );
    }

    @IsTest
    static void unreadErrorsAreCounted() {
        insert new Error_Log__c(
            Timestamp__c = System.now(),
            Context__c = 'Health Check test',
            Message__c = 'Something went wrong and here is what to do about it.',
            Severity__c = 'Error',
            Status__c = 'New'
        );
        // Counting the Error Log needs read on the object and on Status, which is what the
        // packaged Nonprofit Admin permission set gives Maria, and mariaWithManageSettings
        // now assigns it because every audited settings save needs it too. Without that
        // access the selector keeps its promise and says nothing, which is what this test
        // used to be measuring.
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            HealthCheckService.Finding finding = find(HealthCheckService.run(), 'error_log_new');

            System.assertNotEquals(
                null,
                finding,
                'A new error is surfaced where Maria will see it.'
            );
            System.assertEquals(
                HealthCheckService.SEVERITY_WARNING,
                finding.severity,
                'Unread errors are a warning.'
            );
            System.assert(finding.title.contains('1'), 'The title says how many there are.');
        }
    }

    @IsTest
    static void noUnreadErrorsMeansNoFinding() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();

        System.runAs(maria) {
            OrgShapeDetector.overrideShape = shape(false, false, false, false);

            System.assertEquals(
                null,
                find(HealthCheckService.run(), 'error_log_new'),
                'An empty Error Log produces no finding at all.'
            );
        }
    }

    @IsTest
    static void twoFiscalYearsThatDisagreeAreReportedWithBothMonths() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = 1;

        HealthCheckService.Finding finding = find(HealthCheckService.run(), 'fiscal_year_mismatch');

        System.assertNotEquals(
            null,
            finding,
            'ADR-0025: the rollups are computed from the Nonprofit Settings month and the ' +
                'retention reports from the Setup month, so a disagreement makes every year based ' +
                'number wrong in a way nobody notices.'
        );
        System.assert(
            finding.detail.contains(FiscalYearSelector.monthName(7)),
            'The finding names the month Open Impact uses. Detail was: ' + finding.detail
        );
        System.assert(
            finding.detail.contains(FiscalYearSelector.monthName(1)),
            'And the month Setup uses, because the fix is deciding which one is right. ' +
                'Detail was: ' +
                finding.detail
        );
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'Nothing is broken today: the numbers are simply measured on two boundaries.'
        );
        System.assertEquals(
            HealthCheckService.SECTION_GENERAL,
            finding.fixTarget,
            'The one field an administrator can change from inside the app is in General ' +
            'settings, and the fix button opens it.'
        );
    }

    @IsTest
    static void twoFiscalYearsThatAgreeAreNotReported() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = 7;

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'fiscal_year_mismatch'),
            'Both fiscal years start in July, which is the state the check exists to ask for.'
        );
    }

    @IsTest
    static void aSetupFiscalYearNobodyCouldReadIsNotAMismatch() {
        OrgShapeDetector.overrideShape = shape(false, false, false, false);
        SettingsService.saveSystemValue('Fiscal_Year_Start_Month__c', 7);
        FiscalYearSelector.orgStartMonthOverridden = true;
        FiscalYearSelector.orgStartMonthOverride = null;

        System.assertEquals(
            null,
            find(HealthCheckService.run(), 'fiscal_year_mismatch'),
            'A value that could not be read is not evidence that the two disagree, so the ' +
            'report says nothing rather than accusing the org of a mismatch.'
        );
    }

    @IsTest
    static void oneFailingCheckDoesNotHideTheOthers() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckService.faultInjection = new BrokenCheck();

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        HealthCheckService.Finding failed = find(findings, 'check_failed_injected');
        System.assertNotEquals(null, failed, 'The check that failed says so, by name.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            failed.severity,
            'One check failing is a warning about the report, not an error about the org.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'The other eight answers are still there.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'coexistence_mode_unset'),
            'Including the ones that come after the failure.'
        );
    }

    @IsTest
    static void anErrorLoggerThatIsItselfBrokenDoesNotTakeTheReportDown() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckService.faultInjection = new BrokenCheck();
        HealthCheckService.loggerFault = new BrokenCheckException('The Error Log is unwritable.');

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertNotEquals(
            null,
            find(findings, 'check_failed_injected'),
            'The failure is still reported even when it could not be written down.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'And the rest of the report survives a logger that cannot log.'
        );
    }

    /**
     * A dependent package's findings (G-20 follow-up, ADR-0057): Core resolves
     * `HealthCheckExtensions.findAll()` and folds its list in, isolated exactly like a check
     * that throws. Core has no Giving package to install a real one, so the extension itself
     * is the test double here, the same way `ImportEntityProcessors` tests stand in for a row
     * processor.
     */
    @IsTest
    static void reportIncludesFindingsFromAnInstalledExtension() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckExtensions.overrides.put(
            'GivingHealthCheckExtension',
            new FakeExtension(
                new List<HealthCheckService.Finding>{
                    new HealthCheckService.Finding(
                        'unposted_gifts_closed_period',
                        'Title',
                        'Detail',
                        HealthCheckService.SEVERITY_WARNING,
                        HealthCheckService.CATEGORY_SETTINGS
                    )
                }
            )
        );

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertNotEquals(
            null,
            find(findings, 'unposted_gifts_closed_period'),
            'A finding the installed extension returns is folded into the one report.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'Core keeps reporting its own findings alongside the extension.'
        );
    }

    @IsTest
    static void noExtensionInstalledAddsNothingAndFailsNothing() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckExtensions.noneForTest = true;

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertEquals(
            null,
            find(findings, 'check_failed_giving_extension'),
            'An org with no extension installed is an ordinary org shape, not a failure.'
        );
        System.assertNotEquals(null, find(findings, 'org_shape'), 'The rest of the report runs.');
    }

    @IsTest
    static void anExtensionThatThrowsDoesNotTakeTheReportDown() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckExtensions.overrides.put('GivingHealthCheckExtension', new BrokenExtension());

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        HealthCheckService.Finding failed = find(findings, 'check_failed_giving_extension');
        System.assertNotEquals(null, failed, 'A broken extension says so, by name.');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            failed.severity,
            'The extension failing is a warning about the report, not an error about the org.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'org_shape'),
            'The rest of the report survives an extension that throws.'
        );
    }

    @IsTest
    static void oneExtensionThatThrowsDoesNotHideAnother() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);
        HealthCheckExtensions.overrides.put(
            'GivingHealthCheckExtension',
            new FakeExtension(
                new List<HealthCheckService.Finding>{
                    new HealthCheckService.Finding(
                        'unposted_gifts_closed_period',
                        'Title',
                        'Detail',
                        HealthCheckService.SEVERITY_WARNING,
                        HealthCheckService.CATEGORY_SETTINGS
                    )
                }
            )
        );
        HealthCheckExtensions.overrides.put('ConnectHealthCheckExtension', new BrokenExtension());

        List<HealthCheckService.Finding> findings = HealthCheckService.run();

        System.assertNotEquals(
            null,
            find(findings, 'unposted_gifts_closed_period'),
            'Giving\'s finding is reported.'
        );
        System.assertNotEquals(
            null,
            find(findings, 'check_failed_connect_extension'),
            'Connect\'s failure is reported by its own name.'
        );
    }

    private class FakeExtension implements HealthCheckExtension {
        private List<HealthCheckService.Finding> toReturn;
        FakeExtension(List<HealthCheckService.Finding> toReturn) {
            this.toReturn = toReturn;
        }
        public List<HealthCheckService.Finding> findings() {
            return toReturn;
        }
    }

    private class BrokenExtension implements HealthCheckExtension {
        public List<HealthCheckService.Finding> findings() {
            throw new BrokenCheckException('Giving could not be asked.');
        }
    }

    private class BrokenCheckException extends Exception {
    }

    private class BrokenCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            throw new BrokenCheckException('This check is broken on purpose.');
        }
    }

    @IsTest
    static void everyFindingCarriesACategoryAndASeverity() {
        OrgShapeDetector.overrideShape = shape(true, true, true, true);

        for (HealthCheckService.Finding finding : HealthCheckService.run()) {
            System.assertNotEquals(null, finding.key, 'Every finding has a key.');
            System.assertNotEquals(null, finding.title, 'Every finding has a title.');
            System.assertNotEquals(null, finding.detail, 'Every finding explains itself.');
            System.assert(
                finding.severity == HealthCheckService.SEVERITY_INFO ||
                    finding.severity == HealthCheckService.SEVERITY_WARNING ||
                    finding.severity == HealthCheckService.SEVERITY_ERROR,
                'Severity is one of the three the component knows how to draw.'
            );
            System.assert(
                finding.category == HealthCheckService.CATEGORY_ORG_SHAPE ||
                    finding.category == HealthCheckService.CATEGORY_LICENSES ||
                    finding.category == HealthCheckService.CATEGORY_ACCESS ||
                    finding.category == HealthCheckService.CATEGORY_SETTINGS,
                'Category is one of the four the component groups by.'
            );
        }
    }

    @IsTest
    static void reportCarriesTheModesAndThePermission() {
        OrgShapeDetector.overrideShape = shape(true, false, false, false);

        Test.startTest();
        HealthCheckService.Report report = HealthCheckService.buildReport();
        Test.stopTest();

        System.assertNotEquals(null, report.findings, 'The report carries the findings.');
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            report.recommendedMode,
            'The report says what is recommended.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Npsp,
            report.recommendedModeLabel,
            'The recommendation is labelled for a person to read.'
        );
        System.assertEquals(
            true,
            report.modeNeedsAttention,
            'An unconfirmed mode needs attention, which is what shows the button.'
        );
        System.assertNotEquals(
            null,
            report.orgShapeSummary,
            'The card summary is on the report, not rebuilt by the component.'
        );
    }

    @IsTest
    static void modeLabelFallsBackWhenNothingIsSet() {
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Unset,
            HealthCheckService.modeLabel(null),
            'An unset mode reads as unset, never as blank.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_Standalone,
            HealthCheckService.modeLabel(CoexistenceService.MODE_STANDALONE),
            'Standalone has a name a person recognizes.'
        );
        System.assertEquals(
            System.Label.Core_CoexistenceMode_AgentforceNonprofit,
            HealthCheckService.modeLabel(CoexistenceService.MODE_AGENTFORCE_NONPROFIT),
            'Agentforce Nonprofit coexistence has a name a person recognizes.'
        );
    }

    @IsTest
    static void summaryOfANullShapeIsStillReadable() {
        System.assertEquals(
            System.Label.Core_HealthCheck_NothingDetected,
            HealthCheckService.detectedSummary(null),
            'A shape that could not be read still produces a sentence.'
        );
    }

    /**
     * Access counts the test chose. The real counts are questions about every user and
     * permission set in the org, so a finding asserted against them is really an assertion
     * about the org the tests happen to run in. These are the numbers the test asked for.
     */
    private class FixedAccessCounts implements HealthCheckService.AccessCounts {
        private final Integer admins;
        private final Integer without;

        private FixedAccessCounts(Integer admins, Integer without) {
            this.admins = admins;
            this.without = without;
        }

        public Integer administrators() {
            return admins;
        }

        public Integer usersWithoutAccess() {
            return without;
        }
    }

    private static OrgShapeDetector.OrgShape shape(
        Boolean hasNpsp,
        Boolean hasPersonAccounts,
        Boolean hasIndustriesNonprofit,
        Boolean hasSalesCloudObjects
    ) {
        OrgShapeDetector.OrgShape orgShape = new OrgShapeDetector.OrgShape();
        orgShape.hasNpsp = hasNpsp;
        orgShape.hasPersonAccounts = hasPersonAccounts;
        orgShape.hasIndustriesNonprofit = hasIndustriesNonprofit;
        orgShape.hasSalesCloudObjects = hasSalesCloudObjects;
        return orgShape;
    }

    private static HealthCheckService.Finding find(
        List<HealthCheckService.Finding> findings,
        String key
    ) {
        for (HealthCheckService.Finding finding : findings) {
            if (key.equals(finding.key)) {
                return finding;
            }
        }
        return null;
    }

    // ---------------------------------------------------------- native household findings

    /**
     * Informational: an org with native Nonprofit Cloud households is told how many, and
     * that Open Impact leaves them alone (product-plan Section 11.2 item 9).
     */
    @IsTest
    static void anOrgWithNativeHouseholdsReportsHowManyInformationally() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.hasNativeHouseholdGroups = true;
        orgShape.nativeHouseholdGroupCount = 3;
        OrgShapeDetector.overrideShape = orgShape;
        HouseholdSelector.nativeHouseholdCollisionCountOverride = 0;

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        HealthCheckService.Finding finding = find(findings, 'native_households');
        System.assertNotEquals(null, finding, 'The native households finding is reported');
        System.assertEquals(
            HealthCheckService.SEVERITY_INFO,
            finding.severity,
            'A native household is not a problem, it is mutual exclusion working'
        );
        System.assert(finding.detail.contains('3'), 'The finding names how many were found');
    }

    /**
     * An org OrgShapeDetector reports as having no native households at all gets no finding.
     */
    @IsTest
    static void anOrgWithNoNativeHouseholdsReportsNothing() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.hasNativeHouseholdGroups = false;
        orgShape.nativeHouseholdGroupCount = 0;
        OrgShapeDetector.overrideShape = orgShape;
        HouseholdSelector.nativeHouseholdCollisionCountOverride = 0;

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        System.assertEquals(
            null,
            find(findings, 'native_households'),
            'Nothing is reported about native households when there are none'
        );
    }

    /**
     * Warning: an Account that is an Open Impact household and a native Nonprofit Cloud
     * household at once, the collision mutual exclusion exists to prevent.
     */
    @IsTest
    static void anAccountCarryingBothHouseholdModelsIsReportedAsAWarning() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.hasNativeHouseholdGroups = true;
        orgShape.nativeHouseholdGroupCount = 1;
        OrgShapeDetector.overrideShape = orgShape;
        HouseholdSelector.nativeHouseholdCollisionCountOverride = 1;

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        HealthCheckService.Finding finding = find(findings, 'native_household_collision');
        System.assertNotEquals(null, finding, 'The collision finding is reported');
        System.assertEquals(
            HealthCheckService.SEVERITY_WARNING,
            finding.severity,
            'A collision is a problem, an administrator should look at'
        );
        System.assert(finding.detail.contains('1'), 'The finding names how many Accounts collide');
    }

    /**
     * No collision, no warning, even in an org that does have native households.
     */
    @IsTest
    static void noCollisionMeansNoWarning() {
        OrgShapeDetector.OrgShape orgShape = shape(false, false, false, false);
        orgShape.hasNativeHouseholdGroups = true;
        orgShape.nativeHouseholdGroupCount = 2;
        OrgShapeDetector.overrideShape = orgShape;
        HouseholdSelector.nativeHouseholdCollisionCountOverride = 0;

        Test.startTest();
        List<HealthCheckService.Finding> findings = HealthCheckService.run();
        Test.stopTest();

        System.assertEquals(
            null,
            find(findings, 'native_household_collision'),
            'No warning is raised when nothing collides'
        );
    }
}
