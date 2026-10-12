/**
 * Proves, in an org with both packages installed, that Core's Setup Assistant finds
 * `GivingSetupAssistantExtension` by name and reads as it did before Core was made neutral
 * (C-29, ADR-0059): eight steps, the fund and appeal step third, the receipt fields on the
 * organization step, and the first gift button last.
 *
 * `SetupAssistantService.Step` and `StepField` fields are `@AuraEnabled` only, not
 * `@NamespaceAccessible`, so under a future namespace prefix this package cannot read them
 * directly. A JSON round trip reaches them the way the Lightning wire path does.
 */
@IsTest
private class GivingSetupAssistantExtensionTest {
    private static List<Object> asList(List<SetupAssistantService.Step> steps) {
        return (List<Object>) JSON.deserializeUntyped(JSON.serialize(steps));
    }

    private static Map<String, Object> stepByKey(List<Object> steps, String key) {
        for (Object step : steps) {
            Map<String, Object> fields = (Map<String, Object>) step;
            if (fields.get('key') == key) {
                return fields;
            }
        }
        return null;
    }

    private static List<String> fieldKeys(Map<String, Object> step) {
        List<String> keys = new List<String>();
        for (Object field : (List<Object>) step.get('fields')) {
            keys.add((String) ((Map<String, Object>) field).get('key'));
        }
        return keys;
    }

    @IsTest
    static void keepsTheEightStepFlowWithGivingInstalled() {
        Test.startTest();
        List<Object> steps = asList(SetupAssistantService.getSteps());
        Test.stopTest();

        List<String> keys = new List<String>();
        for (Object step : steps) {
            keys.add((String) ((Map<String, Object>) step).get('key'));
        }
        System.assertEquals(
            new List<String>{
                'coexistence',
                'naming',
                'funddefaults',
                'access',
                'identity',
                'modules',
                'data',
                'verify'
            },
            keys,
            'Giving adds the fund and appeal step third, as before'
        );
        Map<String, Object> defaults = stepByKey(steps, 'funddefaults');
        System.assertEquals(3, defaults.get('position'));
        System.assertEquals(Label.Giving_SetupAssistant_FundAppealStepLabel, defaults.get('label'));
        System.assertEquals(true, defaults.get('advanceOnSave'));
    }

    @IsTest
    static void asksForTheReceiptFieldsOnTheOrganizationStep() {
        Test.startTest();
        Map<String, Object> identity = stepByKey(
            asList(SetupAssistantService.getSteps()),
            'identity'
        );
        Test.stopTest();

        System.assertEquals(
            new List<String>{
                'Organization_Legal_Name__c',
                'Organization_EIN__c',
                'Organization_Address__c',
                'Receipt_Signer_Name__c',
                'Receipt_Signer_Title__c',
                'Receipt_Logo_Document_Id__c',
                'Receipt_Signature_Document_Id__c'
            },
            fieldKeys(identity),
            'The seven fields, in the order the step always showed them'
        );
        System.assertEquals(
            Label.Giving_SetupAssistant_IdentityDescription,
            identity.get('description'),
            'With Giving the step says what a receipt needs'
        );
    }

    @IsTest
    static void endsWithTheFirstGiftButton() {
        Test.startTest();
        Map<String, Object> verify = stepByKey(asList(SetupAssistantService.getSteps()), 'verify');
        Test.stopTest();

        Map<String, Object> button = (Map<String, Object>) ((List<Object>) verify.get('fields'))[0];
        System.assertEquals(SetupAssistantService.FIELD_NAVIGATE, button.get('fieldType'));
        System.assertEquals('Gift_Entry', button.get('navigationTarget'));
    }

    /**
     * Core saves a step's fields through `SettingsService`, which refuses a key with no Setting
     * Definition row, so every key Giving declares has to have one on the object it names.
     */
    @IsTest
    static void declaresOnlyKeysTheSettingsConsoleKnows() {
        Integer checked = 0;
        Test.startTest();
        for (
            SetupAssistantService.Step step : new GivingSetupAssistantExtension().contributions()
        ) {
            for (
                Object field : (List<Object>) ((Map<String, Object>) JSON.deserializeUntyped(
                        JSON.serialize(step)
                    ))
                    .get('fields')
            ) {
                Map<String, Object> declared = (Map<String, Object>) field;
                String key = (String) declared.get('key');
                if (String.isBlank(key)) {
                    continue;
                }
                // Throws when the key has no row, which fails the test with the key's name.
                SettingsService.getValue((String) declared.get('settingsObject'), key);
                checked++;
            }
        }
        Test.stopTest();

        System.assertEquals(7, checked, 'Two defaults and five receipt fields');
    }
}
