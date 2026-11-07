/**
 * Processes public submissions (canonical model R-FS6; ADR-NEXT public forms on a Salesforce
 * Site, decision 2). Scheduled from Health Check by an administrator, it runs as that
 * administrator, so Core's matchers find people in user mode exactly as for a staff submission;
 * the guest who sent the answers never reads a record.
 *
 * Four scheduled jobs, at :00, :15, :30 and :45 (a cron expression takes one minute value). Each
 * enqueues `Run` when anything is waiting, which processes a few submissions per transaction and
 * enqueues itself again while more wait (a Queueable may not also be Schedulable).
 */
public with sharing class FormPublicProcessor implements Schedulable {
	public static final String JOB_NAME = 'BarnCRM Forms Public Processing';
	@TestVisible
	private static final List<Integer> MINUTES = new List<Integer>{ 0, 15, 30, 45 };
	/** Submissions per transaction: each may run several matcher queries and writes. */
	@TestVisible
	private static final Integer PER_RUN = 5;
	private static final String CONTEXT = 'FormPublicProcessor';

	/** The name of the job at one minute past the hour. */
	public static String jobName(Integer minute) {
		return JOB_NAME + ' :' + String.valueOf(minute).leftPad(2, '0');
	}

	/** Schedules the four jobs as the running user; those already scheduled are kept. */
	public static void schedule() {
		for (Integer minute : MINUTES) {
			ScheduledJobSelector.ensure(
				jobName(minute),
				'0 ' + minute + ' * * * ?',
				new FormPublicProcessor()
			);
		}
	}

	/** True when every one of the four jobs is scheduled. */
	public static Boolean isScheduled() {
		for (Integer minute : MINUTES) {
			if (!ScheduledJobSelector.isScheduled(jobName(minute))) {
				return false;
			}
		}
		return true;
	}

	public void execute(SchedulableContext context) {
		if (!waiting(1).isEmpty()) {
			System.enqueueJob(new Run());
		}
	}

	/** Processes up to PER_RUN waiting submissions, then enqueues itself while more wait. */
	public with sharing class Run implements Queueable {
		public void execute(QueueableContext context) {
			List<Form_Submission__c> batch = waiting(PER_RUN + 1);
			Integer done = 0;
			for (Form_Submission__c submission : batch) {
				if (done == PER_RUN) {
					break;
				}
				done++;
				try {
					FormSubmitService.processReceived(submission.Id);
				} catch (Exception e) {
					// Marked Failed so it is not taken up again; staff can Process Again.
					ErrorLogger.log(e, CONTEXT + '.execute', submission.Id);
					markFailed(submission.Id, e);
				}
			}
			if (batch.size() > PER_RUN && !Test.isRunningTest()) {
				System.enqueueJob(new Run());
			}
		}
	}

	@TestVisible
	private static void markFailed(Id submissionId, Exception e) {
		try {
			update as user new Form_Submission__c(
				Id = submissionId,
				Status__c = FormSubmitService.FAILED,
				Message__c = BarnHelp.text(
						'Forms',
						'Forms_Submit_Failed',
						new List<Object>{ e.getMessage() }
					)
					.abbreviate(255)
			);
		} catch (Exception again) {
			ErrorLogger.log(again, CONTEXT + '.markFailed', submissionId);
		}
	}

	/** The oldest received public submissions, up to the count. */
	public static List<Form_Submission__c> waiting(Integer count) {
		return [
			SELECT Id
			FROM Form_Submission__c
			WHERE Status__c = :FormIntakeService.RECEIVED
			WITH USER_MODE
			ORDER BY CreatedDate ASC, Id ASC
			LIMIT :count
		];
	}
}
