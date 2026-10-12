/**
 * The guided Setup Assistant's Apex surface: what the panels show, and what they save.
 * Everything a panel needs to render is in one call, so the assistant opens on the step Maria
 * stopped at without a chain of round trips. A step's fields, Core's or a module's, are saved
 * by one method that accepts only the keys that step declares (C-29, ADR-0059).
 *
 * Every method that changes something checks the `Manage_Nonprofit_Settings` custom
 * permission first, logs what went wrong, and returns a message Maria can act on.
 */
public with sharing class SetupAssistantController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String ERROR_CONTEXT = 'Setup Assistant';

    /** Everything the assistant needs to draw itself. */
    public class SetupState {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<SetupAssistantService.Step> steps;
        @AuraEnabled
        public Integer stepsCompleted;
        @AuraEnabled
        public Integer stepsTotal;
        @AuraEnabled
        public Boolean isComplete;
        @AuraEnabled
        public Integer elapsedMinutes;
        @AuraEnabled
        public CoexistenceModel coexistence;
        @AuraEnabled
        public List<ModuleDetectionService.ModuleInfo> modules;
        @AuraEnabled
        public List<AccessService.Role> roles;
        @AuraEnabled
        public Boolean importAvailable;
    }

    /** What step one shows: what was detected, what is recommended, what is in force. */
    public class CoexistenceModel {
        @AuraEnabled
        public String detectedShape;
        @AuraEnabled
        public String recommendedMode;
        @AuraEnabled
        public String currentMode;
        @AuraEnabled
        public List<String> modes;
    }

    @AuraEnabled
    public static SetupState getState() {
        try {
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState completeStep(String stepKey) {
        requireEdit();
        try {
            SetupAssistantService.markComplete(stepKey);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState skipStep(String stepKey) {
        requireEdit();
        try {
            SetupAssistantService.markSkipped(stepKey);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    @AuraEnabled
    public static SetupState reset() {
        requireEdit();
        try {
            SetupAssistantService.reset();
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_LoadErrorMessage);
        }
    }

    /** Step one: put the confirmed coexistence mode in force and record the step as done. */
    @AuraEnabled
    public static SetupState applyCoexistence(String mode) {
        requireEdit();
        String chosen = mode == null ? '' : mode.trim();
        if (!new Set<String>(SetupAssistantService.modes()).contains(chosen)) {
            throw asAuraException(System.Label.Core_SetupAssistant_UnknownModeError);
        }
        try {
            SetupAssistantService.ensureStarted();
            CoexistenceService.applyMode(chosen);
            SetupAssistantService.markComplete('coexistence');
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_SaveErrorMessage);
        }
    }

    /**
     * Saves the fields of one step, Core's or a module's. Only the keys the step declares are
     * accepted, each on the settings object its field names, and a record picker's value has
     * to be a record of the object the field offers, so a client cannot store a setting the
     * step does not name or a default that points at the wrong kind of record.
     */
    @AuraEnabled
    public static SetupState saveStepValues(String stepKey, Map<String, Object> values) {
        requireEdit();
        SetupAssistantService.Step step = SetupAssistantService.findStep(stepKey);
        if (step == null) {
            throw asAuraException(System.Label.Core_SetupAssistant_UnknownStepError);
        }
        Map<String, Map<String, Object>> byObject = acceptedValues(step, values);
        if (byObject.isEmpty()) {
            throw asAuraException(System.Label.Core_SetupAssistant_NothingToSaveError);
        }
        // A step can span two settings objects (Core's and a module's): all of it or none.
        Savepoint beforeSave = Database.setSavepoint();
        try {
            SetupAssistantService.ensureStarted();
            for (String settingsObject : byObject.keySet()) {
                SettingsService.saveValues(settingsObject, byObject.get(settingsObject));
            }
        } catch (Exception e) {
            Database.rollback(beforeSave);
            SettingsService.clearCaches();
            throw logged(e, System.Label.Core_SetupAssistant_SaveErrorMessage);
        }
        return buildState();
    }

    /** The submitted values the step declares, grouped by the settings object each belongs to. */
    private static Map<String, Map<String, Object>> acceptedValues(
        SetupAssistantService.Step step,
        Map<String, Object> values
    ) {
        Map<String, Map<String, Object>> byObject = new Map<String, Map<String, Object>>();
        if (values == null) {
            return byObject;
        }
        for (SetupAssistantService.StepField field : step.fields) {
            if (String.isBlank(field.key) || !values.containsKey(field.key)) {
                continue;
            }
            Object value = values.get(field.key);
            if (field.fieldType == SetupAssistantService.FIELD_RECORD) {
                value = requireType(value, field.objectApiName);
            } else if (field.fieldType == SetupAssistantService.FIELD_TEXT) {
                requireWithinLimits(value, field);
            }
            String settingsObject = String.isBlank(field.settingsObject)
                ? SettingsService.CORE_SETTINGS_OBJECT
                : field.settingsObject;
            if (!byObject.containsKey(settingsObject)) {
                byObject.put(settingsObject, new Map<String, Object>());
            }
            byObject.get(settingsObject).put(field.key, value);
        }
        return byObject;
    }

    /**
     * Step four: give one colleague one packaged role, without leaving the assistant.
     *
     * Only the role is written here. A role is a setup object record and the step's progress
     * is an ordinary one, and the platform refuses both in one transaction (mixed DML), so
     * the page records the step with completeStep once this has succeeded.
     */
    @AuraEnabled
    public static SetupState assignAccess(Id userId, String roleDeveloperName) {
        requireEdit();
        if (userId == null || String.isBlank(roleDeveloperName)) {
            throw asAuraException(System.Label.Core_SetupAssistant_NothingToSaveError);
        }
        try {
            AccessService.assignRole(userId, roleDeveloperName);
            return buildState();
        } catch (Exception e) {
            throw logged(e, System.Label.Core_SetupAssistant_AccessErrorMessage);
        }
    }

    private static SetupState buildState() {
        SetupState state = new SetupState();
        state.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
        state.steps = SetupAssistantService.getSteps();
        state.stepsTotal = state.steps.size();
        state.stepsCompleted = SetupAssistantService.countCompleted(state.steps);
        state.isComplete = state.stepsCompleted == state.stepsTotal;
        state.elapsedMinutes = SetupAssistantService.elapsedMinutes();
        state.coexistence = coexistence();
        state.modules = ModuleDetectionService.getModules();
        state.roles = roles();
        state.importAvailable = ModuleDetectionService.isImportPresent();
        return state;
    }

    private static CoexistenceModel coexistence() {
        CoexistenceModel model = new CoexistenceModel();
        model.detectedShape = SetupAssistantService.detectedShape();
        model.recommendedMode = SetupAssistantService.recommendedMode();
        model.modes = SetupAssistantService.modes();
        try {
            model.currentMode = CoexistenceService.getCurrentMode();
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            model.currentMode = null;
        }
        return model;
    }

    /**
     * The roles step four can give out. C-06 ships each role with a label and a plain
     * language description, so the assistant shows the label rather than a developer name
     * with its underscores taken out.
     */
    private static List<AccessService.Role> roles() {
        try {
            List<AccessService.Role> roles = AccessService.getRoles();
            return roles == null ? new List<AccessService.Role>() : roles;
        } catch (Exception e) {
            ErrorLogger.log(e, ERROR_CONTEXT);
            return new List<AccessService.Role>();
        }
    }

    /**
     * Refuses text longer than the field allows or not in the shape it asks for. The page checks
     * both as Maria types, but a save that follows an upload sends the whole step without the
     * page's own validation, so the server holds the same line. A blank value clears the setting.
     */
    private static void requireWithinLimits(Object value, SetupAssistantService.StepField field) {
        String text = value == null ? '' : String.valueOf(value);
        if (String.isBlank(text)) {
            return;
        }
        if (field.maxLength != null && text.length() > field.maxLength) {
            throw asAuraException(
                String.format(
                    System.Label.Core_SetupAssistant_TooLongError,
                    new List<Object>{ field.label, String.valueOf(field.maxLength) }
                )
            );
        }
        if (String.isNotBlank(field.pattern) && !Pattern.matches(field.pattern, text)) {
            throw asAuraException(
                String.isBlank(field.patternMessage)
                    ? System.Label.Core_SetupAssistant_InvalidValueError
                    : field.patternMessage
            );
        }
    }

    /**
     * Refuses a record identifier that does not point at the object the field is choosing
     * from. The expected object comes from the step's own field, so no module object is ever
     * named here, and a client that sends any other identifier is turned away rather than
     * storing a default the module would fail to read later. A blank value clears the setting.
     */
    private static String requireType(Object value, String expectedObject) {
        String text = value == null ? '' : String.valueOf(value).trim();
        if (String.isBlank(text)) {
            return null;
        }
        Id recordId;
        try {
            recordId = Id.valueOf(text);
        } catch (Exception notAnId) {
            throw asAuraException(System.Label.Core_SetupAssistant_WrongRecordTypeError);
        }
        String actual = recordId.getSObjectType()
            .getDescribe(SObjectDescribeOptions.DEFERRED)
            .getName();
        if (String.isBlank(expectedObject) || !expectedObject.equalsIgnoreCase(actual)) {
            throw asAuraException(System.Label.Core_SetupAssistant_WrongRecordTypeError);
        }
        return String.valueOf(recordId);
    }

    /** Logs what went wrong and gives the page one message Maria can act on. */
    private static AuraHandledException logged(Exception e, String fallback) {
        ErrorLogger.log(e, ERROR_CONTEXT);
        Boolean speaksForItself =
            e instanceof SetupAssistantService.SetupStepException ||
            e instanceof SettingsService.SettingsException;
        return asAuraException(speaksForItself ? e.getMessage() : fallback);
    }

    private static void requireEdit() {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw asAuraException(System.Label.Core_Settings_PermissionRequiredError);
        }
    }

    private static AuraHandledException asAuraException(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
