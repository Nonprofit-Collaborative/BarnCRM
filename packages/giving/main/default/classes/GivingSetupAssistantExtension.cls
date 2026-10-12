/**
 * The class Core finds by name (in `SetupAssistantExtensions.EXTENSION_CLASSES`) to add
 * Giving's part of the Setup Assistant (C-29, ADR-0059): the fund and appeal step, the receipt
 * fields and wording of the identity step, and the first gift check on the last step. With
 * these the assistant reads exactly as it did before Core was made neutral.
 *
 * `@NamespaceAccessible`, public and with a public no-argument constructor, because Core
 * resolves it with `Type.forName` under ADR-0017. Each field names the settings object its
 * key is on, and the assistant saves it there through `SettingsService`.
 */
@NamespaceAccessible
public with sharing class GivingSetupAssistantExtension implements SetupAssistantExtension {
    /** Giving's settings object, which holds the defaults and the receipt identity (ADR-0059). */
    private static final String DEFAULTS_OBJECT = 'Giving_Settings__c';
    private static final String IDENTITY_OBJECT = DEFAULTS_OBJECT;

    /**
     * A tax identification number in the United States: two digits, a hyphen, seven digits.
     * Left blank elsewhere, which the help text says.
     */
    private static final String EIN_PATTERN = '[0-9]{2}-[0-9]{7}';

    /** The Giving tab the first gift check opens (ADR-0020: reached by navigation). */
    private static final String GIFT_ENTRY_TAB = 'Gift_Entry';

    public List<SetupAssistantService.Step> contributions() {
        return new List<SetupAssistantService.Step>{ fundAndAppeal(), identity(), verify() };
    }

    /** Step three: the fund and appeal a gift falls back to (R-F4). */
    private static SetupAssistantService.Step fundAndAppeal() {
        return new SetupAssistantService.Step(
                'funddefaults',
                30,
                Label.Giving_SetupAssistant_FundAppealStepLabel,
                Label.Giving_SetupAssistant_FundAppealStepDescription
            )
            .withTarget(SettingSections.GIVING)
            .completedBy(DEFAULTS_OBJECT, 'Default_Fund__c')
            .advancingOnSave()
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_RECORD,
                        10,
                        DEFAULTS_OBJECT,
                        'Default_Fund__c',
                        Label.Giving_SetupAssistant_FundLabel
                    )
                    .withObject(
                        Fund__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                    )
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_RECORD,
                        20,
                        DEFAULTS_OBJECT,
                        'Default_Appeal__c',
                        Label.Giving_SetupAssistant_AppealLabel
                    )
                    .withObject(
                        Appeal__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName()
                    )
            );
    }

    /** Step five: what a receipt prints beside the legal name and address Core asks for. */
    private static SetupAssistantService.Step identity() {
        return new SetupAssistantService.Step(
                'identity',
                null,
                null,
                Label.Giving_SetupAssistant_IdentityDescription
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_TEXT,
                        20,
                        IDENTITY_OBJECT,
                        'Organization_EIN__c',
                        Label.Giving_SetupAssistant_EinLabel
                    )
                    .withLimits(20, EIN_PATTERN, Label.Giving_SetupAssistant_EinPatternMessage)
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_TEXT,
                        40,
                        IDENTITY_OBJECT,
                        'Receipt_Signer_Name__c',
                        Label.Giving_SetupAssistant_SignerNameLabel
                    )
                    .withLimits(80, null, null)
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_TEXT,
                        50,
                        IDENTITY_OBJECT,
                        'Receipt_Signer_Title__c',
                        Label.Giving_SetupAssistant_SignerTitleLabel
                    )
                    .withLimits(80, null, null)
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_FILE,
                        60,
                        IDENTITY_OBJECT,
                        'Receipt_Logo_Document_Id__c',
                        Label.Giving_SetupAssistant_LogoLabel
                    )
                    .withPreviewAlt(Label.Giving_SetupAssistant_LogoPreviewAlt)
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_FILE,
                        70,
                        IDENTITY_OBJECT,
                        'Receipt_Signature_Document_Id__c',
                        Label.Giving_SetupAssistant_SignatureLabel
                    )
                    .withPreviewAlt(Label.Giving_SetupAssistant_SignaturePreviewAlt)
            );
    }

    /** Step eight: enter one gift, which proves the chain from donor to household to gift. */
    private static SetupAssistantService.Step verify() {
        return new SetupAssistantService.Step(
                'verify',
                null,
                null,
                Label.Giving_SetupAssistant_VerifyDescription
            )
            .withField(
                new SetupAssistantService.StepField(
                        SetupAssistantService.FIELD_NAVIGATE,
                        10,
                        null,
                        null,
                        Label.Giving_SetupAssistant_EnterFirstGiftButton
                    )
                    .withNavigationTarget(GIFT_ENTRY_TAB)
            );
    }
}
