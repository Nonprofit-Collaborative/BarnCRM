/**
 * Maria works down the setup checklist, and the Hub remembers where she got to.
 */
@IsTest
private class SetupAssistantServiceTest {
    @TestSetup
    static void grantPermission() {
        SettingsTestPermissions.grantTo('C03_Setup_Assistant_Test', UserInfo.getUserId());
    }

    @IsTest
    static void shipsSevenStepsInOrderOnCoreAlone() {
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(7, steps.size(), 'Core alone ships seven setup steps (ADR-0059)');
        for (Integer i = 0; i < steps.size(); i++) {
            Assert.areEqual(
                i + 1,
                steps[i].position,
                'Steps are numbered in the order Maria works through them'
            );
            Assert.isNotNull(steps[i].label, 'Every step is named in the language Maria uses');
            Assert.isNotNull(steps[i].description, 'Every step says what it is for');
            Assert.isNotNull(steps[i].completed, 'Every step says whether it is done');
        }
        Assert.isFalse(
            stepByKey(steps, 'modules').completed,
            'A step nobody has marked and no setting completes is still to do'
        );
        Assert.areEqual(
            'coexistence',
            steps[0].key,
            'Confirming how Open Impact fits the org comes first'
        );
        Assert.areEqual(
            '/lightning/setup/ManageUsers/home',
            steps[2].setupPath,
            'Creating a colleague who has never signed in is the one part of access Salesforce keeps in Setup'
        );
    }

    @IsTest
    static void remembersWhichStepsAreDone() {
        Integer before = SetupAssistantService.countCompleted(SetupAssistantService.getSteps());

        Test.startTest();
        List<SetupAssistantService.Step> afterMarking = SetupAssistantService.markComplete(
            'modules'
        );
        Test.stopTest();

        Assert.areEqual(
            before + 1,
            SetupAssistantService.countCompleted(afterMarking),
            'One more step is done'
        );
        Assert.isTrue(
            stepByKey(afterMarking, 'modules').completed,
            'The step Maria marked is the one that is done'
        );
    }

