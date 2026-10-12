/**
 * Maria works through the guided assistant: she confirms how Open Impact fits her
 * Nonprofit Cloud org, records her organization's name, answers the step a module adds,
 * skips a step, and starts again when she wants to.
 *
 * Each test says which modules it runs with (`SetupAssistantTestExtension`), because Core is
 * tested both on its own and with Giving beside it (ADR-0013, ADR-0059).
 *
 * The permission the assistant checks is granted in setup, so the saving tests assert the
 * saving path itself, and David's refusal is asserted once, under `System.runAs`.
 */
@IsTest
private class SetupAssistantControllerTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C12_Setup_Assistant_Test', UserInfo.getUserId());
    }

    private static User buildDavid() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            FirstName = 'David',
            LastName = 'Okonkwo',
            Alias = 'davids',
            Email = 'david.setup@example.com',
            Username = 'david.setup.' + DateTime.now().getTime() + '@example.com',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'America/New_York',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    @IsTest
    static void opensWithEveryPanelItNeeds() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.getState();
        Test.stopTest();

        Assert.areEqual(7, state.stepsTotal, 'Core alone has seven setup steps');
        Assert.areEqual(7, state.steps.size(), 'Every step is sent to the page at once');
        Assert.isNotNull(state.coexistence, 'Step one needs what detection found');
        Assert.areEqual(
            2,
            stepByKey(state.steps, 'identity').fields.size(),
            'The organization step carries the fields it is going to edit'
        );
        Assert.areEqual(6, state.modules.size(), 'The modules step lists the six packages');
        Assert.isNotNull(state.roles, 'The access step needs the roles it can give out');
        Assert.isFalse(state.isComplete, 'A fresh org has not finished setup');
    }

    @IsTest
    static void leadsWithTheNonprofitCloudCase() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        SetupAssistantService.stubbedShape = shape;

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.getState();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.SHAPE_PERSON_ACCOUNTS,
            state.coexistence.detectedShape,
            'An org with Person Accounts is recognised as the Nonprofit Cloud case'
        );
        Assert.areEqual(
            SetupAssistantService.MODE_AGENTFORCE,
            state.coexistence.recommendedMode,
            'That org is recommended Agentforce Nonprofit coexistence (plan Section 4.5)'
        );
    }

    @IsTest
    static void recommendsNpspCoexistenceWhenNpspIsInstalled() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        SetupAssistantService.stubbedShape = shape;

        Test.startTest();
        String recommended = SetupAssistantService.recommendedMode();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.MODE_NPSP,
            recommended,
            'An org with NPSP keeps the households it already has'
        );
    }

    @IsTest
    static void confirmsTheCoexistenceModeAndMarksStepOneDone() {
        // The shipped Setting Definition rows, not an empty stub: the coexistence mode is an
        // ordinary setting, and a save of a key with no row is refused.
        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.applyCoexistence(
            SetupAssistantService.MODE_STANDALONE
        );
        Test.stopTest();

        Assert.isTrue(
            stepByKey(state.steps, 'coexistence').completed,
            'Confirming the mode is what finishes step one'
        );
        Assert.isNotNull(state.elapsedMinutes, 'The clock starts at the first change Maria makes');
    }

    @IsTest
    static void refusesAModeItDoesNotKnow() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.applyCoexistence('SomethingElse');
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A mode outside the three the plan names is refused');
    }

    @IsTest
    static void savesTheOrganizationIdentityAndFinishesItsStep() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.saveStepValues(
            'identity',
            new Map<String, Object>{
                'Organization_Legal_Name__c' => 'Riverside Community Aid',
                'Organization_Address__c' => '1 River Road'
            }
        );
        Test.stopTest();

        SetupAssistantService.Step identity = stepByKey(state.steps, 'identity');
        Assert.areEqual(
            'Riverside Community Aid',
            identity.fields[0].value,
            'The field shows the legal name Maria saved'
        );
        Assert.isTrue(identity.completed, 'The legal name is what finishes the step');
    }

    @IsTest
    static void refusesKeysTheStepDoesNotDeclare() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useNone();
        Boolean refused = false;
        String message;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                'identity',
                new Map<String, Object>{
                    'Not_A_Setting__c' => 'x',
                    'Household_Name_Pattern__c' => 'The {LastName} Family'
                }
            );
        } catch (AuraHandledException e) {
            refused = true;
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Only the keys the step declares are accepted');
        Assert.areEqual(
            System.Label.Core_SetupAssistant_NothingToSaveError,
            message,
            'A setting on another step is not saved through this one'
        );
    }

    @IsTest
    static void refusesTextLongerThanTheFieldAllows() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useNone();
        String message;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                'identity',
                new Map<String, Object>{ 'Organization_Legal_Name__c' => 'x'.repeat(256) }
            );
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.isNotNull(message, 'A name longer than the field allows is refused');
        Assert.isTrue(message.contains('255'), 'The message says how long it may be');
        Assert.isNull(savedLegalName(), 'Nothing was saved');
    }

    @IsTest
    static void refusesTextNotInTheShapeTheFieldAsksFor() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useSpanningTwoObjects();
        String message;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                'identity',
                new Map<String, Object>{
                    'Organization_Legal_Name__c' => 'Riverside Community Aid',
                    SetupAssistantTestExtension.CODE_KEY => 'abc'
                }
            );
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantTestExtension.CODE_PATTERN_MESSAGE,
            message,
            'A value saved without the page, as after an upload, is checked on the server too'
        );
        Assert.isNull(savedLegalName(), 'Nothing in the step was saved');
    }

    @IsTest
    static void aStepSpanningTwoSettingsObjectsSavesAllOrNothing() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useSpanningTwoObjects();
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                'identity',
                new Map<String, Object>{
                    'Organization_Legal_Name__c' => 'Riverside Community Aid',
                    SetupAssistantTestExtension.CODE_KEY => 'RC-01'
                }
            );
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'The module settings object cannot be written here');
        Assert.isNull(
            savedLegalName(),
            'The legal name, saved first, was rolled back with the failed half'
        );
    }

    @IsTest
    static void refusesAStepOnlyAnAbsentModuleShips() {
        SetupAssistantTestExtension.useNone();
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                SetupAssistantTestExtension.STEP_KEY,
                new Map<String, Object>{ SetupAssistantTestExtension.RECORD_KEY => null }
            );
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'With the module absent its step does not exist');
    }

    @IsTest
    static void savesAModuleStepAndFinishesIt() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useThis();
        Contact chosen = new Contact(LastName = 'Ruiz');
        insert chosen;

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.saveStepValues(
            SetupAssistantTestExtension.STEP_KEY,
            new Map<String, Object>{ SetupAssistantTestExtension.RECORD_KEY => chosen.Id }
        );
        Test.stopTest();

        Assert.areEqual(8, state.stepsTotal, 'The module step is counted');
        Assert.isTrue(
            stepByKey(state.steps, SetupAssistantTestExtension.STEP_KEY).completed,
            'Choosing the record is what finishes the module step'
        );
    }

    @IsTest
    static void refusesARecordThatIsNotTheKindTheStepAsksFor() {
        SettingDefinitionSelector.stubbedRows = identityRows();
        SetupAssistantTestExtension.useThis();
        String message;

        Test.startTest();
        try {
            SetupAssistantController.saveStepValues(
                SetupAssistantTestExtension.STEP_KEY,
                new Map<String, Object>{
                    SetupAssistantTestExtension.RECORD_KEY => UserInfo.getUserId()
                }
            );
        } catch (AuraHandledException e) {
            message = e.getMessage();
        }
        Test.stopTest();

        Assert.areEqual(
            System.Label.Core_SetupAssistant_WrongRecordTypeError,
            message,
            'A user identifier is not a contact, so it never becomes the default'
        );
    }

    @IsTest
    static void skipsAStepWithoutCountingItDone() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.skipStep('data');
        Test.stopTest();

        SetupAssistantService.Step step = stepByKey(state.steps, 'data');
        Assert.isTrue(step.skipped, 'The step is out of the way');
        Assert.isFalse(step.completed, 'Skipping is not finishing');
        Assert.areEqual(0, state.stepsCompleted, 'A skipped step does not count towards progress');
    }

    @IsTest
    static void finishesAStepThatHasNoSettingBehindIt() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.completeStep(
            'modules'
        );
        Test.stopTest();

        Assert.isTrue(
            stepByKey(state.steps, 'modules').completed,
            'Reading the module list is what finishes step six'
        );
    }

    @IsTest
    static void refusesAStepTheAssistantDoesNotShip() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.completeStep('not-a-step');
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A step key the package does not ship is refused');
    }

    @IsTest
    static void givesAColleagueARoleAndFinishesStepFour() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        TestDataFactory.prepareRoleGroup(AccessService.ADMIN_ROLE);

        // The page makes two calls, as it must: the role is a setup object write, and the
        // step's progress cannot be saved in the same transaction. The role is given in a
        // context of its own here for the same reason.
        Test.startTest();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            SetupAssistantController.assignAccess(UserInfo.getUserId(), AccessService.ADMIN_ROLE);
        }
        SetupAssistantController.SetupState state = SetupAssistantController.completeStep('access');
        Test.stopTest();

        String adminRole = AccessService.ADMIN_ROLE;
        Assert.areEqual(
            1,
            [
                SELECT COUNT()
                FROM PermissionSetAssignment
                WHERE
                    AssigneeId = :UserInfo.getUserId()
                    AND PermissionSetGroup.DeveloperName = :adminRole
            ],
            'The colleague holds the role'
        );
        Assert.isTrue(
            stepByKey(state.steps, 'access').completed,
            'Giving someone a role is what finishes step four'
        );
    }

    @IsTest
    static void refusesAccessWithNobodyChosen() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantController.assignAccess(null, null);
        } catch (AuraHandledException e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A person and a role are both needed');
    }

    @IsTest
    static void startsAgainWhenTheOrganizationChanges() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantController.completeStep('modules');

        Test.startTest();
        SetupAssistantController.SetupState state = SetupAssistantController.reset();
        Test.stopTest();

        Assert.areEqual(0, state.stepsCompleted, 'Every step Maria recorded is back on the list');
        Assert.isNull(state.elapsedMinutes, 'The clock starts again with the next change');
    }

    @IsTest
    static void letsDavidReadTheStepsAndRefusesHisChanges() {
        SetupAssistantTestExtension.useNone();
        User david = buildDavid();
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert david;
        }
        Boolean refused = false;

        Test.startTest();
        System.runAs(david) {
            SetupAssistantController.SetupState state = SetupAssistantController.getState();
            Assert.areEqual(7, state.steps.size(), 'David sees the same seven steps');
            Assert.isFalse(state.canEdit, 'David may read the assistant but not change it');
            try {
                SetupAssistantController.completeStep('modules');
            } catch (AuraHandledException e) {
                refused = true;
                Assert.areEqual(
                    System.Label.Core_Settings_PermissionRequiredError,
                    e.getMessage(),
                    'The message names the permission he is missing'
                );
            }
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Finishing a step without the permission is refused');
    }

    private static List<Setting_Definition__mdt> identityRows() {
        List<Setting_Definition__mdt> rows = new List<Setting_Definition__mdt>();
        for (
            String key : new List<String>{ 'Organization_Legal_Name__c', 'Organization_Address__c' }
        ) {
            rows.add(
                new Setting_Definition__mdt(
                    Setting_Key__c = key,
                    Settings_Object__c = 'Nonprofit_Settings__c',
                    Section__c = 'Organization',
                    Module__c = 'Core',
                    Data_Type__c = 'Text'
                )
            );
        }
        return rows;
    }

    /** What is actually stored, read past any cached org default. */
    private static String savedLegalName() {
        List<Nonprofit_Settings__c> rows = [
            SELECT Organization_Legal_Name__c
            FROM Nonprofit_Settings__c
            WHERE SetupOwnerId = :UserInfo.getOrganizationId()
        ];
        return rows.isEmpty() ? null : rows[0].Organization_Legal_Name__c;
    }

    private static SetupAssistantService.Step stepByKey(
        List<SetupAssistantService.Step> steps,
        String key
    ) {
        for (SetupAssistantService.Step step : steps) {
            if (step.key == key) {
                return step;
            }
        }
        return null;
    }
}
