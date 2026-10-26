/**
 * Tests for RollupsPostInstall: Maria installs the Rollup Builder module and the shipped rollups
 * are in the org when she gets there, an upgrade changes none she edited, a bad shipped row
 * never breaks the install, and she can open the Rollup Builder straight away. Moved from
 * CorePostInstallTest with the engine (ADR-0125).
 */
@IsTest(testFor='ApexClass:RollupsPostInstall')
private class RollupsPostInstallTest {
    @TestSetup
    static void createTestUser() {
        TestUsers.adminWith(RollupsPostInstall.ADMIN_PERMISSION_SET);
    }

    private static User admin() {
        return TestUsers.adminWith(RollupsPostInstall.ADMIN_PERMISSION_SET);
    }

    /** The person who installs the module in one test, holding no BarnCRM access yet. */
    private static Id newInstaller() {
        return TestDataFactory.createUser('Installer', new List<String>()).Id;
    }

    private static void install(RollupsPostInstall handler, Id installerId) {
        handler.onInstall(new InstallBy(installerId, null));
    }

    private static void upgrade(RollupsPostInstall handler, Id installerId) {
        handler.onInstall(new InstallBy(installerId, new Version(1, 0)));
    }

    /** What the platform tells an install handler, with the installer stated. */
    private class InstallBy implements InstallContext {
        private final Id installer;
        private final Version previous;

        InstallBy(Id installer, Version previous) {
            this.installer = installer;
            this.previous = previous;
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
            return false;
        }
    }

    /**
     * The one shipped default these tests materialize: over objects Core has.
     *
     * @return an in-memory shipped default, since custom metadata cannot be inserted by a test
     */
    private static Rollup_Definition_Default__mdt memberCountDefault() {
        return new Rollup_Definition_Default__mdt(
            DeveloperName = 'Core_Household_Member_Count',
            MasterLabel = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = RollupService.MODE_BOTH,
            Fiscal_Year_Aware__c = false,
            Default_Active__c = true,
            Package__c = 'Core'
        );
    }

    private static Integer adminSetsHeldBy(Id userId) {
        return [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE
                AssigneeId = :userId
                AND PermissionSet.Name = :RollupsPostInstall.ADMIN_PERMISSION_SET
            WITH SYSTEM_MODE
        ];
    }

