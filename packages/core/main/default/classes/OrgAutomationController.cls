/**
 * What the Automation tab's inventory reads and starts (C-60, D-184). Reading needs the Manage
 * BarnCRM Settings permission; a scan through the org connection also needs what the
 * connection does (ADR-0148, ImportNewFieldService.canCreate). Each refusal is in words.
 */
public with sharing class OrgAutomationController {
	public class OrgAutomationException extends Exception {
	}

	/** Every automation in the org, BarnCRM's and the org's own (OrgAutomationInventory). */
	@AuraEnabled
	public static OrgAutomationInventory.Result getInventory() {
		try {
			requirePermission();
			OrgAutomationInventory.Result result = OrgAutomationInventory.build();
			ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
			result.canUseConnection = connection.canCreate;
			result.connected = connection.connected;
			return result;
		} catch (Exception caught) {
			throw asUserError(caught, 'Automation inventory');
		}
	}

	/** Reads validation rules, workflow rules and coverage through the org connection (R-AS3). */
	@AuraEnabled
	public static Id startScan() {
		try {
			requireConnection();
			return OrgAutomationScan.start();
		} catch (Exception caught) {
			throw asUserError(caught, 'Automation inventory scan');
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

	/** The settings permission, the connection's permissions, and a connection with callouts on. */
	@TestVisible
	private static void requireConnection() {
		requirePermission();
		ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
		if (!connection.canCreate) {
			throw new OrgAutomationException(
				BarnHelp.text('Core', 'Core_AutomationInventory_NoConnectionPermission')
			);
		}
		if (!connection.connected) {
			throw new OrgAutomationException(
				BarnHelp.text('Core', 'Core_AutomationInventory_ConnectionNeeded')
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
