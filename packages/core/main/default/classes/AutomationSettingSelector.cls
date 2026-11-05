/**
 * Every query against the Automation Setting object (plan Section 9.3).
 *
 * `selectAllForFramework` runs in system mode on purpose, and it is the only method here that
 * does. The trigger dispatcher asks it, on every save, whether an automation is switched on. A
 * user-mode read would throw for anyone whose permission sets do not include this configuration
 * object, which would turn a missing permission into a failed save for that person. Reading a
 * packaged on and off switch is not a data disclosure: no record data is returned and nothing is
 * written. Everything the settings console reads goes through `selectAllForConsole`, in user
 * mode, so the console shows a person only what they are allowed to see.
 */
public with sharing class AutomationSettingSelector {
	public static List<Automation_Setting__c> selectAllForFramework() {
		return [
			SELECT
				Id,
				Name,
				Automation_Name__c,
				Description__c,
				Enabled__c,
				Always_Runs__c,
				Handler_Class__c,
				Object_Name__c,
				Execution_Order__c,
				Is_Package_Default__c
			FROM Automation_Setting__c
			WITH SYSTEM_MODE
			ORDER BY Execution_Order__c NULLS LAST, Name
			LIMIT 1000
		];
	}

	public static List<Automation_Setting__c> selectAllForConsole() {
		return [
			SELECT
				Id,
				Name,
				Automation_Name__c,
				Description__c,
				Enabled__c,
				Always_Runs__c,
				Handler_Class__c,
				Object_Name__c,
				Execution_Order__c,
				Is_Package_Default__c
			FROM Automation_Setting__c
			WITH USER_MODE
			ORDER BY Execution_Order__c NULLS LAST, Name
			LIMIT 1000
		];
	}

	public static List<Automation_Setting__c> selectByNames(Set<String> automationNames) {
		if (automationNames == null || automationNames.isEmpty()) {
			return new List<Automation_Setting__c>();
		}
		return [
			SELECT
				Id,
				Name,
				Automation_Name__c,
				Description__c,
				Enabled__c,
				Always_Runs__c,
				Handler_Class__c,
				Object_Name__c,
				Execution_Order__c,
				Is_Package_Default__c
			FROM Automation_Setting__c
			WHERE Automation_Name__c IN :automationNames
			WITH USER_MODE
			ORDER BY Name
			LIMIT 1000
		];
	}
}
