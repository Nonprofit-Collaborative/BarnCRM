/**
 * What the Automation tab's inventory reads and starts (C-60, D-184). Reading needs the Manage
 * BarnCRM Settings permission; a scan, deactivation or restore through the org connection also
 * needs what the connection does (ADR-0148, ImportNewFieldService.canCreate). Each refusal is in
 * words.
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
			result.isSandbox = [SELECT IsSandbox FROM Organization WITH SYSTEM_MODE LIMIT 1]
			.IsSandbox;
			result.snapshots = OrgAutomationDeactivation.recent();
			return result;
		} catch (Exception caught) {
			throw asUserError(caught, 'Automation inventory');
		}
	}

	/**
	 * Saves a snapshot of the chosen org flows and validation rules, then deactivates them
	 * (R-AS4 to R-AS7). `itemsJson` is a list of OrgAutomationDeactivation.Item.
	 */
	@AuraEnabled
	public static Id deactivate(String itemsJson) {
		try {
			requireConnection();
			List<OrgAutomationDeactivation.Item> items;
			try {
				items = (List<OrgAutomationDeactivation.Item>) JSON.deserialize(
					itemsJson,
					List<OrgAutomationDeactivation.Item>.class
				);
			} catch (JSONException notItems) {
				items = null;
			}
			return OrgAutomationDeactivation.start(items);
		} catch (Exception caught) {
			throw asUserError(caught, 'Deactivate org automation');
		}
	}

	/** Puts back exactly what a deactivation snapshot changed (R-AS8). */
	@AuraEnabled
	public static Id restore(Id snapshotId) {
		try {
			requireConnection();
			return OrgAutomationDeactivation.restore(snapshotId);
		} catch (Exception caught) {
			throw asUserError(caught, 'Restore org automation');
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
			caught instanceof OrgAutomationException ||
			caught instanceof OrgAutomationDeactivation.DeactivationException,
			context,
			BarnHelp.text('Core', 'Core_AutomationInventory_UnexpectedError')
		);
	}
}
