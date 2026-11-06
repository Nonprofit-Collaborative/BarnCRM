/**
 * Record-level rule for Session_Schedule__c, run by the Core trigger dispatcher through the
 * registry row `Session_Schedule_Rules`, switchable from the console (ADR-0017, R-SS3): saving
 * an active schedule queues a run for it, so its sessions appear at once. The run's own save of
 * Created Through queues nothing. Editing or ending a schedule deletes no session (R-SS4).
 */
@NamespaceAccessible
public with sharing class SessionScheduleTriggerHandler extends TriggerHandler {
	@NamespaceAccessible
	public SessionScheduleTriggerHandler() {
		return;
	}

	public override String getName() {
		return 'SessionScheduleTriggerHandler';
	}

	public override void afterInsert() {
		queueActive(null);
	}

	public override void afterUpdate() {
		queueActive((Map<Id, Session_Schedule__c>) oldRecordsById());
	}

	private void queueActive(Map<Id, Session_Schedule__c> oldById) {
		Set<Id> toRun = new Set<Id>();
		for (Session_Schedule__c schedule : (List<Session_Schedule__c>) newRecords()) {
			Session_Schedule__c old = oldById == null ? null : oldById.get(schedule.Id);
			Boolean ownSave = old != null && old.Created_Through__c != schedule.Created_Through__c;
			if (schedule.Active__c == true && !ownSave) {
				toRun.add(schedule.Id);
			}
		}
		SessionScheduleJob.queue(toRun);
	}
}
