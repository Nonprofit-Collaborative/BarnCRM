/**
 * The Adopt NPSP Households panel's server side (X-05, admin guide npsp-households.md), and the
 * same panel converting Nonprofit Cloud households (R-HA7, admin guide
 * nonprofit-cloud-households.md): thin over `NpspHouseholdAdoptionService`, which checks Manage
 * BarnCRM Settings on every call and answers plain JSON shapes (plan 9.9). `source` is NPSP or
 * NPC, NPSP when blank. A refusal the service words is shown as it is; anything else is logged
 * and shown as the unexpected-error label.
 */
public with sharing class NpspHouseholdAdoptionController {
	@AuraEnabled
	public static NpspHouseholdAdoptionService.Status getStatus(String source) {
		try {
			return NpspHouseholdAdoptionService.getStatus(source);
		} catch (AuraHandledException e) {
			throw e;
		} catch (Exception e) {
			throw UserErrors.wrap(e, Label.Core_NpspAdoption_ErrorContext, true);
		}
	}

	@AuraEnabled
	public static String adopt(String source, Boolean keepNames, Integer confirmedCount) {
		try {
			return NpspHouseholdAdoptionService.start(source, keepNames, confirmedCount);
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
