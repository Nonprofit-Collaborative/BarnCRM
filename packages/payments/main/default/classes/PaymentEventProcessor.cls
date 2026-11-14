/**
 * Processes received processor events (ADR-0201 `0201-payments-module.md`, decision 6; R-PEV2,
 * R-PEV3). Scheduled from Health Check by an administrator, it runs as them, in user mode.
 *
 * Four scheduled jobs, at :00, :15, :30 and :45. Each enqueues `Abandon`, which cancels abandoned
 * checkouts (R-PAY3), and `Run` when events wait. `Run` reads up to PER_RUN events with every callout first
 * (PayPal verification and capture), then writes them all, since Salesforce allows no callout
 * after a write; it enqueues itself again while more wait.
 */
public with sharing class PaymentEventProcessor implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Payments Processing';
	@TestVisible
	private static final List<Integer> MINUTES = new List<Integer>{ 0, 15, 30, 45 };
	/** Events per transaction: a PayPal event takes up to three callouts, plus one sign-in. */
	@TestVisible
	private static final Integer PER_RUN = 20;
	/** Abandoned checkouts cancelled per transaction (R-PAY3). */
	@TestVisible
	private static final Integer ABANDON_PER_RUN = 50;
	/** Reading stops after this long, leaving room for one more event's three 20-second callouts. */
	@TestVisible
	private static Long calloutBudgetMs = 60000;
	private static final String CONTEXT = 'PaymentEventProcessor';

	public static String jobName(Integer minute) {
		return JOB_NAME + ' :' + String.valueOf(minute).leftPad(2, '0');
	}

	/** Schedules the four jobs as the running user; those already scheduled are kept. */
	public static void schedule() {
		for (Integer minute : MINUTES) {
			ScheduledJobSelector.ensure(
				jobName(minute),
				'0 ' + minute + ' * * * ?',
				new PaymentEventProcessor()
			);
		}
	}

	public static Boolean isScheduled() {
		for (Integer minute : MINUTES) {
			if (!ScheduledJobSelector.isScheduled(jobName(minute))) {
				return false;
			}
		}
		return true;
	}

	public void execute(SchedulableContext context) {
		System.enqueueJob(new Abandon());
		if (!waiting(1).isEmpty()) {
			System.enqueueJob(new Run());
		}
	}

	/**
	 * Cancels up to ABANDON_PER_RUN abandoned checkouts (R-PAY3) in a transaction of its own, so
	 * their listeners never share limits with event processing; enqueues itself while more wait.
	 */
	public with sharing class Abandon implements Queueable {
		public void execute(QueueableContext context) {
			Integer cancelled = 0;
			try {
				cancelled = PaymentService.cancelAbandoned(ABANDON_PER_RUN);
			} catch (Exception e) {
				ErrorLogger.log(e, CONTEXT + '.cancelAbandoned');
			}
			if (cancelled == ABANDON_PER_RUN && !Test.isRunningTest()) {
				System.enqueueJob(new Abandon());
			}
		}
	}

	/**
	 * Reads and applies up to PER_RUN events, then enqueues itself while more wait. Reading stops
	 * once the callout-time budget is spent (a PayPal event can take three 20-second callouts and
	 * a transaction allows 120 seconds of them), leaving the rest Received. An event whose
	 * callout failed in transport stays Received too, and is read again by the next run.
	 */
	public with sharing class Run implements Queueable, Database.AllowsCallouts {
		public void execute(QueueableContext context) {
			List<Payment_Event__c> batch = waiting(PER_RUN + 1);
			List<PaymentService.Outcome> outcomes = new List<PaymentService.Outcome>();
			// Logged after the last callout: the Error Log's direct-insert fallback is DML, and DML
			// before a callout in the same transaction is refused.
			Map<Id, Exception> readFailures = new Map<Id, Exception>();
			Long started = System.currentTimeMillis();
			Boolean more = batch.size() > PER_RUN;
			for (Integer i = 0; i < Math.min(PER_RUN, batch.size()); i++) {
				if (
					i > 0 &&
					(System.currentTimeMillis() - started > calloutBudgetMs ||
					Limits.getCallouts() + 4 > Limits.getLimitCallouts())
				) {
					more = true;
					break;
				}
				Payment_Event__c event = batch[i];
				try {
					outcomes.add(
						event.Processor__c == PaymentService.PAYPAL
							? PaymentPayPal.read(event)
							: PaymentStripe.read(event)
					);
				} catch (CalloutException e) {
					readFailures.put(event.Id, e);
				} catch (Exception e) {
					readFailures.put(event.Id, e);
					outcomes.add(
						new PaymentService.Outcome(event)
							.nothing(
								'Failed',
								BarnHelp.text(
									'Payments',
									'Payments_Event_Failed',
									new List<Object>{ e.getMessage() }
								)
							)
					);
				}
			}
			for (Id eventId : readFailures.keySet()) {
				ErrorLogger.log(readFailures.get(eventId), CONTEXT + '.read', eventId);
			}
			if (outcomes.isEmpty()) {
				// Every read failed in transport: the next scheduled run tries again.
				return;
			}
			try {
				PaymentService.apply(outcomes);
			} catch (Exception e) {
				ErrorLogger.log(e, CONTEXT + '.apply');
				markFailed(outcomes, e);
			}
			if (more && !Test.isRunningTest()) {
				System.enqueueJob(new Run());
			}
		}
	}

	/** Marks the run's read events Failed so they are not taken up again and again. */
	private static void markFailed(List<PaymentService.Outcome> outcomes, Exception e) {
		List<Payment_Event__c> failed = new List<Payment_Event__c>();
		for (PaymentService.Outcome outcome : outcomes) {
			failed.add(
				new Payment_Event__c(
					Id = outcome.event.Id,
					Status__c = 'Failed',
					Message__c = BarnHelp.text(
							'Payments',
							'Payments_Event_Failed',
							new List<Object>{ e.getMessage() }
						)
						.abbreviate(255)
				)
			);
		}
		Database.update(failed, false, AccessLevel.USER_MODE);
	}

	/** The oldest received events, up to the count. */
	public static List<Payment_Event__c> waiting(Integer count) {
		return [
			SELECT Id, Processor__c, Event_Key__c, Event_Type__c, Payload__c, Headers__c
			FROM Payment_Event__c
			WHERE Status__c = 'Received'
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
			LIMIT :count
		];
	}
}