    @IsTest
    static void countsAStepDoneWhenItsSettingIsFilledIn() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SettingsService.saveSystemValue('Household_Name_Pattern__c', 'The {LastName} Family');

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.isTrue(
            stepByKey(steps, 'naming').completed,
            'A step whose setting already has a value does not need marking'
        );
    }

    @IsTest
    static void refusesAStepItDoesNotShip() {
        Boolean refused = false;

        Test.startTest();
        try {
            SetupAssistantService.markComplete('not-a-step');
        } catch (SetupAssistantService.SetupStepException e) {
            refused = true;
            Assert.areEqual(
                System.Label.Core_SetupAssistant_UnknownStepError,
                e.getMessage(),
                'The message says what to do next'
            );
        }
        Test.stopTest();

        Assert.isTrue(refused, 'A step key the package does not ship is refused');
    }

    @IsTest
    static void remembersASkippedStepWithoutCountingItDone() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.markSkipped('data');
        Test.stopTest();

        SetupAssistantService.Step step = stepByKey(steps, 'data');
        Assert.isTrue(step.skipped, 'The step Maria skipped is out of the way');
        Assert.isFalse(step.completed, 'Skipping a step is not the same as finishing it');
    }

    @IsTest
    static void timesHowLongSetupTakes() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        Assert.isNull(
            SetupAssistantService.elapsedMinutes(),
            'Nothing has been done yet, so there is nothing to time'
        );

        Test.startTest();
        SetupAssistantService.markComplete('modules');
        Test.stopTest();

        Assert.isNotNull(
            SetupAssistantService.getStartedAt(),
            'The clock starts at the first change'
        );
        Assert.areEqual(
            0,
            SetupAssistantService.elapsedMinutes(),
            'A test finishes setup in under a minute'
        );
    }

    @IsTest
    static void putsTheStepsMariaRecordedBackOnTheList() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SettingsService.saveSystemValue('Household_Name_Pattern__c', 'The {LastName} Family');
        SetupAssistantService.markComplete('modules');
        SetupAssistantService.markSkipped('data');

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.reset();
        Test.stopTest();

        Assert.isFalse(
            stepByKey(steps, 'modules').completed,
            'A step Maria recorded as done is back on the list'
        );
        Assert.isFalse(stepByKey(steps, 'data').skipped, 'A skip is forgotten too');
        Assert.isNull(SetupAssistantService.getStartedAt(), 'So is when setup started');
        Assert.isTrue(
            stepByKey(steps, 'naming').completed,
            'A step whose setting really does have a value stays done: re-running setup revisits decisions, it does not empty the org'
        );
    }

    @IsTest
    static void readsThePersonAccountsShapeAsTheNonprofitCloudCase() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasIndustriesNonprofit = true;
        SetupAssistantService.stubbedShape = shape;

        Test.startTest();
        String detected = SetupAssistantService.detectedShape();
        String recommended = SetupAssistantService.recommendedMode();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.SHAPE_PERSON_ACCOUNTS,
            detected,
            'A Nonprofit Cloud org is recognised by its shape, not by asking Maria'
        );
        Assert.areEqual(
            SetupAssistantService.MODE_AGENTFORCE,
            recommended,
            'And it is recommended the coexistence mode built for it'
        );
    }

    @IsTest
    static void saysHowEachStepFinishes() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantService.RULE_SETTING,
            stepByKey(steps, 'naming').completionRule,
            'A step backed by a setting says so, so the page can explain how it finishes'
        );
        Assert.areEqual(
            SetupAssistantService.RULE_ACTION,
            stepByKey(steps, 'modules').completionRule,
            'A step with no setting behind it finishes when Maria finishes it'
        );
        Assert.areEqual(
            2,
            stepByKey(steps, 'identity').fields.size(),
            'On Core alone the organization step asks for the legal name and the address'
        );
    }

    @IsTest
    static void placesAModuleStepWhereItsSortOrderSays() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantTestExtension.useThis();

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(8, steps.size(), 'The module adds one step to Core\'s seven');
        Assert.areEqual(SetupAssistantTestExtension.STEP_KEY, steps[2].key, 'It comes third');
        Assert.areEqual(3, steps[2].position, 'And is numbered where it stands');
        Assert.areEqual('access', steps[3].key, 'The Core steps after it move down one');
        Assert.areEqual(
            SetupAssistantService.RULE_SETTING,
            steps[2].completionRule,
            'A module step can finish when its setting has a value'
        );
        Assert.isTrue(steps[2].advanceOnSave, 'A one question step moves on once answered');
        Assert.areEqual('Contact', steps[2].fields[0].objectApiName, 'Its picker names its object');
    }

    @IsTest
    static void letsAModuleAddFieldsAndWordingToACoreStep() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantTestExtension.useThis();

        Test.startTest();
        SetupAssistantService.Step identity = SetupAssistantService.findStep('identity');
        Test.stopTest();

        Assert.areEqual(
            SetupAssistantTestExtension.IDENTITY_WORDING,
            identity.description,
            'The module words the step for what it now asks'
        );
        Assert.areEqual(
            System.Label.Core_SetupAssistant_Step5Label,
            identity.label,
            'A contribution with no label keeps the Core one'
        );
        Assert.areEqual(3, identity.fields.size(), 'Core\'s two fields and the module\'s one');
        Assert.areEqual(
            SetupAssistantService.FIELD_NAVIGATE,
            identity.fields[1].fieldType,
            'Fields are ordered by sort order, whichever package declared them'
        );
    }

    @IsTest
    static void opensWithCoreStepsWhenAModuleFails() {
        SettingDefinitionSelector.stubbedRows = new List<Setting_Definition__mdt>();
        SetupAssistantExtensions.overrides = new List<SetupAssistantExtension>{
            new SetupAssistantTestExtension(true)
        };

        Test.startTest();
        List<SetupAssistantService.Step> steps = SetupAssistantService.getSteps();
        Test.stopTest();

        Assert.areEqual(7, steps.size(), 'A module that throws is left out, and setup still opens');
    }

    @IsTest
    static void findsNoStepForAKeyNobodyShips() {
        SetupAssistantTestExtension.useNone();

        Test.startTest();
        SetupAssistantService.Step missing = SetupAssistantService.findStep('moduledefaults');
        Test.stopTest();

        Assert.isNull(missing, 'A module step is not there when the module is not');
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
