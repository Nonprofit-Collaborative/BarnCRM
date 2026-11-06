/**
 * What the Automation tab's inventory reads (C-60, D-184). Every method needs the Manage
 * BarnCRM Settings permission, and says so in words when it is missing.
 */
public with sharing class OrgAutomationController {
	public class OrgAutomationException extends Exception {
	}

	/** Every automation in the org, BarnCRM's and the org's own (OrgAutomationInventory). */
	@AuraEnabled
	public static OrgAutomationInventory.Result getInventory() {
		try {
			requirePermission();
			return OrgAutomationInventory.build();
		} catch (Exception caught) {
			throw asUserError(caught, 'Automation inventory');
		}
	}

	@TestVisible
	private static void requirePermission() {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw new OrgAutomationException(
				BarnHelp.text('Core', 'Core_AutomationInventory_NoPermission')
			);
		}
	}

	@TestVisible
	private static AuraHandledException asUserError(Exception caught, String context) {
		return UserErrors.wrap(
			caught,
			caught instanceof OrgAutomationException,
			context,
			BarnHelp.text('Core', 'Core_AutomationInventory_UnexpectedError')
		);
	}
}
