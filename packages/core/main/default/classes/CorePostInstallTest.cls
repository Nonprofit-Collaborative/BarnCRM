/**
 * Tests for CorePostInstall and its retry job: Maria installs BarnCRM and can use
 * BarnCRM Settings straight away, an upgrade changes nothing, the role follows when the platform has finished preparing it,
 * and nothing here ever breaks an install.
 */
@IsTest(testFor='ApexClass:CorePostInstall')
private class CorePostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.admin();
    }

    private static final String SWITCH_CONTEXT = 'CorePostInstall.ensureAutomationSwitches';
    private static final String RETRY_CONTEXT = 'CorePostInstallRetryQueueable.execute';
    private static final String MODE_CONTEXT = 'CorePostInstall.applyRecommendedMode';

    /**
     * The BarnCRM Admin group as the platform leaves it in the minutes after an install:
     * present, but still being calculated, so it cannot be assigned yet.
     *
     * Built by deserializing rather than by construction because Status is written by the
     * platform and Apex cannot assign it, and because Test.calculatePermissionSetGroup only
     * ever moves a group forwards to Updated. There is no other way to prove what the install
     * does while it waits.
     *
     * @return a permission set group that is not ready to be assigned
     */
    private static PermissionSetGroup groupStillBeingCalculated() {
        return (PermissionSetGroup) JSON.deserialize(
            '{"attributes":{"type":"PermissionSetGroup"},"DeveloperName":"' +
                AccessService.ADMIN_ROLE +
                '","Status":"Updating"}',
            PermissionSetGroup.class
        );
    }

    /**
     * The person who installs the package in one test: somebody created for that test alone.
     *
     * Not the running user, because the running user is shared. Test classes run in parallel
     * as the same person, and a PermissionSetAssignment for a given person and group is one
     * row whoever inserts it: when another class (SetupAssistantControllerTest, for one) gives
     * the running user the BarnCRM Admin role at the same moment as the job here, one of
     * the two inserts is refused, the job logs the refusal as it should, and the role count
     * here reads 0. A person nobody else can see has no such neighbour. It also means the
     * permission set assertions prove the install gave it, rather than finding the one the
     * test org's run script assigned to the running user beforehand.
     *
     * @return the installer's Id, holding no BarnCRM access yet
     */
    private static Id newInstaller() {
        return TestDataFactory.createUser('Installer', new List<String>()).Id;
    }

    /**
     * Installs the package for the first time, as the given person.
     *
     * Test.testInstall has no way to name the installer, and the one it names is the running
     * user (see newInstaller), so the handler is given a context that states the person.
     * Nothing else in the context is read by the handler.
     *
     * @param handler the install handler under test
     * @param installerId the person pressing Install
     */
    private static void install(CorePostInstall handler, Id installerId) {
        handler.onInstall(new InstallBy(installerId, null, false));
    }

    /**
     * Upgrades from version 1.0 as the given person, as a push upgrade.
     *
     * @param handler the install handler under test
     * @param installerId the person the upgrade is recorded against
     */
    private static void upgrade(CorePostInstall handler, Id installerId) {
        handler.onInstall(new InstallBy(installerId, new Version(1, 0), true));
    }

    /** What the platform tells an install handler, with the installer stated. */
    private class InstallBy implements InstallContext {
        private final Id installer;
        private final Version previous;
        private final Boolean pushed;

        InstallBy(Id installer, Version previous, Boolean pushed) {
            this.installer = installer;
            this.previous = previous;
            this.pushed = pushed;
        }

        public Id organizationId() {
            return UserInfo.getOrganizationId();
        }

        public Id installerId() {
            return installer;
        }

        public Version previousVersion() {
            return previous;
        }

        public Boolean isUpgrade() {
            return previous != null;
        }

        public Boolean isPush() {
            return pushed;
        }
    }

    @IsTest
    static void aNewInstallStartsWithEveryFeatureOffAndAnUpgradeKeepsThemOn() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            upgrade(handler, installer);
            Boolean onAfterUpgrade = FeatureSwitchService.isOn(FeatureSwitchService.DATA_MANAGER);
            install(handler, installer);
            Test.stopTest();

            Assert.isTrue(onAfterUpgrade, 'An upgraded org keeps every feature it used');
            Assert.areEqual(
                FeatureSwitchService.NONE_ON,
                SettingsService.getSettings().Features_Turned_On__c,
                'A new install stores None until first-run setup'
            );
            Assert.isTrue(FeatureSwitchService.featuresOn().isEmpty(), 'So no feature is on yet');
        }
    }

    @IsTest
    static void anUpgradeWithNoEditionSavesTheRecommendedOne() {
        System.runAs(TestUsers.admin()) {
            String recommended = SetupAssistantService.recommendedSuite();
            String expected = recommended == null
                ? ModuleDetectionService.SUITE_COMMUNITY
                : recommended;

            new CorePostInstall().onInstall(new InstallBy(null, new Version(1, 0), false));

            Assert.areEqual(
                expected,
                ModuleDetectionService.chosenSuite(),
                'An upgraded org is not stopped by the first-run window'
            );
            Assert.isFalse(FirstRunController.getState().needsSetup, 'So the window never shows');
        }
    }

    @IsTest
    static void anUpgradeKeepsASavedEditionAndANewInstallSavesNone() {
        System.runAs(TestUsers.admin()) {
            SettingsService.saveSystemValue('Suite__c', ModuleDetectionService.SUITE_IMPACT);

            new CorePostInstall().onInstall(new InstallBy(null, new Version(1, 0), false));
            String afterUpgrade = ModuleDetectionService.chosenSuite();
            SettingsService.saveSystemValue('Suite__c', null);
            new CorePostInstall().onInstall(new InstallBy(null, null, false));

            Assert.areEqual(
                ModuleDetectionService.SUITE_IMPACT,
                afterUpgrade,
                'The edition chosen is kept'
            );
            Assert.isNull(
                ModuleDetectionService.chosenSuite(),
                'A new install leaves the edition to first-run setup'
            );
        }
    }

    @IsTest
    static void everyRunSchedulesTheNightlyTabCheckOnce() {
        System.runAs(TestUsers.admin()) {
            CorePostInstall.scheduleTabCheckInTests = true;
            // The org's own check, if an install already scheduled it, would be counted too.
            TestDataFactory.clearScheduledJobs(new List<String>{ TabAccessScheduler.JOB_NAME });
            ScheduledJobSelector.forget();

            new CorePostInstall().onInstall(new InstallBy(null, null, false));
            new CorePostInstall().onInstall(new InstallBy(null, new Version(1, 0), false));

            Assert.areEqual(
                1,
                [
                    SELECT COUNT()
                    FROM CronTrigger
                    WHERE CronJobDetail.Name = :TabAccessScheduler.JOB_NAME
                ],
                'An install and an upgrade leave one nightly tab access check'
            );
        }
    }

    /**
     * Removes the org's saved settings inside the test, so a test about an org that has never
     * saved them runs the same on an org that has (custom settings are visible to tests).
     */
    private static void forgetSavedSettings() {
        delete [SELECT Id FROM BarnCRM_Settings__c];
        SettingsService.clearCaches();
    }

    @IsTest
    static void aSourceDeployOnAFreshOrgStartsLikeANewInstall() {
        System.runAs(TestUsers.admin()) {
            forgetSavedSettings();

            Test.startTest();
            CorePostInstall.runAsSourceDeploy();
            CorePostInstall.runAsSourceDeploy();
            Test.stopTest();

            SettingsService.clearCaches();
            Assert.areEqual(
                FeatureSwitchService.NONE_ON,
                SettingsService.getSettings().Features_Turned_On__c,
                'A fresh org waits for first-run setup, as after a package install'
            );
            Assert.isTrue(
                [SELECT COUNT() FROM Automation_Setting__c] > 0,
                'The Automation page lists its switches'
            );
        }
    }

    @IsTest
    static void aSourceDeployOnAnOrgWithSavedSettingsChangesNothingChosen() {
        System.runAs(TestUsers.admin()) {
            forgetSavedSettings();
            SettingsService.saveSystemValue('Suite__c', ModuleDetectionService.SUITE_IMPACT);
            SettingsService.clearCaches();

            CorePostInstall.runAsSourceDeploy();

            SettingsService.clearCaches();
            Assert.isNull(
                SettingsService.getSettings().Features_Turned_On__c,
                'An org already in use is never marked as a new install'
            );
            Assert.isTrue(
                FeatureSwitchService.isOn(FeatureSwitchService.DATA_MANAGER),
                'So every feature it used stays on'
            );
            Assert.areEqual(
                ModuleDetectionService.SUITE_IMPACT,
                ModuleDetectionService.chosenSuite(),
                'And its edition is kept'
            );
        }
    }

    @IsTest
    static void anOrgHoldingAHouseholdCountsAsSetUpEvenWithoutSettings() {
        System.runAs(TestUsers.admin()) {
            insert HouseholdTestDataFactory.newHousehold('The Garcia Family');
            forgetSavedSettings();

            Assert.isTrue(
                CorePostInstall.hasBeenSetUp(),
                'Households mean the org is in use, so a source deploy is an upgrade there'
            );
        }
    }

    @IsTest
    static void installAlwaysGivesTheInstallerTheAdminPermissionSet() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The permission set is the step that must never depend on timing: it has no
            // calculation status, so it works the moment the job the install queues runs.
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                1,
                countPermissionSetAssignments(installer),
                'The person who installs the package should hold the BarnCRM Admin permission set.'
            );
        }
    }

    @IsTest
    static void installGivesTheInstallerTheRoleWhenItIsReady() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                1,
                countRoleAssignments(installer),
                'A prepared role should be given by the job the install queued, on its first look.'
            );
            // The install queues exactly one job, because giving access is a setup object write
            // that cannot share the install's transaction. A second job would mean the role was
            // not given on the first look; queueing it fails inside a test and is logged.
            Assert.areEqual(1, countRetryJobs(), 'Only the job the install itself queued.');
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :RETRY_CONTEXT],
                'Nothing needs to wait in the background when the role is already prepared.'
            );
        }
    }

    @IsTest
    static void installQueuesARetryWhenTheRoleIsNotReadyYet() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The state a real org is in during the minutes after an install: the packaged group
            // is there, but the platform is still calculating it and will refuse to assign it.
            // Leaving Test.calculatePermissionSetGroup uncalled does not produce that state, which
            // is what this test used to assume: in any org where the metadata is deployed the
            // group is already Updated, the install assigns the role outright, and nothing is
            // queued. The state has to be stated rather than hoped for.
            PermissionSetGroupSelector.systemModeOverride = groupStillBeingCalculated();
            CorePostInstall handler = new CorePostInstall();

            // The queued job runs at Test.stopTest, gives the permission set, finds the group
            // still not ready, and tries to queue the next attempt. The platform does not allow a queueable to chain inside a
            // test, so that attempt fails and the job logs it, which is why this asserts on the
            // one job the install itself queued rather than on the whole chain.
            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                1,
                countPermissionSetAssignments(installer),
                'The installer is working regardless, because the permission set does not wait.'
            );
            Assert.areEqual(
                0,
                countRoleAssignments(installer),
                'A role the platform is still calculating cannot be handed out during the install.'
            );
            Assert.areEqual(
                1,
                countRetryJobs(),
                'A role that is not prepared yet should be picked up by a background job.'
            );
        }
    }

    @IsTest
    static void upgradingAnOrgThatIsAlreadySetUpChangesNothing() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
            CorePostInstall handler = new CorePostInstall();
            install(handler, installer);

            Test.startTest();
            upgrade(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                1,
                countPermissionSetAssignments(installer),
                'An upgrade should leave exactly one permission set assignment, not add a second.'
            );
            Assert.areEqual(
                1,
                countRoleAssignments(installer),
                'An upgrade should leave exactly one role assignment, not add a second.'
            );
        }
    }

    @IsTest
    static void aMissingContextChangesNothing() {
        System.runAs(TestUsers.admin()) {
            Integer permissionSetsBefore = countPermissionSetAssignments(UserInfo.getUserId());
            Integer rolesBefore = countRoleAssignments(UserInfo.getUserId());
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            handler.onInstall(null);
            Test.stopTest();

            Assert.areEqual(
                permissionSetsBefore,
                countPermissionSetAssignments(UserInfo.getUserId()),
                'An install with no context should assign no permission set.'
            );
            Assert.areEqual(
                rolesBefore,
                countRoleAssignments(UserInfo.getUserId()),
                'An install with no context should assign no role.'
            );
            Assert.areEqual(
                0,
                countRetryJobs(),
                'An install with no context should queue nothing.'
            );
        }
    }

    @IsTest
    static void theRetryJobAssignsTheRoleOnceItIsPrepared() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);

            Test.startTest();
            System.enqueueJob(new CorePostInstallRetryQueueable(installer));
            Test.stopTest();

            Assert.areEqual(
                1,
                countRoleAssignments(installer),
                'The background job should hand out the role once the platform has prepared it.'
            );
        }
    }

    @IsTest
    static void theRetryJobWaitsBetweenAttemptsRatherThanBurningThroughThemAtOnce() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The defect this covers: the job used to re-enqueue itself immediately, with no
            // delay, so all MAX_ATTEMPTS attempts burned through within seconds of install,
            // long before the platform leaves the group's Status as Updating. The fix is the
            // delayed-execution overload of System.enqueueJob, named here by its constant: a
            // test cannot observe wall-clock delay (Test.stopTest runs a delayed job as soon
            // as it is reached, ignoring the delay), so this locks in the delay itself and,
            // starting from the full attempt count, that the job re-queues rather than giving
            // up or assigning a role the platform has not finished calculating.
            Assert.isTrue(
                CorePostInstallRetryQueueable.RETRY_DELAY_MINUTES > 0,
                'Each attempt should wait before the next one runs, not retry inline.'
            );
            PermissionSetGroupSelector.systemModeOverride = groupStillBeingCalculated();
            CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(
                installer,
                CorePostInstallRetryQueueable.MAX_ATTEMPTS
            );

            Test.startTest();
            job.execute(null);
            Assert.areEqual(
                1,
                countRetryJobs(),
                'The first of several attempts should queue exactly one more.'
            );
            Test.stopTest();

            Assert.areEqual(
                0,
                countRoleAssignments(installer),
                'A role the platform is still calculating cannot be handed out yet.'
            );
        }
    }

    @IsTest
    static void theRetryJobGivesUpQuietlyOnItsLastAttempt() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // One attempt left and a role the platform is still calculating: the job records a
            // warning and stops rather than queueing for ever or throwing. The state is stated
            // rather than assumed, for the reason given in installQueuesARetryWhenTheRoleIsNotReadyYet.
            PermissionSetGroupSelector.systemModeOverride = groupStillBeingCalculated();
            CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(installer, 1);

            Test.startTest();
            job.execute(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                countRoleAssignments(installer),
                'Giving up should leave the org as it was, with the permission set doing the work.'
            );
            Assert.areEqual(0, countRetryJobs(), 'The last attempt should not queue another.');
            List<Error_Log__c> logged = [
                SELECT Technical_Detail__c
                FROM Error_Log__c
                WHERE Context__c = :RETRY_CONTEXT
            ];
            Assert.areEqual(
                1,
                logged.size(),
                'Giving up quietly still means leaving Maria a note in the Error Log.'
            );
            Assert.isTrue(
                logged[0].Technical_Detail__c.contains('BarnCRM Admin role'),
                'The note names the role that was never handed out, so Maria knows what to finish.'
            );
        }
    }

    @IsTest
    static void theRetryJobIgnoresAMissingPerson() {
        System.runAs(TestUsers.admin()) {
            CorePostInstallRetryQueueable job = new CorePostInstallRetryQueueable(null);

            Test.startTest();
            job.execute(null);
            Test.stopTest();

            Assert.areEqual(
                0,
                countRetryJobs(),
                'With nobody to assign, the job should do nothing.'
            );
        }
    }

    /** The keys of the import templates the installed packages ship. */
    private static Set<String> shippedTemplateKeys() {
        Set<String> keys = new Set<String>();
        for (Import_Template_Default__mdt row : ImportTemplateSelector.selectShippedDefaults()) {
            if (String.isNotBlank(row.Template_Key__c)) {
                keys.add(row.Template_Key__c);
            }
        }
        return keys;
    }

    /** The import templates in the org, by key. */
    private static Map<String, Import_Template__c> templatesByKey() {
        Map<String, Import_Template__c> result = new Map<String, Import_Template__c>();
        for (Import_Template__c template : [
            SELECT Id, Name, Template_Key__c, Active__c, Column_Mapping_JSON__c
            FROM Import_Template__c
            WITH SYSTEM_MODE
        ]) {
            result.put(template.Template_Key__c, template);
        }
        return result;
    }

    /** An install adds every shipped import template, so the wizard has them on day one. */
    @IsTest
    static void installAddsTheShippedImportTemplates() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();

            Test.startTest();
            install(new CorePostInstall(), installer);
            Test.stopTest();

            Map<String, Import_Template__c> byKey = templatesByKey();
            Assert.isTrue(
                byKey.keySet().containsAll(shippedTemplateKeys()),
                'Every shipped template is here after the install: ' + byKey.keySet()
            );
            Assert.isTrue(byKey.containsKey('generic_contact_list'), 'Core\'s own included.');
            Assert.areEqual(
                shippedTemplateKeys().size(),
                byKey.size(),
                'One each, and nothing else.'
            );
        }
    }

    /**
     * An upgrade adds a template the org does not have, as one shipped in a later version is,
     * and leaves one the administrator edited exactly as they left it, with no second copy.
     */
    @IsTest
    static void upgradeAddsANewTemplateAndKeepsAnEditedOne() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            CorePostInstall handler = new CorePostInstall();
            install(handler, installer);
            Import_Template__c edited = templatesByKey().get('generic_contact_list');
            edited.Name = 'Our contact list';
            edited.Active__c = false;
            edited.Column_Mapping_JSON__c = '{"version":1,"columns":[]}';
            update as system edited;
            // A shipped template the org lacks, as one first shipped in the new version is.
            List<Import_Template__c> others = [
                SELECT Id
                FROM Import_Template__c
                WHERE Template_Key__c != 'generic_contact_list'
                WITH SYSTEM_MODE
            ];
            delete as system others;

            Test.startTest();
            upgrade(handler, installer);
            Test.stopTest();

            Map<String, Import_Template__c> byKey = templatesByKey();
            Assert.areEqual(
                shippedTemplateKeys().size(),
                byKey.size(),
                'The missing templates are added, and no second copy of the edited one.'
            );
            Import_Template__c kept = byKey.get('generic_contact_list');
            Assert.areEqual(edited.Id, kept.Id, 'The same record.');
            Assert.areEqual('Our contact list', kept.Name, 'Its name as the admin left it.');
            Assert.isFalse(kept.Active__c, 'Still switched off.');
            Assert.areEqual(
                '{"version":1,"columns":[]}',
                kept.Column_Mapping_JSON__c,
                'And its mapping untouched.'
            );
        }
    }

    /** Adding the templates twice, as an install then an upgrade does, adds them once. */
    @IsTest
    static void addingTheTemplatesTwiceAddsThemOnce() {
        System.runAs(TestUsers.admin()) {
            Test.startTest();
            Integer created = ImportTemplateService.materializeDefaultsDuringInstall(
                'CorePostInstall.ensureImportTemplates'
            );
            Integer again = ImportTemplateService.materializeDefaultsDuringInstall(null);
            Test.stopTest();

            Assert.areEqual(shippedTemplateKeys().size(), created, 'Created once.');
            Assert.areEqual(0, again, 'And nothing the second time.');
        }
    }

    @IsTest
    static void installCreatesTheAutomationSwitchesSoThePageIsNotEmpty() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The defect this covers: nothing created the switch rows, so the Automation page was
            // empty on every org until somebody pressed a Health Check fix (C-21).
            Automation_Registry__mdt lock = TestDataFactory.registryEntry(
                'Test_Receipt_Lock',
                true
            );
            lock.Always_Runs__c = true;
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                TestDataFactory.registryEntry('Test_Household_Naming', true),
                lock
            };
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Map<String, Automation_Setting__c> byName = switchesByName();
            Assert.areEqual(2, byName.size(), 'The install creates one switch per automation.');
            Assert.isTrue(
                byName.get('Test_Household_Naming').Enabled__c,
                'Each set to its shipped default.'
            );
            Assert.isTrue(
                byName.get('Test_Receipt_Lock').Always_Runs__c,
                'And an automation that always runs is listed as one (ADR-0024).'
            );
        }
    }

    @IsTest
    static void upgradingCreatesNoSecondSwitchAndKeepsOneTurnedOff() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                TestDataFactory.registryEntry('Test_Household_Naming', true)
            };
            CorePostInstall handler = new CorePostInstall();
            install(handler, installer);
            Automation_Setting__c afterInstall = switchesByName().get('Test_Household_Naming');
            // Maria switches household naming off.
            update new Automation_Setting__c(Id = afterInstall.Id, Enabled__c = false);
            // The upgrade ships a second automation.
            AutomationRegistrySelector.registryOverride.add(
                TestDataFactory.registryEntry('Test_Address_Sync', true)
            );

            Test.startTest();
            upgrade(handler, installer);
            Test.stopTest();

            Map<String, Automation_Setting__c> byName = switchesByName();
            Assert.areEqual(2, byName.size(), 'Only the newly shipped automation gets a switch.');
            Assert.areEqual(
                afterInstall.Id,
                byName.get('Test_Household_Naming').Id,
                'The existing switch is the same record, not a replacement.'
            );
            Assert.isFalse(
                byName.get('Test_Household_Naming').Enabled__c,
                'A switch the admin turned off stays off across an upgrade.'
            );
        }
    }

    @IsTest
    static void aSwitchThatCannotBeCreatedIsLoggedRatherThanFailingTheInstall() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // A registry label longer than the switch's Name allows: the insert throws.
            Automation_Registry__mdt tooLong = TestDataFactory.registryEntry('Test_Too_Long', true);
            tooLong.MasterLabel = 'x'.repeat(100);
            AutomationRegistrySelector.registryOverride = new List<Automation_Registry__mdt>{
                tooLong
            };
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            // No try/catch on purpose: an exception escaping this call fails the test.
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Automation_Setting__c], 'Nothing is created.');
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :SWITCH_CONTEXT],
                'The failure is in the Error Log, under the step that failed.'
            );
            Assert.areEqual(
                1,
                countPermissionSetAssignments(installer),
                'And the rest of the install still ran.'
            );
        }
    }

    private static Map<String, Automation_Setting__c> switchesByName() {
        Map<String, Automation_Setting__c> byName = new Map<String, Automation_Setting__c>();
        for (Automation_Setting__c setting : [
            SELECT Id, Automation_Name__c, Enabled__c, Always_Runs__c
            FROM Automation_Setting__c
            WITH SYSTEM_MODE
        ]) {
            byName.put(setting.Automation_Name__c, setting);
        }
        return byName;
    }

    @IsTest
    static void installPutsTheRecommendedModeInForceSoHouseholdsCanForm() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The defect this covers: applyRecommendedIfUnset was never called from the install,
            // so a Person Accounts org stayed in contact membership, which cannot hold a person
            // stored as an account, and households silently never formed.
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                CoexistenceService.MODE_STANDALONE,
                CoexistenceService.getCurrentMode(),
                'A fresh install takes the mode detection recommends, so Maria is not asked first.'
            );
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_JUNCTION,
                CoexistenceService.getMembershipMode(),
                'And in a Person Accounts org the flexible way of belonging comes with it.'
            );
            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :MODE_CONTEXT],
                'Nothing went wrong, so nothing is logged.'
            );
        }
    }

    @IsTest
    static void upgradingLeavesAModeTheAdministratorChoseAlone() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // Maria chose standalone and the simple way of belonging on purpose. An upgrade that
            // detects Person Accounts must not argue with her: that is what IfUnset means.
            CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);
            SettingsService.saveValues(
                new Map<String, Object>{
                    CoexistenceService.KEY_MEMBERSHIP_MODE => CoexistenceService.MEMBERSHIP_CONTACT
                }
            );
            OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
            shape.hasPersonAccounts = true;
            OrgShapeDetector.overrideShape = shape;
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            upgrade(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                CoexistenceService.MODE_STANDALONE,
                CoexistenceService.getCurrentMode(),
                'An upgrade leaves the coexistence mode Maria chose.'
            );
            Assert.areEqual(
                CoexistenceService.MEMBERSHIP_CONTACT,
                CoexistenceService.getMembershipMode(),
                'And the way of belonging she chose.'
            );
        }
    }

    @IsTest
    static void aModeThatCannotBeSavedIsLoggedRatherThanFailingTheInstall() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // A recommendation nothing in the org can store: a settings row the console does not
            // know is refused by SettingsService, which is the shape of any failure on this step.
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            CorePostInstall handler = new CorePostInstall();

            Test.startTest();
            // No try/catch here on purpose: an exception escaping this call fails the test, which
            // is the assertion that an install is never aborted by this step.
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                null,
                CoexistenceService.getCurrentMode(),
                'The mode is left unset for Health Check to report.'
            );
            Assert.areEqual(
                1,
                [SELECT COUNT() FROM Error_Log__c WHERE Context__c = :MODE_CONTEXT],
                'The failure is in the Error Log where Maria can read it.'
            );
            Assert.areEqual(
                1,
                countPermissionSetAssignments(installer),
                'And the rest of the install still ran, so the installer can open the console.'
            );
        }
    }

    @IsTest
    static void theHubCanCountWhatTheInstallLogged() {
        System.runAs(TestUsers.admin()) {
            Id installer = newInstaller();
            // The role is prepared so that the one failure counted is the one this test causes: a
            // role still being calculated would have the access job try to wait, which a test
            // cannot do, and log that as well.
            TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);
            SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
            CorePostInstall handler = new CorePostInstall();

            // The Error Log is written through a platform event, delivered at Test.stopTest, so
            // the count is taken after it.
            Test.startTest();
            install(handler, installer);
            Test.stopTest();

            Assert.areEqual(
                1,
                CorePostInstall.countInstallProblemsUpTo(999),
                'The install step that failed is counted, so the Hub can say setup had a problem.'
            );
        }
    }

    /**
     * Counts how many rows link a person to the BarnCRM Admin permission set.
     *
     * @param userId the person
     * @return the number of assignment rows
     */
    private static Integer countPermissionSetAssignments(Id userId) {
        String permissionSetName = AccessService.ADMIN_PERMISSION_SET;
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE
                AssigneeId = :userId
                AND PermissionSetGroupId = NULL
                AND PermissionSet.Name = :permissionSetName
        ];
    }

    /**
     * Counts how many rows link a person to the BarnCRM Admin role.
     *
     * @param userId the person
     * @return the number of assignment rows
     */
    private static Integer countRoleAssignments(Id userId) {
        String adminRole = AccessService.ADMIN_ROLE;
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetGroup.DeveloperName = :adminRole
        ];
    }

    /**
     * Counts the background jobs waiting for the role to be prepared.
     *
     * @return the number of queued retry jobs
     */
    private static Integer countRetryJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'CorePostInstallRetryQueueable'
        ];
    }
}
