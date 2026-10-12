/**
 * The engine as the rest of BarnCRM sees it: materializing shipped defaults, running a
 * definition, and stamping freshness.
 *
 * These tests have not been executed: no Salesforce org exists in this environment. The engine
 * itself is stood down with `RollupService.skipEngine`, because what is being asserted here is
 * BarnCRM's side of ADR-0015: which definitions are selected, what metadata they become, and
 * what is stamped afterwards. The engine's own behaviour is upstream's, and upstream tests it.
 */
@IsTest
private class RollupServiceTest {
    private static Rollup_Definition__c memberCount(String mode, Boolean active) {
        return new Rollup_Definition__c(
            Name = 'Household member count',
            Definition_Key__c = 'Core_Household_Member_Count',
            Source_Object__c = 'Household_Member__c',
            Target_Object__c = 'Account',
            Relationship_Path__c = 'Household__c',
            Aggregate__c = 'COUNT',
            Target_Field__c = 'Member_Count__c',
            Mode__c = mode,
            Fiscal_Year_Aware__c = false,
            Active__c = active
        );
    }

    @IsTest
    static void theDefaultModeComesFromTheOrgSetting() {
        SettingsService.saveSystemValue('Rollup_Mode_Default__c', RollupService.MODE_SCHEDULED);
        SettingsService.clearCaches();

        System.Assert.areEqual(
            RollupService.MODE_SCHEDULED,
            RollupService.defaultMode(),
            'A new rollup starts in the mode the org chose'
        );
    }

    @IsTest
    static void anOrgThatHasNotChosenGetsBoth() {
        // Written straight onto the record, not through the settings service: the service is
        // right to refuse a mode the shipped row does not offer, and what is being measured
        // here is what the reader does with a stored value that is wrong anyway, which is how
        // an org upgraded from an older row would arrive.
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.Rollup_Mode_Default__c = 'Nonsense';
        TestDataFactory.saveSettings(settings);

        System.Assert.areEqual(
            RollupService.MODE_BOTH,
            RollupService.defaultMode(),
            'Both is the mode R-R4 says keeps the numbers visibly right'
        );
    }

