/**
 * Report Subscriptions (C-63, D-156, ADR "Duplicate Rules Starter and report subscriptions
 * through the org connection"): lists the reports in BarnCRM's report folders and subscribes the
 * running user to one through the Analytics Notification API (`lightningReportSubscribe`),
 * called by a queued job through the org connection (ADR-0148). The subscription is the
 * person's own; Salesforce sends it. A report already subscribed is updated, never duplicated.
 */
public with sharing class ReportSubscriptions {
	public static final String LOG_CONTEXT = 'Report subscription ';
	public static final String RUNNING = 'Running';
	public static final String SUBSCRIBED = 'Subscribed';
	public static final String FAILED = 'Failed';
	private static final String SOURCE = 'lightningReportSubscribe';
	private static final Set<String> FREQUENCIES = new Set<String>{ 'daily', 'weekly', 'monthly' };
	private static final Set<String> WEEKDAYS = new Set<String>{
		'sun',
		'mon',
		'tue',
		'wed',
		'thu',
		'fri',
		'sat'
	};
	private static final Integer MAX_REPORTS = 200;

	public class ReportRow {
		@AuraEnabled
		public Id id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String folder;
		@AuraEnabled
		public String description;
	}

	public class SubscriptionView {
		/** May subscribe here: the connection's permissions and a connection with callouts on. */
		@AuraEnabled
		public Boolean canSubscribe = false;
		@AuraEnabled
		public Boolean canUseConnection = false;
		@AuraEnabled
		public Boolean connected = false;
		@AuraEnabled
		public List<ReportRow> reports = new List<ReportRow>();
	}

	public class Outcome {
		@AuraEnabled
		public String state = RUNNING;
		@AuraEnabled
		public String message;
	}

	/** What the person chose: daily, weekly on a day, or monthly on a date, at an hour (0 to 23). */
	public class Choice {
		public Id reportId;
		public String frequency;
		public String weekday;
		public Integer monthDay;
		public Integer hour;
	}

	public class SubscriptionException extends Exception {
	}

	@AuraEnabled
	public static SubscriptionView getView() {
		try {
			SubscriptionView view = new SubscriptionView();
			ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
			view.canUseConnection = connection.canCreate;
			view.connected = connection.connected;
			view.canSubscribe = connection.canCreate && connection.connected;
			for (Report each : [
				SELECT Id, Name, FolderName, Description
				FROM Report
				WHERE FolderName LIKE 'BarnCRM%'
				WITH USER_MODE
				ORDER BY FolderName, Name
				LIMIT :MAX_REPORTS
			]) {
				ReportRow row = new ReportRow();
				row.id = each.Id;
				row.name = each.Name;
				row.folder = each.FolderName;
				row.description = each.Description;
				view.reports.add(row);
			}
			return view;
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'ReportSubscriptions.getView', true);
		}
	}

	/** Checks the choice and queues the job; returns the job's Id for `check`. */
	@AuraEnabled
	public static Id subscribe(String scheduleJson) {
		try {
			ImportNewFieldService.Connection connection = ImportNewFieldService.connection();
			if (!connection.canCreate) {
				throw new SubscriptionException(
					BarnHelp.text('Core', 'Core_AutomationInventory_NoConnectionPermission')
				);
			}
			if (!connection.connected) {
				throw new SubscriptionException(
					BarnHelp.text('Core', 'Core_ReportSubscriptions_ConnectionNeeded')
				);
			}
			Choice chosen = (Choice) JSON.deserialize(scheduleJson, Choice.class);
			if (!valid(chosen)) {
				throw new SubscriptionException(
					BarnHelp.text('Core', 'Core_ReportSubscriptions_ScheduleInvalid')
				);
			}
			List<Report> found = [
				SELECT Name
				FROM Report
				WHERE Id = :chosen.reportId AND FolderName LIKE 'BarnCRM%'
				WITH USER_MODE
				LIMIT 1
			];
			if (found.isEmpty()) {
				throw new SubscriptionException(
					BarnHelp.text('Core', 'Core_ReportSubscriptions_ReportNotFound')
				);
			}
			return AsyncStarter.queue(
				new SubscribeJob(chosen, found[0].Name),
				'ReportSubscriptions.subscribe'
			);
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'ReportSubscriptions.subscribe', true);
		}
	}

	/** Where the job is: still running, subscribed, or failed with the reason in words. */
	@AuraEnabled
	public static Outcome check(Id jobId) {
		try {
			Outcome result = new Outcome();
			List<AsyncApexJob> jobs = [
				SELECT Status
				FROM AsyncApexJob
				WHERE Id = :jobId AND CreatedById = :UserInfo.getUserId()
				WITH SYSTEM_MODE
				LIMIT 1
			];
			if (jobs.isEmpty() || jobs[0].Status == 'Failed' || jobs[0].Status == 'Aborted') {
				result.state = FAILED;
				result.message = BarnHelp.text('Core', 'Core_ReportSubscriptions_JobFailed');
				return result;
			}
			if (jobs[0].Status != 'Completed') {
				return result;
			}
			String context = LOG_CONTEXT + String.valueOf(jobId).left(15) + '%';
			List<Error_Log__c> logged = [
				SELECT Message__c
				FROM Error_Log__c
				WHERE Context__c LIKE :context
				WITH SYSTEM_MODE
				ORDER BY CreatedDate DESC
				LIMIT 1
			];
			// The job logs only a failure; a finished job with no entry subscribed. The entry
			// arrives through ErrorLogger's event, so a first poll may miss it; the page polls
			// once more after Completed before it says Subscribed.
			result.state = logged.isEmpty() ? SUBSCRIBED : FAILED;
			result.message = logged.isEmpty() ? null : logged[0].Message__c;
			return result;
		} catch (Exception e) {
			throw UserErrors.wrap(e, 'ReportSubscriptions.check', true);
		}
	}

	@TestVisible
	private static Boolean valid(Choice chosen) {
		if (chosen == null || chosen.reportId == null || !FREQUENCIES.contains(chosen.frequency)) {
			return false;
		}
		if (chosen.hour == null || chosen.hour < 0 || chosen.hour > 23) {
			return false;
		}
		if (chosen.frequency == 'weekly' && !WEEKDAYS.contains(chosen.weekday)) {
			return false;
		}
		return chosen.frequency != 'monthly' ||
			(chosen.monthDay != null &&
			chosen.monthDay >= 1 &&
			chosen.monthDay <= 31);
	}

	/** The notification body: the report, its schedule, and an email to the subscriber only. */
	@TestVisible
	private static Map<String, Object> body(Choice chosen, String reportName) {
		Map<String, Object> details = new Map<String, Object>{ 'time' => chosen.hour };
		if (chosen.frequency == 'weekly') {
			details.put('daysOfWeek', new List<String>{ chosen.weekday });
		} else if (chosen.frequency == 'monthly') {
			details.put('daysOfMonth', new List<Integer>{ chosen.monthDay });
		}
		return new Map<String, Object>{
			'active' => true,
			'name' => reportName,
			'recordId' => chosen.reportId,
			'source' => SOURCE,
			'schedule' => new Map<String, Object>{
				'frequency' => chosen.frequency,
				'details' => details
			},
			'thresholds' => new List<Object>{
				new Map<String, Object>{
					'type' => 'always',
					'conditions' => null,
					'actions' => new List<Object>{
						new Map<String, Object>{
							'type' => 'sendEmail',
							'configuration' => new Map<String, Object>{
								'recipients' => new List<Object>()
							}
						}
					}
				}
			}
		};
	}

	/**
	 * Updates the person's subscription to the report when there is one, else checks the
	 * per-user limit and creates one. Logs only a failure, in words, under the job's context.
	 */
	public with sharing class SubscribeJob implements Queueable, Database.AllowsCallouts {
		private final Choice chosen;
		private final String reportName;

		public SubscribeJob(Choice chosen, String reportName) {
			this.chosen = chosen;
			this.reportName = reportName;
		}

		public void execute(QueueableContext context) {
			String logContext =
				LOG_CONTEXT + (context == null ? 'test' : String.valueOf(context.getJobId()));
			try {
				String failure = save(chosen, reportName);
				if (failure != null) {
					ErrorLogger.logMessage(failure, logContext, ErrorLogger.SEVERITY_ERROR);
				}
			} catch (Exception e) {
				ErrorLogger.logWithMessage(
					e,
					logContext,
					BarnHelp.text(
						'Core',
						'Core_ReportSubscriptions_Refused',
						new List<Object>{ reportName, e.getMessage() }
					)
				);
			}
		}
	}

	/** Returns null when saved, else why not in words. */
	@TestVisible
	private static String save(Choice chosen, String reportName) {
		String body = JSON.serialize(body(chosen, reportName));
		String query =
			'analytics/notifications?source=' +
			SOURCE +
			'&recordId=' +
			EncodingUtil.urlEncode(chosen.reportId, 'UTF-8');
		List<Object> existing = (List<Object>) JSON.deserializeUntyped(
			OrgToolingApi.rest('GET', query, null)
		);
		if (!existing.isEmpty()) {
			String notificationId = String.valueOf(((Map<String, Object>) existing[0]).get('id'));
			OrgToolingApi.rest('PUT', 'analytics/notifications/' + notificationId, body);
			return null;
		}
		Map<String, Object> limits = (Map<String, Object>) JSON.deserializeUntyped(
			OrgToolingApi.rest('GET', 'analytics/notifications/limits?source=' + SOURCE, null)
		);
		Map<String, Object> userLimit = (Map<String, Object>) limits.get('userLimit');
		if (userLimit != null && (Integer) userLimit.get('remaining') <= 0) {
			return BarnHelp.text(
				'Core',
				'Core_ReportSubscriptions_LimitReached',
				new List<Object>{ userLimit.get('max') }
			);
		}
		OrgToolingApi.rest('POST', 'analytics/notifications', body);
		return null;
	}
}
