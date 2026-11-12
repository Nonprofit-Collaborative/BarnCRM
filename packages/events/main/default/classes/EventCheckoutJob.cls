/**
 * Starts the checkouts of form registrations waiting for payment (EV-20, R-ERG5; ADR-0207
 * `0207-events-paid-registration-proposals-ratings.md`, decision 3). Payments allows one checkout
 * per transaction (callout, then write), so each run takes the oldest Pending Payment registration
 * still Unpaid and queues the next run while more wait. A checkout that cannot be started marks
 * the registration's payment Failed and is logged, so staff can send a link from the
 * Registrations tab and the queue never stops on one registration.
 */
public with sharing class EventCheckoutJob implements Queueable, Database.AllowsCallouts {
	public void execute(QueueableContext context) {
		List<Event_Registration__c> waiting = [
			SELECT Id
			FROM Event_Registration__c
			WHERE
				Status__c = :EventRegistrationService.STATUS_PENDING_PAYMENT
				AND Payment_Status__c = :EventPayments.UNPAID
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT 2
		];
		if (waiting.isEmpty()) {
			return;
		}
		try {
			EventPayments.sendLink(waiting[0].Id);
		} catch (Exception e) {
			ErrorLogger.log(e, 'EventCheckoutJob.execute', waiting[0].Id);
			if (!markFailed(waiting[0].Id)) {
				// Still Unpaid, so the next run would take it again: stop rather than loop.
				return;
			}
		}
		if (waiting.size() > 1 && !Test.isRunningTest()) {
			System.enqueueJob(new EventCheckoutJob());
		}
	}

	/** Marks the payment Failed; false when the save did not go through. */
	@TestVisible
	private static Boolean markFailed(Id registrationId) {
		Database.SaveResult saved = Database.update(
			new Event_Registration__c(
				Id = registrationId,
				Payment_Status__c = EventPayments.FAILED
			),
			false,
			AccessLevel.SYSTEM_MODE
		);
		return saved.isSuccess();
	}
}
