/**
 * The Nightly Jobs panel on the General page of BarnCRM Settings (ADR-0166
 * nightly-job-dispatcher, R-NJ1 to R-NJ7): whether the one nightly schedule exists, and every
 * step of every module in the order the run takes it, with its time, whether it is on and how it
 * last ran. A manager schedules the run, switches a step that has a switch, and starts a step
 * that allows it now (D-200 S6, the one nightly card that replaced Giving's Nightly Jobs page).
 * Returns plain JSON-shaped wrappers (plan 9.9).
 */
public with sharing class NightlyJobsController {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		null,
		null,
		System.Label.Core_UnexpectedError
	);

	/** Raised with a message the panel shows as it is. */
	public class NightlyJobsException extends Exception {
	}

	/** The panel, in one round trip. */
	public class PanelView {
		@AuraEnabled
		public Boolean canManage;
		@AuraEnabled
		public Boolean scheduled;
		@AuraEnabled
		public Datetime lastRunStarted;
		@AuraEnabled
		public Datetime lastRunFinished;
		@AuraEnabled
		public String lastRunOutcome;
		@AuraEnabled
		public List<StepView> steps = new List<StepView>();
	}

	/** One step. */
	public class StepView {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		/** Minutes after midnight, which the panel shows as a time of day. */
		@AuraEnabled
		public Integer minute;
		@AuraEnabled
		public Boolean isOn;
		@AuraEnabled
		public Datetime lastStarted;
		@AuraEnabled
		public String outcome;
		/** The kit status word for the outcome (done, attention, failed, skipped, in-progress). */
		@AuraEnabled
		public String outcomeStatus;
		@AuraEnabled
		public String message;
		/** True when the step has a switch of its own, which the card turns on and off. */
		@AuraEnabled
		public Boolean hasSwitch;
		/** The switch's state, whatever the step's settings say tonight. */
		@AuraEnabled
		public Boolean switchedOn;
		@AuraEnabled
		public Boolean canRunNow;
		/** The step's own summary of its last run, when it keeps one. */
		@AuraEnabled
		public String summary;
		/** On, but it did not start when the last nightly run (over two hours ago) did. */
		@AuraEnabled
		public Boolean missed;
	}

	/** How long after a run starts a step that has not started yet is still only waiting. */
	private static final Integer SETTLING_HOURS = 2;

	@AuraEnabled
	public static PanelView getPanel() {
		try {
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Nightly Jobs panel');
		}
	}

	/** Schedules the nightly run (and the hourly check) to run as the person pressing it. */
	@AuraEnabled
	public static PanelView schedule() {
		try {
			if (!BarnCRMPermissions.canManageSettings()) {
				throw new NightlyJobsException(
					BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired')
				);
			}
			NightlyJobs.scheduleAll();
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Schedule the nightly jobs');
		}
	}

	/**
	 * Turns a step's own switch on (scheduling the run when it is not) or off, org-wide. Refused
	 * for a step with no switch.
	 */
	@AuraEnabled
	public static PanelView setStep(String key, Boolean turnOn) {
		try {
			NightlyStep step = managedStep(key);
			if (!step.hasSwitch()) {
				throw new NightlyJobsException(BarnHelp.text('Core', 'Core_NightlyJobs_NoSwitch'));
			}
			if (turnOn == true) {
				NightlyJobs.turnOn(step.key);
			} else {
				NightlyJobs.turnOff(step.key);
			}
			NightlyJobs.forget();
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Switch a nightly job');
		}
	}

	/** Starts a step's work now, for a step that allows it; tonight's run is unchanged. */
	@AuraEnabled
	public static PanelView runStep(String key) {
		try {
			NightlyStep step = managedStep(key);
			if (step.canRunNow != true) {
				throw new NightlyJobsException(BarnHelp.text('Core', 'Core_NightlyJobs_NoRunNow'));
			}
			step.run();
			return currentView();
		} catch (Exception caught) {
			throw ERRORS.wrap(caught, 'Run a nightly job now');
		}
	}

	/** The step with this key, for someone who can manage BarnCRM Settings. */
	private static NightlyStep managedStep(String key) {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw new NightlyJobsException(
				BarnHelp.text('Core', 'Core_HealthCheck_PermissionRequired')
			);
		}
		NightlyStep step = String.isBlank(key) ? null : NightlyJobs.step(key);
		if (step == null) {
			throw new NightlyJobsException(BarnHelp.text('Core', 'Core_NightlyJobs_NoSuchJob'));
		}
		return step;
	}

	private static PanelView currentView() {
		PanelView view = new PanelView();
		view.canManage = BarnCRMPermissions.canManageSettings();
		view.scheduled = NightlyJobs.isScheduled();
		Map<String, Nightly_Job__c> rows = NightlyJobs.rows();
		Nightly_Job__c run = rows.get(ScheduledJobSelector.nameKey(NightlyJobs.JOB_NAME));
		if (run != null) {
			view.lastRunStarted = run.Last_Started__c;
			view.lastRunFinished = run.Last_Finished__c;
			view.lastRunOutcome = outcomeLabel(run.Last_Outcome__c);
		}
		for (NightlyStep step : NightlyJobs.steps()) {
			StepView item = new StepView();
			item.key = step.key;
			item.label = step.label;
			item.minute = step.minute;
			item.isOn = NightlyJobs.isOn(step);
			item.hasSwitch = step.hasSwitch();
			item.switchedOn =
				!step.hasSwitch() || NightlyJobs.isSwitchedOn(step.key, step.switchDefault);
			item.canRunNow = step.canRunNow == true;
			item.summary = step.summary;
			Nightly_Job__c row = rows.get(ScheduledJobSelector.nameKey(step.key));
			if (row != null) {
				item.lastStarted = row.Last_Started__c;
				item.outcome = outcomeLabel(row.Last_Outcome__c);
				item.outcomeStatus = outcomeStatus(row.Last_Outcome__c);
				item.message = row.Last_Message__c;
			}
			item.missed =
				item.isOn &&
				view.lastRunStarted != null &&
				view.lastRunStarted < Datetime.now().addHours(-SETTLING_HOURS) &&
				(item.lastStarted == null ||
				item.lastStarted < view.lastRunStarted);
			view.steps.add(item);
		}
		return view;
	}

	/** The kit status word for a stored outcome: it picks the badge's tone, never its text. */
	@TestVisible
	private static String outcomeStatus(String value) {
		if (value == 'Done') {
			return 'done';
		}
		if (value == 'Failed') {
			return 'failed';
		}
		if (value == 'Skipped') {
			return 'skipped';
		}
		if (value == 'Running') {
			return 'in-progress';
		}
		return String.isBlank(value) ? null : 'attention';
	}

	/** The outcome as the org's picklist labels it, so a translation shows. */
	private static String outcomeLabel(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		for (
			Schema.PicklistEntry entry : Nightly_Job__c.Last_Outcome__c.getDescribe()
				.getPicklistValues()
		) {
			if (entry.getValue() == value) {
				return entry.getLabel();
			}
		}
		return value;
	}
}