    @IsTest
    static void shippedDefaultsAreMaterializedOnceAndNeverOverwritten() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Core_Household_Member_Count',
                MasterLabel = 'Household member count',
                Definition_Key__c = 'Core_Household_Member_Count',
                Source_Object__c = 'Household_Member__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Mode__c = 'Both',
                Fiscal_Year_Aware__c = false,
                Default_Active__c = true,
                Package__c = 'Core'
            )
        };

        Test.startTest();
        Integer firstRun = RollupService.ensureDefaults();
        Integer secondRun = RollupService.ensureDefaults();
        Test.stopTest();

        System.Assert.areEqual(1, firstRun, 'The shipped default is created once');
        System.Assert.areEqual(
            0,
            secondRun,
            'And never again, so an upgrade leaves an edit alone (R-R6)'
        );

        List<Rollup_Definition__c> created = [
            SELECT Definition_Key__c, Is_Package_Default__c, Active__c, Mode__c
            FROM Rollup_Definition__c
        ];
        System.Assert.areEqual(1, created.size(), 'One definition');
        System.Assert.isTrue(created[0].Is_Package_Default__c, 'It is marked as shipped');
        System.Assert.isTrue(created[0].Active__c, 'And it is on');
    }

    @IsTest
    static void aDefaultThatCannotBeCreatedIsLoggedRatherThanThrownDuringAnInstall() {
        // A post-install script has nobody to report to and no way to retry, and an exception
        // that escapes it can abort the install (ADR-0029). The label here is longer than the
        // Rollup Name attribute allows, so the insert is refused by the platform.
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Core_Household_Member_Count',
                MasterLabel = 'x'.repeat(100),
                Definition_Key__c = 'Core_Household_Member_Count',
                Source_Object__c = 'Household_Member__c',
                Target_Object__c = 'Account',
                Relationship_Path__c = 'Household__c',
                Aggregate__c = 'COUNT',
                Target_Field__c = 'Member_Count__c',
                Mode__c = RollupService.MODE_BOTH,
                Default_Active__c = true,
                Package__c = 'Core'
            )
        };

        Test.startTest();
        // No try/catch on purpose: an exception escaping this call fails the test, which is the
        // assertion that an install is never aborted by this step.
        Integer created = RollupService.ensureDefaultsDuringInstall('TestPostInstall.rollups');
        Test.stopTest();

        System.Assert.areEqual(0, created, 'The caller is told that nothing was created');
        System.Assert.areEqual(0, [SELECT COUNT() FROM Rollup_Definition__c], 'And nothing was');
        List<Error_Log__c> logged = [
            SELECT Context__c, Technical_Detail__c
            FROM Error_Log__c
            WHERE Context__c = 'TestPostInstall.rollups'
        ];
        System.Assert.areEqual(
            1,
            logged.size(),
            'The failure is in the Error Log, named after the script that hit it'
        );
        System.Assert.isTrue(
            logged[0].Technical_Detail__c.contains('DmlException'),
            'And the technical detail names what the platform refused'
        );
    }

    @IsTest
    static void aDefaultForAPackageThatIsNotInstalledIsSkipped() {
        RollupSelector.defaultsOverride = new List<Rollup_Definition_Default__mdt>{
            new Rollup_Definition_Default__mdt(
                DeveloperName = 'Not_Installed',
                MasterLabel = 'A rollup for something that is not here',
                Definition_Key__c = 'Not_Installed',
                Source_Object__c = 'Nothing_Like_This__c',
                Target_Object__c = 'Account',
                Aggregate__c = 'COUNT',
                Relationship_Path__c = 'Account__c',
                Target_Field__c = 'Member_Count__c',
                Mode__c = 'Both',
                Default_Active__c = true,
                Package__c = 'Volunteers'
            )
        };

        System.Assert.areEqual(
            0,
            RollupService.ensureDefaults(),
            'A rollup whose records are not in this org names objects nobody has'
        );
    }

    @IsTest
    static void onlyTheActiveDefinitionsForTheChangedEntityRunInRealTime() {
        insert new List<Rollup_Definition__c>{
            memberCount(RollupService.MODE_REAL_TIME, true),
            memberCountNamed(
                'Scheduled only',
                'Core_Scheduled_Only',
                RollupService.MODE_SCHEDULED,
                true
            ),
            memberCountNamed('Turned off', 'Core_Turned_Off', RollupService.MODE_REAL_TIME, false)
        };

        List<Rollup_Definition__c> forRealTime = RollupSelector.selectActiveForSource(
            'Household_Member__c',
            new Set<String>{ RollupService.MODE_REAL_TIME, RollupService.MODE_BOTH }
        );

        System.Assert.areEqual(
            1,
            forRealTime.size(),
            'A scheduled rollup and an inactive one both stay out'
        );
        System.Assert.areEqual(
            'Core_Household_Member_Count',
            forRealTime[0].Definition_Key__c,
            'The right one runs'
        );
    }

    @IsTest
    static void aRunStampsTheDefinitionSoTheConsoleCanSayWhen() {
        Rollup_Definition__c definition = memberCount(RollupService.MODE_BOTH, true);
        insert definition;
        RollupService.skipEngine = true;

        Test.startTest();
        RollupService.recalculate(definition.Id);
        Test.stopTest();

        Rollup_Definition__c stamped = [
            SELECT Last_Calculated__c
            FROM Rollup_Definition__c
            WHERE Id = :definition.Id
        ];
        System.Assert.isNotNull(
            stamped.Last_Calculated__c,
            'R-R5: the console can say when this rollup last ran'
        );
        System.Assert.isFalse(RollupService.isStale(), 'A rollup that just ran is not overdue');
    }

    @IsTest
    static void anOrgThatHasNeverCalculatedIsReportedAsOverdue() {
        insert memberCount(RollupService.MODE_BOTH, true);

        System.Assert.isNull(RollupService.lastCalculated(), 'Nothing has run');
        System.Assert.isTrue(
            RollupService.isStale(),
            'Which the Hub tile says out loud (plan Section 4.10)'
        );
    }

    /**
     * Two definitions, one of which cannot be expressed to the engine. The point of the rule is
     * that the broken one is set aside and the run carries on, so the run has to contain
     * something for it to carry on with.
     */
    @IsTest
    static void aBrokenDefinitionIsLoggedAndTheRestStillRun() {
        Rollup_Definition__c broken = memberCountNamed(
            'Household member sum',
            'Core_Household_Member_Sum',
            RollupService.MODE_BOTH,
            true
        );
        broken.Aggregate__c = 'SUM';
        broken.Source_Field__c = null;
        Rollup_Definition__c good = memberCount(RollupService.MODE_BOTH, true);
        insert new List<Rollup_Definition__c>{ broken, good };
        RollupService.skipEngine = true;
        RollupService.lastMetadata = null;

        Test.startTest();
        Integer ran = RollupService.runFullRecalculation(
            new List<Rollup_Definition__c>{ broken, good }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        System.Assert.areEqual(
            1,
            ran,
            'The definition that cannot be expressed is skipped, not thrown, and the other one runs'
        );
        System.Assert.areEqual(
            1,
            RollupService.lastMetadata.size(),
            'One definition reached the engine'
        );
        System.Assert.areEqual(
            'Core_Household_Member_Count',
            RollupService.lastMetadata[0].DeveloperName,
            'And it is the good one'
        );
        Map<Id, Rollup_Definition__c> stampedById = new Map<Id, Rollup_Definition__c>(
            [SELECT Last_Calculated__c FROM Rollup_Definition__c]
        );
        System.Assert.isNotNull(
            stampedById.get(good.Id).Last_Calculated__c,
            'The one that ran is stamped as having run'
        );
        System.Assert.isNull(
            stampedById.get(broken.Id).Last_Calculated__c,
            'And the one that was refused is not, so the console does not claim it is current'
        );
        List<Error_Log__c> logged = [
            SELECT Record_Reference__c, Object_Name__c, Technical_Detail__c
            FROM Error_Log__c
            WHERE Context__c = 'RollupService.recalculate'
        ];
        System.Assert.areEqual(1, logged.size(), 'The refusal is in the log, once');
        System.Assert.areEqual(
            String.valueOf(broken.Id),
            logged[0].Record_Reference__c,
            'Naming the definition Maria has to fix'
        );
        System.Assert.areEqual(
            'Rollup_Definition__c',
            logged[0].Object_Name__c,
            'So the entry can be grouped by what it is about'
        );
        System.Assert.isTrue(
            logged[0].Technical_Detail__c.contains('RollupAdapterException'),
            'And the detail names what refused it'
        );
    }

    @IsTest
    static void recalculatingSomethingThatIsNotThereSaysSo() {
        try {
            RollupService.recalculate(null);
            System.Assert.fail(
                'An unknown definition is refused with a message an admin can act on'
            );
        } catch (RollupService.RollupServiceException expected) {
            System.Assert.isNotNull(expected.getMessage(), 'The message names the problem');
        }
    }

    @IsTest
    static void aMergeRecalculatesOnlyTheRealTimeTotalsOnTheMergedEntity() {
        insert new List<Rollup_Definition__c>{
            memberCountNamed('Live count', 'Core_Merge_Live', RollupService.MODE_BOTH, true),
            memberCountNamed(
                'Nightly count',
                'Core_Merge_Nightly',
                RollupService.MODE_SCHEDULED,
                true
            ),
            memberCountNamed('Off count', 'Core_Merge_Off', RollupService.MODE_BOTH, false)
        };
        RollupService.skipEngine = true;
        RollupService.lastMetadata = null;
        // MasterRecordId cannot be written, so the deleted record is built as the trigger has it.
        List<SObject> merged = new List<SObject>{
            (Account) JSON.deserialize(
                '{"attributes":{"type":"Account"},"MasterRecordId":"001000000000001AAA"}',
                Account.class
            )
        };
        RollupService.runAfterMerge('Account', new List<SObject>{ new Account(Name = 'Deleted') });
        System.Assert.isNull(
            RollupService.lastMetadata,
            'An ordinary delete names no survivor, so nothing is recalculated'
        );

        Test.startTest();
        RollupService.runAfterMerge('Contact', merged);
        List<Rollup__mdt> forPeople = RollupService.lastMetadata;
        RollupService.runAfterMerge('Account', merged);
        Test.stopTest();

        System.Assert.isNull(forPeople, 'No total targets people here, so nothing is run');
        System.Assert.areEqual(
            1,
            RollupService.lastMetadata.size(),
            'Only the active real-time total on the merged entity is recalculated'
        );
        System.Assert.areEqual(
            'Core_Merge_Live',
            RollupService.lastMetadata[0].DeveloperName,
            'And it is the live one'
        );
        System.Assert.areEqual(
            new Set<Id>{ Id.valueOf('001000000000001AAA') },
            RollupService.lastParentIds,
            'Only the survivor is recalculated, not every record the definition covers'
        );
    }

    @IsTest
    static void aFullRecalculationCallsTheEngineOncePerSourceEntity() {
        Rollup_Definition__c byMembership = memberCountNamed(
            'Members',
            'Core_Source_Membership',
            RollupService.MODE_BOTH,
            true
        );
        Rollup_Definition__c byContact = memberCountNamed(
            'Contacts',
            'Core_Source_Contact',
            RollupService.MODE_BOTH,
            true
        );
        byContact.Source_Object__c = 'Contact';
        byContact.Relationship_Path__c = 'AccountId';
        Rollup_Definition__c alsoByMembership = memberCountNamed(
            'Members again',
            'Core_Source_Membership_Two',
            RollupService.MODE_BOTH,
            true
        );
        insert new List<Rollup_Definition__c>{ byMembership, byContact, alsoByMembership };
        RollupService.skipEngine = true;

        Test.startTest();
        Integer ran = RollupService.runFullRecalculation(
            new List<Rollup_Definition__c>{ byMembership, byContact, alsoByMembership }
        );
        Test.stopTest();

        System.Assert.areEqual(3, ran, 'Every definition is recalculated');
        System.Assert.areEqual(
            2,
            RollupService.lastEngineCalls,
            'One engine call per source entity, because one call across two fails in the engine'
        );
        System.Assert.isNull(
            RollupService.lastParentIds,
            'A full recalculation covers every record'
        );
    }

    private static Rollup_Definition__c memberCountNamed(
        String name,
        String key,
        String mode,
        Boolean active
    ) {
        Rollup_Definition__c definition = memberCount(mode, active);
        definition.Name = name;
        definition.Definition_Key__c = key;
        return definition;
    }
}