    @IsTest
    static void installCreatesTheShippedRollupsSoTheTotalsAreNotBlank() {
        System.runAs(admin()) {
            Id installer = newInstaller();
            // The defect this covers: nothing called ensureDefaults, so a fresh org had no
            // Rollup Definition records at all and every giving total stayed empty (ADR-0029).
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
                memberCountDefault()
            };

            Test.startTest();
            install(new RollupsPostInstall(), installer);
            Test.stopTest();

            List<Rollup_Definition__c> created = [
                SELECT Definition_Key__c, Is_Package_Default__c, Active__c
                FROM Rollup_Definition__c
            ];
            Assert.areEqual(1, created.size(), 'The install creates the shipped rollup.');
            Assert.areEqual(
                'Core_Household_Member_Count',
                created[0].Definition_Key__c,
                'It is the shipped default, matched by its Definition Key.'
            );
            Assert.isTrue(
                created[0].Active__c,
                'It arrives switched on, so the total is calculated without a second step.'
            );
            Assert.isTrue(
                created[0].Is_Package_Default__c,
                'It is marked as shipped, so the Rollups page can tell it from an admin rollup.'
            );
            Assert.areEqual(
                1,
                adminSetsHeldBy(installer),
                'The installer can open the Rollup Builder.'
            );
        }
    }

    @IsTest
    static void upgradingDoesNotCreateASecondCopyOrUndoAnEdit() {
        System.runAs(admin()) {
            Id installer = newInstaller();
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
                memberCountDefault()
            };
            RollupsPostInstall handler = new RollupsPostInstall();
            Test.startTest();
            install(handler, installer);
            Test.stopTest();
            Rollup_Definition__c afterInstall = [
                SELECT Id, Active__c, Mode__c
                FROM Rollup_Definition__c
                LIMIT 1
            ];
            // Maria switches it off and changes its mode, which is what R-R6 protects.
            update new Rollup_Definition__c(
                Id = afterInstall.Id,
                Active__c = false,
                Mode__c = RollupService.MODE_SCHEDULED
            );

            // No second startTest: the upgrade's job is only queued, which is all it needs.
            upgrade(handler, installer);

            List<Rollup_Definition__c> afterUpgrade = [
                SELECT Id, Active__c, Mode__c
                FROM Rollup_Definition__c
            ];
            Assert.areEqual(1, afterUpgrade.size(), 'An upgrade adds no second copy of a rollup.');
            Assert.areEqual(afterInstall.Id, afterUpgrade[0].Id, 'It is the same record.');
            Assert.isFalse(
                afterUpgrade[0].Active__c,
                'A rollup the admin switched off stays off across an upgrade (R-R6).'
            );
            Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                afterUpgrade[0].Mode__c,
                'And the mode she chose is not reset to the shipped one.'
            );
            Assert.areEqual(1, adminSetsHeldBy(installer), 'The installer holds the set once.');
        }
    }

    @IsTest
    static void anOrgWithoutTheModuleGetsNoneOfItsRollups() {
        System.runAs(admin()) {
            Id installer = newInstaller();
            // A module's shipped rows can name objects the org does not have. That is the case
            // this stands for: the source entity named here is in no package, so the total must
            // not be materialized.
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
                new Rollup_Definition_Default__mdt(
                    DeveloperName = 'Household_Total_Giving',
                    MasterLabel = 'Household total giving',
                    Definition_Key__c = 'Household_Total_Giving',
                    Source_Object__c = 'A_Module_That_Is_Not_Installed__c',
                    Target_Object__c = 'Account',
                    Relationship_Path__c = 'Household__c',
                    Aggregate__c = 'SUM',
                    Source_Field__c = 'Amount__c',
                    Target_Field__c = 'Total_Giving__c',
                    Mode__c = RollupService.MODE_BOTH,
                    Default_Active__c = true,
                    Package__c = 'Giving'
                )
            };

            Test.startTest();
            install(new RollupsPostInstall(), installer);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Rollup_Definition__c],
                'A rollup over an object nobody has must not be created (R-R6).'
            );
            Assert.areEqual(
                1,
                adminSetsHeldBy(installer),
                'And skipping it leaves the rest of the install alone.'
            );
        }
    }

    @IsTest
    static void aRollupThatCannotBeCreatedIsLoggedRatherThanFailingTheInstall() {
        System.runAs(admin()) {
            Id installer = newInstaller();
            // A shipped row whose label is longer than the Rollup Name attribute allows, which is
            // the shape of any bad packaged row: the insert throws where nobody can see it.
            Rollup_Definition_Default__mdt tooLong = memberCountDefault();
            tooLong.MasterLabel = 'x'.repeat(100);
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{ tooLong };

            Test.startTest();
            // No try/catch here on purpose: an exception escaping this call fails the test, which
            // is the assertion that an install is never aborted by this step.
            install(new RollupsPostInstall(), installer);
            Test.stopTest();

            Assert.areEqual(
                0,
                [SELECT COUNT() FROM Rollup_Definition__c],
                'The bad row is not created.'
            );
            List<Error_Log__c> logged = [
                SELECT Context__c, Technical_Detail__c, Severity__c
                FROM Error_Log__c
                WHERE Context__c = :RollupsPostInstall.ROLLUP_CONTEXT
            ];
            Assert.areEqual(1, logged.size(), 'The failure is in the Error Log.');
            Assert.areEqual(
                ErrorLogger.SEVERITY_ERROR,
                logged[0].Severity__c,
                'It is recorded as an error rather than as information.'
            );
            Assert.isTrue(
                logged[0].Technical_Detail__c.contains('DmlException'),
                'The technical detail names what the platform refused.'
            );
            Assert.areEqual(1, adminSetsHeldBy(installer), 'And the rest of the install ran.');
        }
    }

    @IsTest
    static void aMissingContextChangesNothing() {
        System.runAs(admin()) {
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
                memberCountDefault()
            };

            Test.startTest();
            new RollupsPostInstall().onInstall(null);
            Test.stopTest();

            Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'Nothing ran.');
        }
    }

    @IsTest
    static void theInstallerGetsRollupBuilderAdminOnceEvenWhenTheyHoldItAlready() {
        System.runAs(admin()) {
            Id fresh = newInstaller();
            Id alreadyHolding = TestDataFactory.createUser(
                    'Holder',
                    new List<String>{ RollupsPostInstall.ADMIN_PERMISSION_SET }
                )
                .Id;
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>();

            Test.startTest();
            install(new RollupsPostInstall(), fresh);
            install(new RollupsPostInstall(), alreadyHolding);
            Test.stopTest();

            Assert.areEqual(1, adminSetsHeldBy(fresh), 'The installer holds Rollup Builder Admin.');
            Assert.areEqual(
                1,
                adminSetsHeldBy(alreadyHolding),
                'An installer who held it already is not given it twice.'
            );
        }
    }

    @IsTest
    static void rollupSettingsSavedOnCoreAreCarriedOver() {
        System.runAs(admin()) {
            // Core no longer defines the old fields, so a test org cannot hold them: the read of
            // the old values is stood in for, and the copy is what is measured.
            RollupsPostInstall.oldCoreValuesForTest = new Map<String, Object>{
                RollupService.MODE_DEFAULT_SETTING => RollupService.MODE_SCHEDULED,
                RollupService.PROCESSING_SETTING => RollupService.PROCESSING_IN_SAVE
            };

            Test.startTest();
            RollupsPostInstall.carryOverCoreSettings();
            Test.stopTest();

            Rollup_Settings__c saved = Rollup_Settings__c.getOrgDefaults();
            Assert.isNotNull(saved.Id, 'The module settings are saved.');
            Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                saved.Rollup_Mode_Default__c,
                'The default mode the org chose on Core is kept.'
            );
            Assert.areEqual(
                RollupService.PROCESSING_IN_SAVE,
                saved.Rollup_Processing__c,
                'And so is when real-time totals are recalculated.'
            );
        }
    }

    @IsTest
    static void aBlankOldValueIsLeftToTheShippedDefault() {
        System.runAs(admin()) {
            RollupsPostInstall.oldCoreValuesForTest = new Map<String, Object>{
                RollupService.MODE_DEFAULT_SETTING => RollupService.MODE_SCHEDULED,
                RollupService.PROCESSING_SETTING => ' '
            };

            RollupsPostInstall.carryOverCoreSettings();

            Rollup_Settings__c saved = Rollup_Settings__c.getOrgDefaults();
            Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                saved.Rollup_Mode_Default__c,
                'The non-blank value is carried.'
            );
            Assert.areEqual(
                RollupService.PROCESSING_BACKGROUND,
                saved.Rollup_Processing__c,
                'The blank one keeps the shipped default.'
            );
        }
    }

    @IsTest
    static void aFreshOrgGetsASettingsRowHoldingTheShippedDefaults() {
        System.runAs(admin()) {
            Assert.isNull(Rollup_Settings__c.getOrgDefaults().Id, 'A fresh org has no row.');
            Assert.areEqual(
                RollupService.MODE_BOTH,
                SettingsService.getEffectiveValue(
                    RollupService.SETTINGS_OBJECT,
                    RollupService.MODE_DEFAULT_SETTING,
                    'Picklist'
                ),
                'Before any row exists the console already shows Both.'
            );
            Assert.areEqual(
                RollupService.PROCESSING_BACKGROUND,
                SettingsService.getEffectiveValue(
                    RollupService.SETTINGS_OBJECT,
                    RollupService.PROCESSING_SETTING,
                    'Picklist'
                ),
                'And After the save (Background) for when instant totals are calculated.'
            );

            RollupsPostInstall.ensureSettingsRow();
            RollupsPostInstall.ensureSettingsRow();

            Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Settings__c], 'One row, run twice.');
            Rollup_Settings__c row = Rollup_Settings__c.getOrgDefaults();
            Assert.areEqual(UserInfo.getOrganizationId(), row.SetupOwnerId, 'The org-level row.');
            Assert.areEqual(RollupService.MODE_BOTH, row.Rollup_Mode_Default__c, 'Mode Both.');
            Assert.areEqual(
                RollupService.PROCESSING_BACKGROUND,
                row.Rollup_Processing__c,
                'Processing Background.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing audited.');
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :RollupsPostInstall.SETTINGS_CONTEXT
                ],
                'And nothing failed.'
            );
        }
    }

    @IsTest
    static void theSettingsRowStepNeverOverwritesASavedValue() {
        System.runAs(admin()) {
            Rollup_Settings__c existing = Rollup_Settings__c.getOrgDefaults();
            existing.Rollup_Mode_Default__c = RollupService.MODE_SCHEDULED;
            existing.Rollup_Processing__c = RollupService.PROCESSING_IN_SAVE;
            Database.upsert(existing, AccessLevel.SYSTEM_MODE);

            RollupsPostInstall.ensureSettingsRow();

            Rollup_Settings__c row = Rollup_Settings__c.getOrgDefaults();
            Assert.areEqual(
                RollupService.MODE_SCHEDULED,
                row.Rollup_Mode_Default__c,
                'An upgrade keeps the mode the org chose.'
            );
            Assert.areEqual(
                RollupService.PROCESSING_IN_SAVE,
                row.Rollup_Processing__c,
                'And when it chose to recalculate.'
            );
            Assert.areEqual(1, [SELECT COUNT() FROM Rollup_Settings__c], 'No second row.');
        }
    }

    @IsTest
    static void theInstallCreatesTheSettingsRow() {
        System.runAs(admin()) {
            Test.startTest();
            install(new RollupsPostInstall(), newInstaller());
            Test.stopTest();

            Assert.isNotNull(
                Rollup_Settings__c.getOrgDefaults().Id,
                'A new install leaves the module settings row in place.'
            );
            Assert.areEqual(
                RollupService.MODE_BOTH,
                Rollup_Settings__c.getOrgDefaults().Rollup_Mode_Default__c,
                'Both.'
            );
        }
    }

    @IsTest
    static void settingsTheModuleAlreadySavedWin() {
        System.runAs(admin()) {
            Rollup_Settings__c existing = Rollup_Settings__c.getOrgDefaults();
            existing.Rollup_Mode_Default__c = RollupService.MODE_BOTH;
            Database.upsert(existing, AccessLevel.SYSTEM_MODE);
            RollupsPostInstall.oldCoreValuesForTest = new Map<String, Object>{
                RollupService.MODE_DEFAULT_SETTING => RollupService.MODE_SCHEDULED
            };

            RollupsPostInstall.carryOverCoreSettings();

            Assert.areEqual(
                RollupService.MODE_BOTH,
                Rollup_Settings__c.getOrgDefaults().Rollup_Mode_Default__c,
                'An upgrade never overwrites what the module settings already hold.'
            );
            Assert.areEqual(0, [SELECT COUNT() FROM Setting_Change__c], 'Nothing was saved.');
        }
    }

    @IsTest
    static void anOrgWithoutTheOldFieldsSavesNothing() {
        System.runAs(admin()) {
            // No stand-in: the real read finds no old field in this org.
            Test.startTest();
            RollupsPostInstall.carryOverCoreSettings();
            Test.stopTest();

            Assert.isNull(
                Rollup_Settings__c.getOrgDefaults().Id,
                'With nothing to carry, no settings row is created.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = :RollupsPostInstall.CARRY_CONTEXT
                ],
                'And nothing failed.'
            );
        }
    }

    @IsTest
    static void anInstallWithNoNamedInstallerStillQueuesTheRoleSync() {
        System.runAs(admin()) {
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>();

            Test.startTest();
            // No installer to name: the platform gives none for a push upgrade, say.
            install(new RollupsPostInstall(), null);
            Test.stopTest();

            Assert.isTrue(
                [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'] > 0,
                'The role sync is queued on its own, since there is no installer job to run it.'
            );
            Assert.areEqual(
                0,
                [
                    SELECT COUNT()
                    FROM Error_Log__c
                    WHERE Context__c = 'RollupsPostInstall.grantInstallerAccess'
                ],
                'Nothing failed.'
            );
        }
    }

    @IsTest
    static void aGrantThePlatformRefusesIsLoggedAsAWarning() {
        System.runAs(admin()) {
            RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>();
            // An Id that is no user, so the assignment insert is refused for a reason other
            // than a duplicate.
            Account notAUser = new Account(Name = 'Not a user');
            insert notAUser;

            Test.startTest();
            install(new RollupsPostInstall(), notAUser.Id);
            Test.stopTest();

            List<Error_Log__c> logged = [
                SELECT Severity__c
                FROM Error_Log__c
                WHERE Context__c = 'RollupsPostInstall.grantInstallerAccess'
            ];
            Assert.areEqual(1, logged.size(), 'The refusal is in the Error Log.');
            Assert.areEqual(
                ErrorLogger.SEVERITY_WARNING,
                logged[0].Severity__c,
                'It is a warning: the install is not aborted by it.'
            );
        }
    }
}
