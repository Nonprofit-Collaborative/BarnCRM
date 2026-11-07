/**
 * A stand-in module for the portal action seam's tests. Core resolves it by name, as it would
 * the Volunteers module's class, so the tests reach nothing in Core but its accessible members.
 */
@IsTest
public with sharing class PortalTestModule implements PortalActionExtension {
	/** What it was asked to run: action, person and record. */
	public static List<String> ran = new List<String>();
	/** Whether running fails, as a module refusing would. */
	public static Boolean fail = false;

	/** Registers this module with Core's seam, alone. */
	public static void register() {
		PortalActionExtensions.EXTENSION_CLASSES.clear();
		PortalActionExtensions.EXTENSION_CLASSES.add('PortalTestModule');
		ran.clear();
		fail = false;
	}

	public Set<String> actionNames() {
		return new Set<String>{ 'Test.Thanks' };
	}

	public String run(String actionName, Id personId, Id recordId) {
		if (fail) {
			throw new System.TypeException('Refused');
		}
		ran.add(actionName + ' ' + personId + ' ' + recordId);
		return 'Thanks sent';
	}
}
