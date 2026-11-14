/**
 * The nightly step's work for the Mirror Case bridge: queues `CaseProviderRequests`, which sends
 * unsent Cases and reads status. A class of its own because Apex refuses to queue a class that is
 * both Queueable and Schedulable ("Queueable cannot be implemented with other system interfaces").
 */
public with sharing class CaseProviderRequestsNightly implements Schedulable {
	public void execute(SchedulableContext schedule) {
		CaseProviderRequests.startNightly();
	}
}
