/**
 * What the Stewardship Plans page in the settings console calls (feature G-15).
 *
 * The page exists because of the rule that every administrator setting is reachable in the app: a
 * plan template, its steps and the order they come in are settings, and managing them on raw
 * object tabs left Maria in the object manager working out which tab held which half of one idea.
 * Everything a template carries is edited here.
 *
 * Reads and writes both run as the person on the page (`USER_MODE`), unlike the plan starter, which
 * ADR-0021 puts in system mode. The difference is who is acting: a plan is started as a consequence
 * of a gift somebody entered, while a template is a record an administrator chose to change, so her
 * own permissions are exactly the right answer.
 *
 * Editing a template never touches a plan already running (R-SP7). The page says so where it is
 * read, and `runningPlans` on each template is the number that edit will not reach.
 */
public with sharing class StewardshipPlanController {
    private static final String EDIT_PERMISSION = 'Manage_Nonprofit_Settings';
    private static final String CONTEXT = 'Stewardship plans page';
    private static final String PLAN_KEY_FALLBACK = 'plan';

    /** The key field holds 80 characters; this leaves room for a number suffix. */
    private static final Integer PLAN_KEY_BASE_LENGTH = 70;

    public class PageModel {
        @AuraEnabled
        public Boolean canEdit;
        @AuraEnabled
        public List<TemplateModel> templates;
        @AuraEnabled
        public List<Option> triggerEvents;
        @AuraEnabled
        public List<Option> assignTo;
        @AuraEnabled
        public List<Option> priorities;
        @AuraEnabled
        public List<Option> assignableUsers;
    }

    public class TemplateModel {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String planKey;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public String triggerEvent;
        @AuraEnabled
        public Decimal minimumAmount;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Integer runningPlans;
        @AuraEnabled
        public List<StepModel> steps;
    }

    public class StepModel {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public Decimal order;
        @AuraEnabled
        public String subject;
        @AuraEnabled
        public Decimal daysAfterStart;
        @AuraEnabled
        public String assignTo;
        @AuraEnabled
        public Id assignedUserId;
        @AuraEnabled
        public String assignedUserName;
        @AuraEnabled
        public String priority;
        @AuraEnabled
        public String comments;
    }

    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /** Every plan, its steps in order, and how many copies of each are running now. */
    @AuraEnabled(cacheable=true)
    public static PageModel getPage() {
        try {
            PageModel model = new PageModel();
            model.canEdit = FeatureManagement.checkPermission(EDIT_PERMISSION);
            model.triggerEvents = optionsFor(
                Stewardship_Plan_Template__c.Trigger_Event__c.getDescribe()
            );
            model.assignTo = optionsFor(Stewardship_Plan_Step__c.Assign_To__c.getDescribe());
            model.priorities = optionsFor(Stewardship_Plan_Step__c.Priority__c.getDescribe());
            model.assignableUsers = new List<Option>();
            for (User person : StewardshipSelector.selectAssignableUsers()) {
                Option option = new Option();
                option.label = person.Name;
                option.value = person.Id;
                model.assignableUsers.add(option);
            }
            Map<Id, Integer> running = StewardshipSelector.countRunningPlansByTemplate();
            model.templates = new List<TemplateModel>();
            for (
                Stewardship_Plan_Template__c template : StewardshipSelector.selectTemplatesForPage()
            ) {
                model.templates.add(toModel(template, running));
            }
            return model;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * Creates a plan or saves an edit to one, and returns its id so the page can select it.
     *
     * A validation rule that refuses the save is passed back in its own words rather than replaced
     * with a general apology: the rules on this object say something an administrator can act on,
     * for example that a minimum amount means nothing on a manual plan.
     *
     * The plan key is not asked for (ADR-NEXT,
     * `NEXT-acknowledgment-rule-template-picker-and-generated-plan-keys.md`): a new plan gets one
     * made from its name, and an edit never changes it, because the key is what keeps a plan
     * recognizable after it is renamed. A caller that does pass a key for a new plan keeps it.
     */
    @AuraEnabled
    public static Id saveTemplate(TemplateModel template) {
        requireEdit();
        if (template == null || String.isBlank(template.name)) {
            throw refuse(Label.Giving_Stewardship_ErrorNameRequired);
        }
        Stewardship_Plan_Template__c record = new Stewardship_Plan_Template__c(
            Id = template.recordId,
            Name = template.name.trim(),
            Trigger_Event__c = template.triggerEvent,
            Minimum_Amount__c = template.minimumAmount,
            Description__c = template.description,
            Active__c = template.active == true
        );
        if (template.recordId == null) {
            record.Plan_Key__c = String.isNotBlank(template.planKey)
                ? template.planKey.trim()
                : uniquePlanKeyFor(record.Name);
        }
        save(record);
        return record.Id;
    }

    /**
     * Turns a plan on or off, which is the one edit an administrator makes most often and the one
     * that must not require opening the record. Turning a plan off stops new plans and leaves the
     * running ones exactly as they are (R-SP2).
     */
    @AuraEnabled
    public static void setActive(Id templateId, Boolean active) {
        requireEdit();
        if (templateId == null) {
            throw refuse(Label.Giving_Stewardship_ErrorActionFailed);
        }
        save(new Stewardship_Plan_Template__c(Id = templateId, Active__c = active == true));
    }

    /** Adds a step to a plan, or saves an edit to one. */
    @AuraEnabled
    public static Id saveStep(Id templateId, StepModel step) {
        requireEdit();
        if (step == null || String.isBlank(step.subject)) {
            throw refuse(Label.Giving_Stewardship_ErrorSubjectRequired);
        }
        if (step.recordId == null && templateId == null) {
            throw refuse(Label.Giving_Stewardship_ErrorActionFailed);
        }
        Stewardship_Plan_Step__c record = new Stewardship_Plan_Step__c(
            Id = step.recordId,
            Subject__c = step.subject.trim(),
            Days_After_Start__c = step.daysAfterStart == null ? 0 : step.daysAfterStart,
            Assign_To__c = step.assignTo,
            Assigned_User__c = step.assignedUserId,
            Priority__c = step.priority,
            Comments__c = step.comments
        );
        if (step.recordId == null) {
            record.Stewardship_Plan_Template__c = templateId;
            record.Order__c = step.order == null ? nextOrder(templateId) : step.order;
        } else if (step.order != null) {
            record.Order__c = step.order;
        }
        save(record);
        return record.Id;
    }

    /**
     * Removes a step from a plan. Only the recipe changes: the tasks a plan already laid out from
     * this step are somebody's work and are never deleted by the package (R-SP8).
     */
    @AuraEnabled
    public static void deleteStep(Id stepId) {
        requireEdit();
        if (stepId == null) {
            throw refuse(Label.Giving_Stewardship_ErrorActionFailed);
        }
        try {
            Database.delete(new Stewardship_Plan_Step__c(Id = stepId), true, AccessLevel.USER_MODE);
        } catch (DmlException refused) {
            throw refuse(readable(refused));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * Writes the order the administrator dragged the steps into, as one update whatever the number
     * of steps. Ids that do not belong to this plan are ignored rather than trusted, because the
     * order comes from the page.
     */
    @AuraEnabled
    public static void reorderSteps(Id templateId, List<Id> stepIds) {
        requireEdit();
        if (templateId == null || stepIds == null || stepIds.isEmpty()) {
            throw refuse(Label.Giving_Stewardship_ErrorActionFailed);
        }
        Set<Id> owned = new Map<Id, Stewardship_Plan_Step__c>(
                StewardshipSelector.selectStepsFor(templateId)
            )
            .keySet();
        List<Stewardship_Plan_Step__c> reordered = new List<Stewardship_Plan_Step__c>();
        Integer position = 1;
        for (Id stepId : stepIds) {
            if (stepId == null || !owned.contains(stepId)) {
                continue;
            }
            reordered.add(new Stewardship_Plan_Step__c(Id = stepId, Order__c = position));
            position++;
        }
        if (reordered.isEmpty()) {
            return;
        }
        try {
            Database.update(reordered, true, AccessLevel.USER_MODE);
        } catch (DmlException refused) {
            throw refuse(readable(refused));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * A key made from the plan's name: lower case, words joined by underscores, at most
     * `PLAN_KEY_BASE_LENGTH` characters, and a number added when another plan already has it, so
     * "First gift welcome" becomes `first_gift_welcome`, then `first_gift_welcome_2`. A name
     * with no letters or digits in it (one written entirely in another script, say) falls back
     * to `plan`. The key field is unique and not case sensitive, so the comparison is too.
     */
    @TestVisible
    private static String uniquePlanKeyFor(String name) {
        String base = name.toLowerCase().replaceAll('[^a-z0-9]+', '_').replaceAll('^_+|_+$', '');
        if (String.isBlank(base)) {
            base = PLAN_KEY_FALLBACK;
        }
        base = base.left(PLAN_KEY_BASE_LENGTH).removeEnd('_');
        Set<String> taken = StewardshipSelector.selectPlanKeysStartingWith(base);
        String candidate = base;
        Integer suffix = 2;
        while (taken.contains(candidate)) {
            candidate = base + '_' + suffix;
            suffix++;
        }
        return candidate;
    }

    /** Where a new step goes when the administrator did not say: at the end. */
    private static Decimal nextOrder(Id templateId) {
        Decimal highest = 0;
        for (Stewardship_Plan_Step__c step : StewardshipSelector.selectStepsFor(templateId)) {
            if (step.Order__c != null && step.Order__c > highest) {
                highest = step.Order__c;
            }
        }
        return highest + 1;
    }

    private static void save(SObject record) {
        try {
            Database.upsert(record, true, AccessLevel.USER_MODE);
        } catch (DmlException refused) {
            throw refuse(readable(refused));
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    private static TemplateModel toModel(
        Stewardship_Plan_Template__c template,
        Map<Id, Integer> running
    ) {
        TemplateModel model = new TemplateModel();
        model.recordId = template.Id;
        model.name = template.Name;
        model.planKey = template.Plan_Key__c;
        model.active = template.Active__c;
        model.triggerEvent = template.Trigger_Event__c;
        model.minimumAmount = template.Minimum_Amount__c;
        model.description = template.Description__c;
        model.runningPlans = running.containsKey(template.Id) ? running.get(template.Id) : 0;
        model.steps = new List<StepModel>();
        if (template.Steps__r != null) {
            for (Stewardship_Plan_Step__c step : template.Steps__r) {
                model.steps.add(toModel(step));
            }
        }
        return model;
    }

    private static StepModel toModel(Stewardship_Plan_Step__c step) {
        StepModel model = new StepModel();
        model.recordId = step.Id;
        model.order = step.Order__c;
        model.subject = step.Subject__c;
        model.daysAfterStart = step.Days_After_Start__c;
        model.assignTo = step.Assign_To__c;
        model.assignedUserId = step.Assigned_User__c;
        model.assignedUserName = step.Assigned_User__r == null ? null : step.Assigned_User__r.Name;
        model.priority = step.Priority__c;
        model.comments = step.Comments__c;
        return model;
    }

    /** A picklist offered in the words of the field itself, so a translation is not a second list. */
    private static List<Option> optionsFor(Schema.DescribeFieldResult field) {
        List<Option> options = new List<Option>();
        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            Option option = new Option();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    private static void requireEdit() {
        if (!FeatureManagement.checkPermission(EDIT_PERMISSION)) {
            throw refuse(Label.Giving_Stewardship_ErrorNotPermitted);
        }
    }

    /** What the platform refused, in the words the rule was written in. */
    private static String readable(DmlException refused) {
        return refused.getNumDml() > 0 ? refused.getDmlMessage(0) : refused.getMessage();
    }

    private static AuraHandledException refuse(String message) {
        AuraHandledException refusal = new AuraHandledException(message);
        refusal.setMessage(message);
        return refusal;
    }

    private static AuraHandledException report(Exception failure) {
        ErrorLogger.log(failure, CONTEXT);
        return refuse(Label.Giving_Stewardship_ErrorActionFailed);
    }
}
