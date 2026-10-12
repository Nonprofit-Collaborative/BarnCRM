/**
 * The setup checklist Maria works through on the home page (plan Section 4.8). It defines the
 * steps, says how each one finishes, and remembers where Maria got to, so that closing the
 * browser in the middle of step four opens on step four tomorrow.
 *
 * Core ships seven neutral steps. A dependent package adds its own steps, fields and wording
 * through `SetupAssistantExtension` (C-29, ADR-0059): Giving adds the fund and appeal step and
 * the receipt fields, which makes eight. A step's fields are data, rendered by one Core panel
 * and saved through `SettingsService` on the settings object each field names.
 *
 * A step is finished when the administrator finishes it, or when the setting that step
 * exists to fill in already has a value. A step can also be skipped, which moves it out of
 * the way without counting as done.
 */
@NamespaceAccessible
public with sharing class SetupAssistantService {
    /** Where a step is carried out: a section of the settings console, or Salesforce Setup. */
    public static final String TARGET_SETTINGS = 'Settings';
    public static final String TARGET_SETUP = 'Setup';

    /** How a step finishes: by a setting getting a value, or by Maria finishing the panel. */
    @NamespaceAccessible
    public static final String RULE_SETTING = 'Setting';
    @NamespaceAccessible
    public static final String RULE_ACTION = 'Action';

    /** The kinds of field a step's panel can show (see `StepField`). */
    @NamespaceAccessible
    public static final String FIELD_TEXT = 'Text';
    @NamespaceAccessible
    public static final String FIELD_RECORD = 'Record';
    @NamespaceAccessible
    public static final String FIELD_FILE = 'File';
    @NamespaceAccessible
    public static final String FIELD_NAVIGATE = 'Navigate';

    /** The coexistence modes, as plan Section 4.5 names them. */
    public static final String MODE_STANDALONE = 'Standalone';
    public static final String MODE_NPSP = 'NPSP';
    public static final String MODE_AGENTFORCE = 'AgentforceNonprofit';

    /** What detection found, in the order the assistant leads with. */
    public static final String SHAPE_PERSON_ACCOUNTS = 'PersonAccounts';
    public static final String SHAPE_NPSP = 'Npsp';
    public static final String SHAPE_FRESH = 'Fresh';

    private static final String PROGRESS_KEY = 'Setup_Steps_Completed__c';
    private static final String SKIPPED_KEY = 'Setup_Steps_Skipped__c';
    private static final String STARTED_KEY = 'Setup_Started_At__c';
    private static final Integer PROGRESS_LENGTH = 255;

    /** The org shape used instead of detection, so that tests can run the Person Accounts path. */
    @TestVisible
    private static OrgShapeDetector.OrgShape stubbedShape;

    /** The merged steps, built once per transaction. */
    private static List<Step> cachedDefinitions;

    /** Raised when a step key is not one of the steps this org has. */
    public class SetupStepException extends Exception {
    }

    /**
     * One step of the setup checklist, as the home page renders it. A dependent package builds
     * one with the constructor and the `with` methods, because an `@AuraEnabled` field cannot
     * also be `@NamespaceAccessible` (dynamic-apex.md section 3).
     */
    @NamespaceAccessible
    public class Step {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Integer position;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String targetType;
        @AuraEnabled
        public String target;
        @AuraEnabled
        public String setupPath;
        @AuraEnabled
        public String completionSettingKey;
        /** The settings object the completion key is on; blank means Core's. */
        @AuraEnabled
        public String completionSettingsObject;
        @AuraEnabled
        public String completionRule;
        @AuraEnabled
        public Boolean isAvailable;
        @AuraEnabled
        public Boolean skipped;
        /** True when the step is finished. The Hub checklist has called this `completed` since C-03. */
        @AuraEnabled
        public Boolean completed;
        /** The fields the step's panel shows, in order; empty for a step with its own panel. */
        @AuraEnabled
        public List<StepField> fields;
        /** True when saving the panel's fields also moves on to the next step. */
        @AuraEnabled
        public Boolean advanceOnSave;
        /** Where the step sits: Core's steps are 10 to 80 in tens, a module fills the gaps. */
        public Integer sortOrder;

        /** A step, or a contribution to a Core step when the key is one of Core's. */
        @NamespaceAccessible
        public Step(String key, Integer sortOrder, String label, String description) {
            this.key = key;
            this.sortOrder = sortOrder;
            this.label = label;
            this.description = description;
            this.targetType = TARGET_SETTINGS;
            this.completionRule = RULE_ACTION;
            this.isAvailable = true;
            this.skipped = false;
            this.completed = false;
            this.advanceOnSave = false;
            this.fields = new List<StepField>();
        }

        /** The settings section the step's answers live in afterwards. */
        @NamespaceAccessible
        public Step withTarget(String target) {
            this.target = target;
            return this;
        }

        /** The step finishes by itself once this setting has a value. */
        @NamespaceAccessible
        public Step completedBy(String settingsObject, String settingKey) {
            this.completionRule = RULE_SETTING;
            this.completionSettingsObject = settingsObject;
            this.completionSettingKey = settingKey;
            return this;
        }

        @NamespaceAccessible
        public Step withField(StepField field) {
            this.fields.add(field);
            return this;
        }

        /** Saving the step's fields moves on to the next step. */
        @NamespaceAccessible
        public Step advancingOnSave() {
            this.advanceOnSave = true;
            return this;
        }
    }

    /**
     * One field on a step's panel: a setting to type, a record to pick, a file to upload, or a
     * button that opens another tab. The page renders it and the assistant saves only the keys
     * a step declares, so a panel can never write a setting its step does not name.
     */
    @NamespaceAccessible
    public class StepField {
        @AuraEnabled
        public String fieldType;
        /** The settings field the value is saved to; blank for a Navigate button. */
        @AuraEnabled
        public String key;
        /** The settings object the key is on; blank means Core's. */
        @AuraEnabled
        public String settingsObject;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        /** For a Record field, the object the picker offers, as its API name. */
        @AuraEnabled
        public String objectApiName;
        @AuraEnabled
        public Integer maxLength;
        @AuraEnabled
        public String pattern;
        @AuraEnabled
        public String patternMessage;
        /** For a File field, the alternative text of the preview. */
        @AuraEnabled
        public String previewAlt;
        /** For a Navigate field, the Lightning tab it opens. */
        @AuraEnabled
        public String navigationTarget;
        @AuraEnabled
        public Boolean fullWidth;
        public Integer sortOrder;

        @NamespaceAccessible
        public StepField(
            String fieldType,
            Integer sortOrder,
            String settingsObject,
            String key,
            String label
        ) {
            this.fieldType = fieldType;
            this.sortOrder = sortOrder;
            this.settingsObject = settingsObject;
            this.key = key;
            this.label = label;
            this.fullWidth = false;
        }

        @NamespaceAccessible
        public StepField withLimits(Integer maxLength, String pattern, String patternMessage) {
            this.maxLength = maxLength;
            this.pattern = pattern;
            this.patternMessage = patternMessage;
            return this;
        }

        @NamespaceAccessible
        public StepField withObject(String objectApiName) {
            this.objectApiName = objectApiName;
            return this;
        }

        @NamespaceAccessible
        public StepField withPreviewAlt(String previewAlt) {
            this.previewAlt = previewAlt;
            return this;
        }

        @NamespaceAccessible
        public StepField withNavigationTarget(String navigationTarget) {
            this.navigationTarget = navigationTarget;
            return this;
        }

        @NamespaceAccessible
        public StepField asFullWidth() {
            this.fullWidth = true;
            return this;
        }
    }

    /** The steps, in order, each carrying whether it is finished or skipped, and its fields' values. */
    @NamespaceAccessible
    public static List<Step> getSteps() {
        Set<String> marked = keysIn(PROGRESS_KEY);
        Set<String> skipped = keysIn(SKIPPED_KEY);
        List<Step> steps = definitions();
        for (Step step : steps) {
            step.completed =
                marked.contains(step.key) ||
                hasValue(step.completionSettingsObject, step.completionSettingKey);
            step.skipped = skipped.contains(step.key) && !step.completed;
            for (StepField field : step.fields) {
                field.value = String.isBlank(field.key)
                    ? null
                    : valueOf(field.settingsObject, field.key);
            }
        }
        return steps;
    }

    /** The step with this key, or null when this org has no such step. */
    @NamespaceAccessible
    public static Step findStep(String stepKey) {
        String key = stepKey == null ? '' : stepKey.trim();
        for (Step step : definitions()) {
            if (step.key == key) {
                return step;
            }
        }
        return null;
    }

    /** How many of the steps are finished. */
    public static Integer countCompleted(List<Step> steps) {
        Integer done = 0;
        for (Step step : steps) {
            if (step.completed == true) {
                done++;
            }
        }
        return done;
    }

    public static List<Step> markComplete(String stepKey) {
        ensureStarted();
        return setMembership(PROGRESS_KEY, stepKey, true);
    }

    /** Moves a step out of the way without counting it done, so the assistant offers it again. */
    public static List<Step> markSkipped(String stepKey) {
        ensureStarted();
        return setMembership(SKIPPED_KEY, stepKey, true);
    }

    /**
     * Forgets the progress the administrator recorded, so setup can be run again from the
     * first step. A step whose setting already has a value stays finished, because it really
     * is: re-running setup revisits decisions, it does not empty the org's settings.
     */
    public static List<Step> reset() {
        SettingsService.saveSystemValue(PROGRESS_KEY, '');
        SettingsService.saveSystemValue(SKIPPED_KEY, '');
        SettingsService.saveSystemValue(STARTED_KEY, null);
        return getSteps();
    }

    /** Records when Maria first changed something, so the completion screen can say how long setup took. */
    public static void ensureStarted() {
        if (getStartedAt() == null) {
            SettingsService.saveSystemValue(STARTED_KEY, System.now());
        }
    }

    /** When setup was first touched, or null when nothing has been done yet. */
    public static Datetime getStartedAt() {
        if (!SettingsService.hasKey(STARTED_KEY)) {
            return null;
        }
        Object value = SettingsService.getValue(STARTED_KEY);
        return value instanceof Datetime ? (Datetime) value : null;
    }

    /** How many whole minutes setup has taken so far, or null when it has not started. */
    public static Integer elapsedMinutes() {
        Datetime startedAt = getStartedAt();
        if (startedAt == null) {
            return null;
        }
        Long milliseconds = System.now().getTime() - startedAt.getTime();
        return milliseconds < 0 ? 0 : (Integer) (milliseconds / 60000);
    }

    /** What detection found in this org, as one of the shape constants. */
    public static String detectedShape() {
        OrgShapeDetector.OrgShape shape = orgShape();
        if (shape == null) {
            return SHAPE_FRESH;
        }
        if (shape.hasPersonAccounts == true || shape.hasIndustriesNonprofit == true) {
            return SHAPE_PERSON_ACCOUNTS;
        }
        return shape.hasNpsp == true ? SHAPE_NPSP : SHAPE_FRESH;
    }

    /** The coexistence mode the assistant recommends for what detection found (plan Section 4.5). */
    public static String recommendedMode() {
        String shape = detectedShape();
        if (shape == SHAPE_PERSON_ACCOUNTS) {
            return MODE_AGENTFORCE;
        }
        return shape == SHAPE_NPSP ? MODE_NPSP : MODE_STANDALONE;
    }

    /** The three modes, so the page can offer a different one than the recommendation. */
    public static List<String> modes() {
        return new List<String>{ MODE_STANDALONE, MODE_NPSP, MODE_AGENTFORCE };
    }

    private static OrgShapeDetector.OrgShape orgShape() {
        if (stubbedShape != null) {
            return stubbedShape;
        }
        try {
            return OrgShapeDetector.detect();
        } catch (Exception e) {
            ErrorLogger.log(e, 'Setup Assistant org shape');
            return null;
        }
    }

    private static List<Step> setMembership(String settingKey, String stepKey, Boolean member) {
        String key = stepKey == null ? '' : stepKey.trim();
        if (!keys().contains(key)) {
            throw new SetupStepException(System.Label.Core_SetupAssistant_UnknownStepError);
        }
        Set<String> current = keysIn(settingKey);
        if (member) {
            current.add(key);
        } else {
            current.remove(key);
        }
        List<String> ordered = new List<String>();
        for (Step step : definitions()) {
            if (current.contains(step.key)) {
                ordered.add(step.key);
            }
        }
        String joined = String.join(ordered, ',');
        if (joined.length() > PROGRESS_LENGTH) {
            joined = joined.substring(0, PROGRESS_LENGTH);
        }
        SettingsService.saveSystemValue(settingKey, joined);
        return getSteps();
    }

    private static Set<String> keysIn(String settingKey) {
        Set<String> stored = new Set<String>();
        if (!SettingsService.hasKey(settingKey)) {
            return stored;
        }
        String value = SettingsService.asText(SettingsService.getValue(settingKey));
        for (String part : value.split(',')) {
            String trimmed = part.trim();
            if (String.isNotBlank(trimmed)) {
                stored.add(trimmed);
            }
        }
        return stored;
    }

    private static Boolean hasValue(String settingsObject, String settingKey) {
        return String.isNotBlank(valueOf(settingsObject, settingKey));
    }

    /**
     * A setting's value as text, or null when it is blank or the key is not in this org. A
     * module's settings object that is missing is an absent answer, never a failed page.
     */
    private static String valueOf(String settingsObject, String settingKey) {
        if (String.isBlank(settingKey)) {
            return null;
        }
        try {
            String value = SettingsService.asText(
                String.isBlank(settingsObject)
                    ? SettingsService.getValue(settingKey)
                    : SettingsService.getValue(settingsObject, settingKey)
            );
            return String.isBlank(value) ? null : value;
        } catch (SettingsService.SettingsException unknown) {
            return null;
        }
    }

    private static Set<String> keys() {
        Set<String> keys = new Set<String>();
        for (Step step : definitions()) {
            keys.add(step.key);
        }
        return keys;
    }

    /**
     * Core's seven steps with every installed extension's contributions merged in, sorted and
     * numbered. Built once per transaction: the page asks for the steps several times a call.
     */
    private static List<Step> definitions() {
        if (cachedDefinitions != null) {
            return cachedDefinitions;
        }
        List<Step> steps = coreSteps();
        Map<String, Step> byKey = new Map<String, Step>();
        for (Step step : steps) {
            byKey.put(step.key, step);
        }
        for (SetupAssistantExtension extension : SetupAssistantExtensions.findAll()) {
            List<Step> contributed;
            try {
                contributed = extension.contributions();
            } catch (Exception e) {
                ErrorLogger.log(e, 'Setup Assistant extension');
                continue;
            }
            for (Step contribution : contributed == null ? new List<Step>() : contributed) {
                if (contribution == null || String.isBlank(contribution.key)) {
                    continue;
                }
                Step existing = byKey.get(contribution.key);
                if (existing == null) {
                    byKey.put(contribution.key, contribution);
                    steps.add(contribution);
                } else {
                    mergeInto(existing, contribution);
                }
            }
        }
        steps = sortedBySortOrder(steps);
        for (Integer i = 0; i < steps.size(); i++) {
            steps[i].position = i + 1;
            steps[i].fields = sortedFields(steps[i].fields);
        }
        cachedDefinitions = steps;
        return steps;
    }

    /** A contribution to a Core step adds its fields and, when it has any, its own wording. */
    private static void mergeInto(Step existing, Step contribution) {
        if (String.isNotBlank(contribution.label)) {
            existing.label = contribution.label;
        }
        if (String.isNotBlank(contribution.description)) {
            existing.description = contribution.description;
        }
        existing.fields.addAll(contribution.fields);
        existing.advanceOnSave = existing.advanceOnSave || contribution.advanceOnSave;
    }

    /** A stable insertion sort: a handful of steps, and equal orders keep their arrival order. */
    private static List<Step> sortedBySortOrder(List<Step> steps) {
        List<Step> sorted = new List<Step>();
        for (Step step : steps) {
            Integer at = sorted.size();
            while (at > 0 && orderOf(sorted[at - 1].sortOrder) > orderOf(step.sortOrder)) {
                at--;
            }
            if (at == sorted.size()) {
                sorted.add(step);
            } else {
                sorted.add(at, step);
            }
        }
        return sorted;
    }

    private static List<StepField> sortedFields(List<StepField> fields) {
        List<StepField> sorted = new List<StepField>();
        for (StepField field : fields) {
            Integer at = sorted.size();
            while (at > 0 && orderOf(sorted[at - 1].sortOrder) > orderOf(field.sortOrder)) {
                at--;
            }
            if (at == sorted.size()) {
                sorted.add(field);
            } else {
                sorted.add(at, field);
            }
        }
        return sorted;
    }

    private static Integer orderOf(Integer sortOrder) {
        return sortOrder == null ? 1000 : sortOrder;
    }

    /** The seven steps every organization answers, whatever else is installed. */
    private static List<Step> coreSteps() {
        List<Step> steps = new List<Step>();
        steps.add(
            new Step(
                    'coexistence',
                    10,
                    System.Label.Core_SetupAssistant_Step1Label,
                    System.Label.Core_SetupAssistant_Step1Description
                )
                .withTarget(SettingSections.GENERAL)
                .completedBy(null, 'Coexistence_Mode__c')
        );
        steps.add(
            new Step(
                    'naming',
                    20,
                    System.Label.Core_SetupAssistant_Step2Label,
                    System.Label.Core_SetupAssistant_Step2Description
                )
                .withTarget(SettingSections.HOUSEHOLDS)
                .completedBy(null, 'Household_Name_Pattern__c')
        );
        Step access = new Step(
                'access',
                40,
                System.Label.Core_SetupAssistant_Step4Label,
                System.Label.Core_SetupAssistant_Step4Description
            )
            .withTarget(SettingSections.ACCESS);
        access.setupPath = '/lightning/setup/ManageUsers/home';
        steps.add(access);
        steps.add(
            new Step(
                    'identity',
                    50,
                    System.Label.Core_SetupAssistant_Step5Label,
                    System.Label.Core_SetupAssistant_Step5Description
                )
                .withTarget(SettingSections.ORGANIZATION)
                .completedBy(null, 'Organization_Legal_Name__c')
                .withField(
                    new StepField(
                            FIELD_TEXT,
                            10,
                            null,
                            'Organization_Legal_Name__c',
                            System.Label.Core_SetupAssistant_LegalNameLabel
                        )
                        .withLimits(255, null, null)
                )
                .withField(
                    new StepField(
                            FIELD_TEXT,
                            30,
                            null,
                            'Organization_Address__c',
                            System.Label.Core_SetupAssistant_AddressLabel
                        )
                        .withLimits(255, null, null)
                        .asFullWidth()
                )
        );
        steps.add(
            new Step(
                    'modules',
                    60,
                    System.Label.Core_SetupAssistant_Step6Label,
                    System.Label.Core_SetupAssistant_Step6Description
                )
                .withTarget(SettingSections.GENERAL)
        );
        steps.add(
            new Step(
                    'data',
                    70,
                    System.Label.Core_SetupAssistant_Step7Label,
                    System.Label.Core_SetupAssistant_Step7Description
                )
                .withTarget(SettingSections.IMPORTING)
        );
        steps.add(
            new Step(
                    'verify',
                    80,
                    System.Label.Core_SetupAssistant_Step8Label,
                    System.Label.Core_SetupAssistant_Step8Description
                )
                .withTarget(SettingSections.HEALTH)
        );
        return steps;
    }
}
