/**
 * Maria changes a setting in the console and expects three things: the value sticks, the
 * change is recorded, and a value that makes no sense is refused before anything is saved.
 */
@IsTest
private class SettingsServiceTest {
    private static final String TEXT_KEY = 'Household_Name_Pattern__c';
    private static final String CHECKBOX_KEY = 'Auto_Create_Households__c';
    private static final String DATETIME_KEY = 'Automation_Paused_Until__c';
    private static final String PROGRESS_KEY = 'Setup_Steps_Completed__c';

    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C03_Settings_Service_Test', UserInfo.getUserId());
    }

    @IsTest
    static void theCustomPermissionThisFeatureNeedsIsInstalled() {
        Assert.isTrue(
            SettingsTestPermissions.customPermissionExists(),
            'C-04 ships Manage BarnCRM Settings and merges before C-03: without it nobody can save'
        );
    }

    private static void stubDefinitions() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Household_Name_Pattern',
                MasterLabel = 'Household name pattern',
                Setting_Key__c = TEXT_KEY,
                Section__c = 'Households',
                Module__c = 'Core',
                Data_Type__c = 'Text',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Auto_Create_Households',
                MasterLabel = 'Create households automatically',
                Setting_Key__c = CHECKBOX_KEY,
                Section__c = 'Households',
                Module__c = 'Core',
                Data_Type__c = 'Checkbox',
                Sort_Order__c = 2
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Automation_Paused_Until',
                MasterLabel = 'Automation paused until',
                Setting_Key__c = DATETIME_KEY,
                Section__c = 'Automation',
                Module__c = 'Core',
                Data_Type__c = 'DateTime',
                Sort_Order__c = 1
            )
        };
    }

    @IsTest
    static void savesValueAndRecordsTheChange() {
        stubDefinitions();

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Family',
            SettingsService.getValue(TEXT_KEY),
            'Maria expects the pattern she typed to be the one in force'
        );
        List<Setting_Change__c> changes = SettingChangeSelector.getRecent(10);
        Assert.areEqual(1, changes.size(), 'One changed setting writes exactly one audit record');
        Assert.areEqual(
            'BarnCRM_Settings__c.' + TEXT_KEY,
            changes[0].Setting_Name__c,
            'The audit record names the settings object and the setting, because each package owns one'
        );
        Assert.areEqual(
            null,
            changes[0].Old_Value__c,
            'A setting that had never been set has no old value: unset is null, not empty text'
        );
        Assert.areEqual(
            'The {LastName} Family',
            changes[0].New_Value__c,
            'The audit record holds the new value'
        );
        Assert.areEqual(
            UserInfo.getUserId(),
            changes[0].Changed_By__c,
            'The audit record names who changed it'
        );
    }

    @IsTest
    static void savesADateAndTimeThePackageItselfHandsIn() {
        stubDefinitions();
        Datetime chosen = Datetime.newInstanceGmt(2026, 9, 7, 17, 0, 0);

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ DATETIME_KEY => chosen });
        Test.stopTest();

        Assert.areEqual(
            chosen,
            SettingsService.getValue(DATETIME_KEY),
            'A Datetime handed in as a Datetime is stored as it is: the Setup Assistant records ' +
            'when setup started this way, and text is not the only shape a value arrives in'
        );
    }

    @IsTest
    static void savingWithoutChangingAnythingRecordsNothing() {
        stubDefinitions();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        Assert.areEqual(
            1,
            SettingChangeSelector.getRecent(10).size(),
            'Saving a page without changing anything writes nothing'
        );
    }

    @IsTest
    static void savesSeveralSettingsInOneGo() {
        stubDefinitions();

        Test.startTest();
        SettingsService.saveValues(
            new Map<String, Object>{
                TEXT_KEY => 'The {LastName} Household',
                CHECKBOX_KEY => 'false',
                DATETIME_KEY => '2026-09-07T17:00:00.000Z'
            }
        );
        Test.stopTest();

        Assert.areEqual(
            3,
            SettingChangeSelector.getRecent(10).size(),
            'One audit record per changed setting'
        );
        Assert.areEqual(
            false,
            SettingsService.getValue(CHECKBOX_KEY),
            'A checkbox sent as text is read as a checkbox'
        );
        Assert.areNotEqual(
            null,
            SettingsService.getValue(DATETIME_KEY),
            'A date and time sent as text is read as one'
        );
    }

    @IsTest
    static void recordsAChangeThatIsOnlyACapitalLetter() {
        stubDefinitions();
        SettingsService.saveValues(
            new Map<String, Object>{ TEXT_KEY => 'The {LastName} household' }
        );

        Test.startTest();
        SettingsService.saveValues(
            new Map<String, Object>{ TEXT_KEY => 'The {LastName} Household' }
        );
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Household',
            SettingsService.getValue(TEXT_KEY),
            'Capitalising a word is a real edit and has to stick'
        );
        Assert.areEqual(
            2,
            SettingChangeSelector.getRecent(10).size(),
            'A change of case is recorded like any other change'
        );
    }

    @IsTest
    static void refusesAPicklistValueTheConsoleWouldNeverOffer() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Coexistence_Mode_Choice',
                MasterLabel = 'How BarnCRM fits your org',
                Setting_Key__c = 'Coexistence_Mode__c',
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = 'Picklist',
                Picklist_Values__c = 'Standalone:On its own;NonprofitCloud:Alongside Nonprofit Cloud',
                Sort_Order__c = 1
            )
        };
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(
                new Map<String, Object>{ 'Coexistence_Mode__c' => 'SomethingElse' }
            );
        } catch (SettingsService.SettingsException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_Settings_InvalidValueError,
                e.getMessage(),
                'The message says the value is not one this setting takes'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A choice that is not on the list is refused, whoever calls');
    }

    @IsTest
    static void refusesASettingThatDoesNotExist() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(new Map<String, Object>{ 'Not_A_Setting__c' => 'anything' });
        } catch (SettingsService.SettingsException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_Settings_UnknownKeyError,
                e.getMessage(),
                'The message tells Maria what to do'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A setting that does not exist is refused');
        Assert.areEqual(
            0,
            SettingChangeSelector.getRecent(10).size(),
            'Nothing is saved when one value is refused'
        );
    }

    @IsTest
    static void refusesASettingThatIsNotOnTheConsole() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(
                new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' }
            );
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A field with no console row is not editable from the console');
    }

    @IsTest
    static void refusesAValueInTheWrongFormat() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(new Map<String, Object>{ DATETIME_KEY => 'next Tuesday' });
        } catch (SettingsService.SettingsException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_Settings_InvalidValueError,
                e.getMessage(),
                'The message names the problem and what to do'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A date and time that cannot be read is refused');
    }

    @IsTest
    static void savesTheProgressKeyThePackageOwns() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        SettingsService.saveSystemValue(PROGRESS_KEY, 'coexistence,naming');
        Test.stopTest();

        Assert.areEqual(
            'coexistence,naming',
            SettingsService.getValue(PROGRESS_KEY),
            'The package writes its own progress key without a console row'
        );
    }

    @IsTest
    static void readingAnUnknownSettingIsRefused() {
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.getValue('Not_A_Setting__c');
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Reading a setting that does not exist is refused');
        Assert.isFalse(
            SettingsService.hasKey('Not_A_Setting__c'),
            'The org does not have that setting'
        );
        Assert.isTrue(
            SettingsService.hasKey(TEXT_KEY),
            'The org does have the household name pattern'
        );
    }

    @IsTest
    static void refusesASettingsObjectNoShippedRowNames() {
        stubDefinitions();
        Boolean refused = false;

        Test.startTest();
        try {
            SettingsService.saveValues(
                'Not_A_Settings_Object__c',
                new Map<String, Object>{ TEXT_KEY => 'anything' }
            );
        } catch (SettingsService.SettingsException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Only a settings object a shipped row names can be written');
    }

    @IsTest
    static void readsCoreSettingsByNameAsWellAsByDefault() {
        stubDefinitions();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });

        Test.startTest();
        Object named = SettingsService.getValue('BarnCRM_Settings__c', TEXT_KEY);
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Family',
            named,
            'Naming Core\'s own object reads the same value'
        );
        Assert.isTrue(
            SettingsService.hasKey('BarnCRM_Settings__c', TEXT_KEY),
            'Core owns the household name pattern'
        );
        Assert.isFalse(
            SettingsService.hasKey('BarnCRM_Settings__c', 'Not_A_Setting__c'),
            'Core does not own a setting that does not exist'
        );
    }

    /**
     * The console asks once per Setting Definition row. The type and its fields are cached for
     * the transaction, so asking again gives the same answer, an absent object included.
     */
    @IsTest
    static void hasKeyAnswersEveryRowFromTheSameLookup() {
        Test.startTest();
        for (Integer row = 0; row < 200; row++) {
            Assert.isTrue(SettingsService.hasKey('BarnCRM_Settings__c', TEXT_KEY), 'Row ' + row);
            Assert.isFalse(
                SettingsService.hasKey('Not_A_Settings_Object__c', TEXT_KEY),
                'An object the org lacks has no keys, row ' + row
            );
        }
        Test.stopTest();

        Assert.areEqual(
            SettingsService.typeByName('BarnCRM_Settings__c'),
            SettingsService.typeByName(' barncrm_settings__c '),
            'The cached lookup ignores case and spacing, like the describe it replaces'
        );
        Assert.isNull(SettingsService.typeByName('Not_A_Settings_Object__c'), 'Absent stays null');
    }

    @IsTest
    static void readsSettingsWithoutQueryingEveryTime() {
        Test.startTest();
        BarnCRM_Settings__c first = SettingsService.getSettings();
        BarnCRM_Settings__c second = SettingsService.getSettings();
        Test.stopTest();

        Assert.areNotEqual(null, first, 'An org that has never saved still gets a settings record');
        Assert.areEqual(first, second, 'The second read comes from the cache');
    }

    @IsTest
    static void theOrgSettingsAreReadOncePerTransaction() {
        TestDataFactory.defaultSettings();

        BarnCRM_Settings__c first = SettingsService.getSettings();
        BarnCRM_Settings__c second = SettingsService.getSettings();

        Assert.isNotNull(first, 'A fresh org has settings to read.');
        Assert.areEqual(first.Id, second.Id, 'The second read is the cached one.');
        Assert.areEqual(
            'The {LastName} Family',
            first.Household_Name_Pattern__c,
            'The shipped naming pattern is there on install.'
        );
    }

    @IsTest
    static void aWriteIsSeenByTheNextRead() {
        BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
        Assert.isNull(SettingsService.getSettings().Automation_Paused_Until__c, 'Not paused.');

        settings.Automation_Paused_Until__c = System.now().addHours(4);
        TestDataFactory.saveSettings(settings);

        Assert.isNotNull(
            SettingsService.getSettings().Automation_Paused_Until__c,
            'Clearing the cache on write means the next read is not stale.'
        );
    }

    @IsTest
    static void aModeIsReadBackAsItWasSaved() {
        BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Coexistence_Mode__c = 'NPSP';
        settings.Household_Membership_Mode__c = 'Junction';
        TestDataFactory.saveSettings(settings);

        Assert.areEqual('NPSP', SettingsService.coexistenceMode(), 'Maria chose NPSP coexistence.');
        Assert.areEqual(
            'Junction',
            SettingsService.householdMembershipMode(),
            'And junction membership.'
        );
    }

    @IsTest
    static void aModeNobodyRecognizesFallsBackToTheShippedDefault() {
        BarnCRM_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Coexistence_Mode__c = 'Something a data load put here';
        settings.Household_Membership_Mode__c = null;
        TestDataFactory.saveSettings(settings);

        Assert.areEqual(
            SettingsService.COEXISTENCE_MODE_DEFAULT,
            SettingsService.coexistenceMode(),
            'A value outside the list reads as the shipped default (ADR-0019).'
        );
        Assert.areEqual(
            SettingsService.MEMBERSHIP_MODE_DEFAULT,
            SettingsService.householdMembershipMode(),
            'So does an empty one.'
        );
    }

    @IsTest
    static void aModeIsCheckedOnItsWayIn() {
        Assert.areEqual(
            'NPSP',
            SettingsService.validated('NPSP', SettingsService.coexistenceModes()),
            'An offered value is accepted.'
        );

        for (String rejected : new List<String>{ 'npsp', '', null }) {
            try {
                SettingsService.validated(rejected, SettingsService.membershipModes());
                Assert.fail('The value "' + rejected + '" should be refused.');
            } catch (SettingsService.SettingsServiceException expected) {
                Assert.areEqual(
                    Label.Core_Settings_ModeValueInvalid,
                    expected.getMessage(),
                    'Maria is told to pick from the list.'
                );
            }
        }
        try {
            SettingsService.validated('Contact', null);
            Assert.fail('A value with no list to check against should be refused.');
        } catch (SettingsService.SettingsServiceException expected) {
            Assert.isNotNull(expected.getMessage(), 'With a message.');
        }
    }

    @IsTest
    static void theShippedDefaultsAreExactlyWhatTheFieldsSay() {
        // A text field default value is a formula, so whatever sits inside the quotes is the
        // value a fresh org gets: " Standalone " is not a coexistence mode the service
        // recognizes, and a padded pattern puts spaces into every household name C-02 computes.
        // The formula is read from the field describe and not from getOrgDefaults(), because on a
        // fresh org that returns an empty in-memory instance whose every value is null, so an
        // assertion made against it passes whatever the field ships.
        Map<String, String> expectedByField = new Map<String, String>{
            'Coexistence_Mode__c' => '"' +
            SettingsService.COEXISTENCE_MODE_DEFAULT +
            '"',
            'Household_Membership_Mode__c' => '"' +
            SettingsService.MEMBERSHIP_MODE_DEFAULT +
            '"',
            'Household_Name_Pattern__c' => '"The {LastName} Family"',
            'Formal_Greeting_Pattern__c' => '"{Salutation} {FirstName} {LastName}"',
            'Informal_Greeting_Pattern__c' => '"{FirstName}"'
        };
        Map<String, Schema.SObjectField> shipped = Schema.SObjectType.BarnCRM_Settings__c.fields.getMap();

        for (String fieldName : expectedByField.keySet()) {
            String formula = shipped.get(fieldName).getDescribe().getDefaultValueFormula();
            Assert.isNotNull(formula, fieldName + ' ships a default value.');
            Assert.areEqual(
                formula,
                formula.trim(),
                'The default formula for ' + fieldName + ' carries no padding: "' + formula + '"'
            );
            Assert.areEqual(
                formula.removeStart('"').removeEnd('"'),
                formula.removeStart('"').removeEnd('"').trim(),
                'And no padding inside the quotes either: "' + formula + '"'
            );
            Assert.areEqual(
                expectedByField.get(fieldName),
                formula,
                'The shipped default for ' + fieldName + ' is exactly the literal we mean.'
            );
        }

        Assert.isTrue(
            SettingsService.coexistenceModes().contains(SettingsService.COEXISTENCE_MODE_DEFAULT),
            'And the code default is itself one of the offered values.'
        );
        Assert.isTrue(
            SettingsService.membershipModes().contains(SettingsService.MEMBERSHIP_MODE_DEFAULT),
            'For both keys.'
        );
    }

    @IsTest
    static void everyChangeIsRecordedWithWhoWhenAndWhat() {
        Test.startTest();
        SettingsService.logChange(
            'Household naming pattern',
            'The {LastName} Family',
            '{LastName}'
        );
        SettingsService.logChange('  ', 'something', 'something else');
        Test.stopTest();

        List<Setting_Change__c> audit = [
            SELECT Setting_Name__c, Old_Value__c, New_Value__c, Changed_By__c, Changed_At__c
            FROM Setting_Change__c
        ];
        Assert.areEqual(1, audit.size(), 'A change with no setting name is not an audit row.');
        Assert.areEqual('Household naming pattern', audit[0].Setting_Name__c, 'What changed.');
        Assert.areEqual('The {LastName} Family', audit[0].Old_Value__c, 'What it was.');
        Assert.areEqual('{LastName}', audit[0].New_Value__c, 'What it is now.');
        Assert.areEqual(UserInfo.getUserId(), audit[0].Changed_By__c, 'Who changed it.');
        Assert.isNotNull(audit[0].Changed_At__c, 'And when.');
    }

    /**
     * The trap C-15 fell into. A checkbox that ships on declares `defaultValue` true in its
     * field metadata, but `getOrgDefaults()` on an org that has never saved returns a
     * materialized record with every checkbox false, so a feature guarded by one did nothing
     * on a fresh install and said nothing about it (ADR-0035).
     */
    @IsTest
    static void aCheckboxThatShipsOnReadsOnBeforeTheOrgHasSavedAnything() {
        Test.startTest();
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        Test.stopTest();

        Assert.isNull(settings.Id, 'This org has never saved its settings');
        Assert.isTrue(
            settings.Relationship_Auto_Reciprocal__c,
            'A setting that ships switched on reads on before anyone has saved anything'
        );
    }

    /**
     * The second half of the same trap: the console writes only the keys it was given, so a
     * record created by saving something else would carry a false for every checkbox nobody
     * touched, and would switch a shipped feature off on the way past.
     */
    @IsTest
    static void savingAnUnrelatedSettingKeepsAShippedDefaultOn() {
        stubDefinitions();

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        BarnCRM_Settings__c stored = SettingsService.getSettings();
        Assert.isNotNull(stored.Id, 'Saving one value creates the org level record');
        Assert.areEqual(
            'The {LastName} Family',
            stored.Household_Name_Pattern__c,
            'With the value that was saved'
        );
        Assert.isTrue(
            stored.Relationship_Auto_Reciprocal__c,
            'And the shipped defaults it never asked about, rather than a false nobody chose'
        );
    }

    /**
     * Two administrators with the console open: this transaction read its copy, then the other
     * one saved the naming pattern. The cache here never heard of that save.
     */
    private static Id staleCopyThenAnotherSave() {
        stubDefinitions();
        insert new BarnCRM_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Household_Name_Pattern__c = 'The {LastName} Family',
            Auto_Create_Households__c = true
        );
        Assert.areEqual(
            'The {LastName} Family',
            SettingsService.getSettings().Household_Name_Pattern__c,
            'This transaction holds its copy'
        );
        BarnCRM_Settings__c theirs = [
            SELECT Id
            FROM BarnCRM_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ];
        theirs.Household_Name_Pattern__c = '{LastName} Household';
        update theirs;
        return theirs.Id;
    }

    @IsTest
    static void aSaveKeepsAKeyAnotherAdministratorSavedMeanwhile() {
        Id recordId = staleCopyThenAnotherSave();

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ CHECKBOX_KEY => false });
        Test.stopTest();

        BarnCRM_Settings__c saved = [
            SELECT Household_Name_Pattern__c, Auto_Create_Households__c
            FROM BarnCRM_Settings__c
            WHERE Id = :recordId
        ];
        Assert.isFalse(saved.Auto_Create_Households__c, 'The key Maria changed is saved');
        Assert.areEqual(
            '{LastName} Household',
            saved.Household_Name_Pattern__c,
            'And the pattern the other administrator saved is not written back from her stale copy'
        );
        List<Setting_Change__c> changes = SettingChangeSelector.getRecent(10);
        Assert.areEqual(1, changes.size(), 'One audit row, for the one key she changed');
    }

    @IsTest
    static void aValueComparedAgainstTheStoredRecordNotAStaleCopy() {
        Id recordId = staleCopyThenAnotherSave();

        Test.startTest();
        SettingsService.saveValues(new Map<String, Object>{ TEXT_KEY => 'The {LastName} Family' });
        Test.stopTest();

        Assert.areEqual(
            'The {LastName} Family',
            [SELECT Household_Name_Pattern__c FROM BarnCRM_Settings__c WHERE Id = :recordId]
            .Household_Name_Pattern__c,
            'Her value matched only her stale copy, and it is still saved over the stored one'
        );
        List<Setting_Change__c> changes = SettingChangeSelector.getRecent(10);
        Assert.areEqual(1, changes.size(), 'The change is audited');
        Assert.areEqual(
            '{LastName} Household',
            changes[0].Old_Value__c,
            'With the old value that was really stored, not the one in her copy'
        );
    }

    private static final String RECORD_KEY = 'Organization_Legal_Name__c';
    private static final String RECORD_TYPES_KEY = 'Formal_Greeting_Pattern__c';

    /** A Record row on Account and a Record Type List row on Account, both on Core keys. */
    private static void stubPickerDefinitions() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>{
            new Setting_Definition__mdt(
                DeveloperName = 'Picked_Account',
                MasterLabel = 'Picked account',
                Setting_Key__c = RECORD_KEY,
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = SettingsService.RECORD,
                Record_Object__c = 'Account',
                Sort_Order__c = 1
            ),
            new Setting_Definition__mdt(
                DeveloperName = 'Picked_Record_Types',
                MasterLabel = 'Picked record types',
                Setting_Key__c = RECORD_TYPES_KEY,
                Section__c = SettingSections.GENERAL,
                Module__c = 'Core',
                Data_Type__c = SettingsService.RECORD_TYPE_LIST,
                Record_Object__c = 'Account',
                Sort_Order__c = 2
            )
        };
    }

    /** An Id of the given object that no record needs to carry: only its prefix is read. */
    private static String idOf(Schema.SObjectType type) {
        return type.getDescribe().getKeyPrefix() + '000000000001AAA';
    }

    private static String refusalOf(String key, Object value) {
        try {
            SettingsService.saveValues(new Map<String, Object>{ key => value });
        } catch (SettingsService.SettingsException e) {
            return e.getMessage();
        }
        return null;
    }

    @IsTest
    static void aRecordSettingTakesOnlyARecordOfItsObject() {
        stubPickerDefinitions();
        String accountId = idOf(Account.SObjectType);

        Test.startTest();
        String wrongObject = refusalOf(RECORD_KEY, idOf(Contact.SObjectType));
        String notAnId = refusalOf(RECORD_KEY, 'General Fund');
        String accepted = refusalOf(RECORD_KEY, accountId);
        Test.stopTest();

        Assert.areEqual(
            System.Label.Core_Settings_InvalidValueError,
            wrongObject,
            'A record of another object is refused'
        );
        Assert.areEqual(
            System.Label.Core_Settings_InvalidValueError,
            notAnId,
            'A name typed instead of a picked record is refused'
        );
        Assert.isNull(accepted, 'A record of the row object is accepted');
        Assert.areEqual(
            accountId,
            String.valueOf(SettingsService.getValue(RECORD_KEY)),
            'The picked record Id is what is stored'
        );
    }

    @IsTest
    static void aRecordTypeListTakesOnlyRecordTypesTheObjectHas() {
        stubPickerDefinitions();
        List<Schema.RecordTypeInfo> offered = SettingsService.recordTypes(Account.SObjectType);
        Assert.isFalse(offered.isEmpty(), 'Core ships active Account record types');
        String known = offered[0].getDeveloperName();

        Test.startTest();
        String unknown = refusalOf(RECORD_TYPES_KEY, known + ',Not_A_Record_Type');
        String accepted = refusalOf(RECORD_TYPES_KEY, known);
        String cleared = refusalOf(RECORD_TYPES_KEY, '');
        Test.stopTest();

        Assert.areEqual(
            System.Label.Core_Settings_InvalidValueError,
            unknown,
            'A record type the object does not have is refused, with the known one beside it'
        );
        Assert.isNull(accepted, 'A record type the object has is accepted');
        Assert.isNull(cleared, 'None ticked is accepted and means every record type');
        for (Schema.RecordTypeInfo info : offered) {
            Assert.isTrue(info.isActive() && !info.isMaster(), 'Only active real record types');
        }
    }
}
