/**
 * Change request rules (registry row `Project_Change_Request_Rules`, Always Runs; canonical
 * model 29PM15, R-PM20): a new change request needs the Projects setting Track change requests
 * on. Change requests saved while it was on keep counting and can still be edited. Apex, not a
 * validation rule, because a validation rule cannot read the settings store (ADR-0238 settings
 * as custom metadata).
 */
@NamespaceAccessible
public with sharing class ProjectChangeRequestHandler extends TriggerHandler {
	@NamespaceAccessible
	public ProjectChangeRequestHandler() {
		return;
	}

	public override void beforeInsert() {
		if (ProjectsSettings.changeRequestsSetting()) {
			return;
		}
		String refusal = BarnHelp.text('Projects', 'Projects_ChangeRequests_TurnedOff');
		for (SObject row : newRecords()) {
			row.addError(refusal);
		}
	}
}
