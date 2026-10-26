/**
 * What the Start Stewardship Plan action on a person, household or organization calls: the plans
 * that can be started, and starting one (canonical model R-SP9).
 *
 * Reading the plans runs as the person. Starting one goes through `StewardshipService.start`,
 * which lays the plan and its tasks out in system mode like every other start (ADR-0021), so this
 * class first checks that the person may create a stewardship plan at all: a reader is told so
 * instead of starting one.
 */
public with sharing class StewardshipStartController {
    private static final String CONTEXT = 'Start stewardship plan';

    /** What the action shows: whether the person may start a plan, and the plans to choose from. */
    public class StartModel {
        @AuraEnabled
        public Boolean canStart;
        @AuraEnabled
        public List<PlanOption> plans;
    }

    /** One plan in the list, with the description an administrator wrote for whoever picks it. */
    public class PlanOption {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String description;
    }

    @AuraEnabled(cacheable=true)
    public static StartModel getStartable() {
        try {
            StartModel model = new StartModel();
            model.canStart = canStart();
            model.plans = new List<PlanOption>();
            for (
                Stewardship_Plan_Template__c template : StewardshipSelector.selectManualTemplates()
            ) {
                PlanOption option = new PlanOption();
                option.label = template.Name;
                option.value = template.Id;
                option.description = template.Description__c;
                model.plans.add(option);
            }
            return model;
        } catch (Exception failure) {
            // Cacheable: no Error Log insert is allowed here, so the screen gets the sentence.
            throw refuse(Label.Giving_Stewardship_StartLoadFailed);
        }
    }

    /**
     * Starts one plan on the donor whose page the action was opened from, and returns the plan.
     * A person is the plan's Contact; a household or organization is its Account.
     */
    @AuraEnabled
    public static Id startPlan(Id templateId, Id donorId) {
        if (!canStart()) {
            throw refuse(Label.Giving_Stewardship_StartNoPermission);
        }
        if (donorId == null) {
            throw refuse(Label.Giving_Stewardship_ErrorOneDonor);
        }
        Boolean isPerson = donorId.getSObjectType() == Contact.SObjectType;
        try {
            return StewardshipService.start(
                    templateId,
                    isPerson ? donorId : null,
                    isPerson ? null : donorId
                )
                .Id;
        } catch (StewardshipService.StewardshipException refused) {
            throw refuse(refused.getMessage());
        } catch (Exception failure) {
            ErrorLogger.log(failure, CONTEXT, donorId);
            throw refuse(Label.Giving_Stewardship_ErrorActionFailed);
        }
    }

    private static Boolean canStart() {
        return Schema.SObjectType.Stewardship_Plan__c.isCreateable();
    }

    private static AuraHandledException refuse(String message) {
        AuraHandledException refusal = new AuraHandledException(message);
        refusal.setMessage(message);
        return refusal;
    }
}
