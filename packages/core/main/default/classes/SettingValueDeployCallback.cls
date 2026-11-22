/**
 * Records how a settings save ended (ADR-NEXT settings as custom metadata, R-STV2).
 *
 * Success writes one Setting Change per audited key, with the deployment Id, so Recent Changes
 * lists the change once it has happened and the console can see that the save finished; then
 * the save's side effects run (SettingsService.afterSaved), because the new values are in
 * effect only now. Failure writes one Error Log entry whose record reference is the deployment
 * Id, with Salesforce's reason, which the console shows as it is.
 *
 * Salesforce runs this in its own transaction after the deployment, so everything it needs is
 * carried on the instance, and the audit rows are written in system mode: the transaction is
 * not guaranteed to run as the person who saved (ADR-0021).
 */
public without sharing class SettingValueDeployCallback implements Metadata.DeployCallback {
	private final List<SettingStore.Change> changes;
	private final Boolean audit;
	private final Id requestedBy;

	public SettingValueDeployCallback(List<SettingStore.Change> changes, Boolean audit, Id requestedBy) {
		this.changes = changes;
		this.audit = audit == true;
		this.requestedBy = requestedBy;
	}

	public void handleResult(Metadata.DeployResult result, Metadata.DeployCallbackContext context) {
		Id deploymentId = context == null ? null : context.getCallbackJobId();
		if (result == null || result.status != Metadata.DeployStatus.Succeeded) {
			ErrorLogger.logMessage(
				String.format(
					BarnHelp.text('Core', 'Core_CmdtManager_DeployFailed'),
					new List<Object>{ names(), CustomMetadataDeployCallback.reasonOf(result) }
				),
				SettingStore.ERROR_CONTEXT,
				ErrorLogger.SEVERITY_ERROR,
				deploymentId
			);
			return;
		}
		if (audit) {
			Database.insert(auditRows(deploymentId), AccessLevel.SYSTEM_MODE);
		}
		try {
			SettingsService.afterSaved(changes);
		} catch (Exception failed) {
			// The values are saved; a side effect that failed is logged, not undone.
			ErrorLogger.log(failed, SettingStore.ERROR_CONTEXT);
		}
	}

	private List<Setting_Change__c> auditRows(Id deploymentId) {
		List<Setting_Change__c> rows = new List<Setting_Change__c>();
		Datetime changedAt = System.now();
		for (SettingStore.Change change : changes) {
			rows.add(
				new Setting_Change__c(
					Setting_Name__c = change.settingName == null ? change.name : change.settingName.left(255),
					Old_Value__c = change.oldText,
					New_Value__c = change.newText,
					Changed_By__c = requestedBy,
					Changed_At__c = changedAt,
					Deployment_Id__c = deploymentId
				)
			);
		}
		return rows;
	}

	private String names() {
		List<String> names = new List<String>();
		for (SettingStore.Change change : changes) {
			Setting_Definition__mdt definition = SettingStore.definitions().get(change.name);
			names.add(definition == null ? change.name : definition.MasterLabel);
		}
		return String.join(names, ', ');
	}
}
