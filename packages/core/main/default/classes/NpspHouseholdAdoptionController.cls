/**
 * The Adopt NPSP Households panel's server side (X-05, admin guide npsp-households.md): thin
 * over `NpspHouseholdAdoptionService`, which checks Manage BarnCRM Settings on every call and
 * answers plain JSON shapes (plan 9.9). A refusal the service words is shown as it is; anything
 * else is logged and shown as the unexpected-error label.
 */
public with sharing class NpspHouseholdAdoptionController {
    @AuraEnabled
    public static NpspHouseholdAdoptionService.Status getStatus() {
        try {
            return NpspHouseholdAdoptionService.getStatus();
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UserErrors.wrap(e, Label.Core_NpspAdoption_ErrorContext, true);
        }
    }

    @AuraEnabled
    public static String adopt(Boolean keepNames, Integer confirmedCount) {
        try {
            return NpspHouseholdAdoptionService.start(keepNames, confirmedCount);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UserErrors.wrap(e, Label.Core_NpspAdoption_ErrorContext, true);
        }
    }

    @AuraEnabled
    public static void undo(String runId, Integer confirmedCount) {
        try {
            NpspHouseholdAdoptionService.undo(runId, confirmedCount);
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw UserErrors.wrap(e, Label.Core_NpspAdoption_ErrorContext, true);
        }
    }
}
