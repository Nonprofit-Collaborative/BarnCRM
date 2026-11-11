/**
 * BarnCRM's nightly run: its steps, their switches and last results, its one schedule, and the
 * adoption of the separate schedules it replaced (ADR-0166 nightly-job-dispatcher, canonical
 * model R-NJ1 to R-NJ7). `NightlyRun` runs the steps; this class is everything else, and what
 * every page, Health Check and the install steps call.
 *
 * Steps are Core's own plus those of each dependent package that registers a
 * `NightlyStepProvider`, found by class name as `HealthCheckExtensions` finds an extension: a
 * class name takes no `__` prefix, so it is tried with this package's namespace and then
 * without. A provider that is missing, cannot be built or throws is skipped and logged.
 *
 * Switches and results are rows of `Nightly_Job__c`, one per step key plus one for the run,
 * read once per transaction and written in system mode (ADR-0021): they are the package's own
 * bookkeeping, and the run writes them as whoever scheduled it.
 */
@NamespaceAccessible
public with sharing class NightlyJobs {
	/** The nightly run's scheduled job, and the key of the run's own row. */
	@NamespaceAccessible
	public static final String JOB_NAME = 'BarnCRM Nightly Jobs';

	/** The one-time job the run schedules to resume after a long wait (R-NJ1). */
	public static final String CONTINUE_JOB_NAME = 'BarnCRM Nightly Jobs Continue';

	/** Every day at midnight, in the scheduling user's time zone. */
	@TestVisible
	private static final String NIGHTLY_CRON = '0 0 0 * * ?';

	/** The stored switch values (`Switch__c`). */
	public static final String SWITCH_ON = 'On';
	public static final String SWITCH_OFF = 'Off';

	/** The stored outcomes (`Last_Outcome__c`). */
	public static final String RUNNING = 'Running';
	public static final String DONE = 'Done';
	public static final String DONE_WITH_ERRORS = 'Done With Errors';
	public static final String FAILED = 'Failed';
	public static final String SKIPPED = 'Skipped';
	public static final String GAVE_UP = 'Gave Up Waiting';

	/** The provider classes dependent packages register, in the order they are asked. */
	@NamespaceAccessible
	public static final List<String> PROVIDER_CLASSES = new List<String>{
		'RollupsNightlyJobProvider',
		'GivingNightlyJobProvider',
		'MirrorNightlyJobProvider',
		'VolunteersNightlyJobProvider',
		'ProgramsNightlyJobProvider',
		'LogicModelsNightlyJobProvider',
		'FundersNightlyJobProvider',
		'EventsNightlyJobProvider',
		'CorporateHubNightlyJobProvider',
		'TerritoryNightlyJobProvider'
	};

	/** Separate schedules of steps that became part of another step: adopted, then aborted. */
	private static final List<String> RETIRED_KEYS = new List<String>{
		ImportRowPurgeScheduler.JOB_NAME
	};

	private static final String ERROR_CONTEXT = 'NightlyJobs';

	/** Set by a test to the whole list, so no test depends on which modules are installed. */
	@TestVisible
	private static List<NightlyStep> stepsOverride;

	/** Injected by Core's tests by class name, since no other package is there to resolve. */
	@TestVisible
	private static Map<String, NightlyStepProvider> providerOverrides = new Map<String, NightlyStepProvider>();

	/**
	 * True lets a test adopt old schedules. Off in tests by default, because a test sees the
	 * org's real scheduled jobs and an abort would not be rolled back.
	 */
	@TestVisible
	private static Boolean adoptInTests = false;

	/** The rows by key, read once per transaction; null until asked. */
	private static Map<String, Nightly_Job__c> rowsByKey;

	/** The steps, built once per transaction; null until asked. */
	private static List<NightlyStep> builtSteps;

	/**
	 * Sets `stepsOverride` from a module's test, where `@TestVisible` does not reach once the
	 * packages are separate. Does nothing outside a test.
	 */
	@NamespaceAccessible
	public static void overrideStepsForTest(List<NightlyStep> steps) {
		if (Test.isRunningTest()) {
			stepsOverride = steps;
			builtSteps = null;
		}
	}

	/**
	 * The name the run is scheduled under. A test gets a name of its own, because the org a
	 * test runs in may already have the real run, which a test can neither see past nor stop.
	 */
	@NamespaceAccessible
	public static String jobName() {
		return Test.isRunningTest() ? JOB_NAME + ' Test' : JOB_NAME;
	}

	// -------------------------------------------------------------------------------------
	// Steps
	// -------------------------------------------------------------------------------------

	/** Every step, on or off, in the order the run takes them (R-NJ2). */
	@NamespaceAccessible
	public static List<NightlyStep> steps() {
		if (builtSteps != null) {
			return builtSteps;
		}
		List<NightlyStep> registered = new List<NightlyStep>();
		if (stepsOverride != null) {
			registered.addAll(stepsOverride);
		} else {
			registered.addAll(coreSteps());
			for (String className : PROVIDER_CLASSES) {
				registered.addAll(providedBy(className));
			}
		}
		builtSteps = inOrder(registered);
		return builtSteps;
	}

	/** The step with this key, or null when no installed package has it. */
	@NamespaceAccessible
	public static NightlyStep step(String key) {
		String wanted = rowKey(key);
		for (NightlyStep candidate : steps()) {
			if (rowKey(candidate.key) == wanted) {
				return candidate;
			}
		}
		return null;
	}

	private static List<NightlyStep> coreSteps() {
		return new List<NightlyStep>{
			SeasonalAddressScheduler.step(),
			RecordRetentionBatch.step(),
			SetupChangeCopyJob.step(),
			EmptyHouseholdTidyScheduler.step(),
			ErrorDigestScheduler.step()
		};
	}

	/** By time of day; steps at the same time keep the order they were registered in. */
	private static List<NightlyStep> inOrder(List<NightlyStep> registered) {
		Map<Integer, List<NightlyStep>> byMinute = new Map<Integer, List<NightlyStep>>();
		for (NightlyStep candidate : registered) {
			if (candidate == null) {
				continue;
			}
			if (!byMinute.containsKey(candidate.minute)) {
				byMinute.put(candidate.minute, new List<NightlyStep>());
			}
			byMinute.get(candidate.minute).add(candidate);
		}
		List<Integer> minutes = new List<Integer>(byMinute.keySet());
		minutes.sort();
		List<NightlyStep> ordered = new List<NightlyStep>();
		for (Integer minute : minutes) {
			ordered.addAll(byMinute.get(minute));
		}
		return ordered;
	}

	private static List<NightlyStep> providedBy(String className) {
		try {
			NightlyStepProvider provider = providerOverrides.containsKey(className)
				? providerOverrides.get(className)
				: resolve(className);
			List<NightlyStep> provided = provider == null ? null : provider.nightlySteps();
			return provided == null ? new List<NightlyStep>() : provided;
		} catch (Exception failed) {
			ErrorLogger.log(failed, ERROR_CONTEXT);
			return new List<NightlyStep>();
		}
	}

	private static NightlyStepProvider resolve(String className) {
		Type providerType = NamespaceUtil.resolveType(className);
		if (providerType == null) {
			return null;
		}
		Object candidate = providerType.newInstance();
		// A module still on its provider from before the nightly run (mid-upgrade) is skipped.
		return candidate instanceof NightlyStepProvider ? (NightlyStepProvider) candidate : null;
	}

	// -------------------------------------------------------------------------------------
	// Switches
	// -------------------------------------------------------------------------------------

	/**
	 * Whether the step with this key is switched on: its saved switch, or `shippedOn` while
	 * none is saved (R-NJ4).
	 */
	@NamespaceAccessible
	public static Boolean isSwitchedOn(String key, Boolean shippedOn) {
		Nightly_Job__c saved = rows().get(rowKey(key));
		if (saved == null || String.isBlank(saved.Switch__c)) {
			return shippedOn == true;
		}
		return saved.Switch__c == SWITCH_ON;
	}

	/** Whether tonight's run includes this step: its settings allow it and its switch is on. */
	@NamespaceAccessible
	public static Boolean isOn(NightlyStep candidate) {
		if (candidate == null || candidate.active != true) {
			return false;
		}
		return !candidate.hasSwitch() || isSwitchedOn(candidate.key, candidate.switchDefault);
	}

	/**
	 * Turns a step's switch on and makes sure the nightly run is scheduled: what a page's
	 * Schedule button does now (R-NJ4). Returns the run's trigger Id.
	 */
	@NamespaceAccessible
	public static Id turnOn(String key) {
		saveSwitch(key, SWITCH_ON);
		return start();
	}

	/** Turns a step's switch off: what a page's Stop button does now. The run stays scheduled. */
	@NamespaceAccessible
	public static void turnOff(String key) {
		saveSwitch(key, SWITCH_OFF);
	}

	/**
	 * Whether the step with this key runs tonight as far as its switch goes: the run is
	 * scheduled and the switch is on. What a page's "scheduled" means now.
	 */
	@NamespaceAccessible
	public static Boolean isStepScheduled(String key, Boolean shippedOn) {
		return isScheduled() && isSwitchedOn(key, shippedOn);
	}

	private static void saveSwitch(String key, String value) {
		Nightly_Job__c row = rowFor(key);
		row.Switch__c = value;
		save(new List<Nightly_Job__c>{ row });
	}

	// -------------------------------------------------------------------------------------
	// Schedule
	// -------------------------------------------------------------------------------------

	/** True when the nightly run is scheduled. */
	@NamespaceAccessible
	public static Boolean isScheduled() {
		return ScheduledJobSelector.isScheduled(jobName());
	}

	/** Schedules the nightly run, or does nothing when it is already scheduled. */
	@NamespaceAccessible
	public static Id start() {
		return ScheduledJobSelector.ensure(jobName(), NIGHTLY_CRON, new NightlyRun());
	}

	/**
	 * When this step next starts at the earliest: its time of day today, or tomorrow once that
	 * has passed. Null when the run is not scheduled. Takes the step, not its key, so a page
	 * asking about its own step never builds every package's steps.
	 */
	@NamespaceAccessible
	public static Datetime nextRunAt(NightlyStep found) {
		if (found == null || !isScheduled()) {
			return null;
		}
		Datetime today = Datetime.newInstance(
			Date.today(),
			Time.newInstance(found.minute / 60, Math.mod(found.minute, 60), 0, 0)
		);
		return today > Datetime.now() ? today : today.addDays(1);
	}

	/** When the step with this key last started, or null when it never has. */
	@NamespaceAccessible
	public static Datetime lastStarted(String key) {
		Nightly_Job__c row = rows().get(rowKey(key));
		return row == null ? null : row.Last_Started__c;
	}

	// -------------------------------------------------------------------------------------
	// Adopting the old schedules (R-NJ5)
	// -------------------------------------------------------------------------------------

	/**
	 * Replaces every separate schedule a known step used to have with the nightly run: aborts
	 * each, turns on the switch of a step that has one, and schedules the run when anything was
	 * adopted. Returns true when something was. Never throws.
	 */
	@NamespaceAccessible
	public static Boolean adoptOldSchedules() {
		if (Test.isRunningTest() && !adoptInTests) {
			return false;
		}
		try {
			List<Nightly_Job__c> switched = new List<Nightly_Job__c>();
			Boolean adopted = false;
			for (String retired : RETIRED_KEYS) {
				Id gone = ScheduledJobSelector.triggerIdByName(retired);
				if (gone != null) {
					ScheduledJobSelector.abort(gone);
					adopted = true;
				}
			}
			for (NightlyStep candidate : steps()) {
				Id old = ScheduledJobSelector.triggerIdByName(candidate.key);
				if (old == null) {
					continue;
				}
				ScheduledJobSelector.abort(old);
				adopted = true;
				if (candidate.hasSwitch()) {
					Nightly_Job__c row = rowFor(candidate.key);
					row.Switch__c = SWITCH_ON;
					switched.add(row);
				}
			}
			save(switched);
			if (adopted) {
				start();
			}
			return adopted;
		} catch (Exception failed) {
			ErrorLogger.log(failed, ERROR_CONTEXT);
			return false;
		}
	}

	// -------------------------------------------------------------------------------------
	// Health Check
	// -------------------------------------------------------------------------------------

	/** The labels of what is not scheduled: the nightly run and the hourly tab access check. */
	@NamespaceAccessible
	public static List<String> unscheduledLabels() {
		List<String> labels = new List<String>();
		if (!isScheduled()) {
			labels.add(System.Label.Core_NightlyJobs_Title);
		}
		if (!TabAccessScheduler.isScheduled()) {
			labels.add(System.Label.Core_HealthCheck_JobTabAccess);
		}
		return labels;
	}

	/**
	 * Adopts any old schedule, then schedules the nightly run and the hourly check where they
	 * are missing. Returns the labels of those that were missing.
	 */
	public static List<String> scheduleAll() {
		List<String> scheduled = unscheduledLabels();
		adoptOldSchedules();
		start();
		TabAccessScheduler.start();
		return scheduled;
	}

	/**
	 * Stops each named job and schedules it again to run as the running user, for jobs whose
	 * owner was deactivated (ADMIN-12): such a job stops running but keeps its trigger, so it
	 * reads as scheduled. The nightly run and the hourly check are scheduled again by
	 * `scheduleAll`, and the end of a running automation pause by AutomationResumeJob. Returns
	 * the names that are not scheduled afterwards.
	 */
	public static List<String> rescheduleAsRunningUser(List<String> jobNames) {
		Datetime pauseEnds = AutomationControl.pausedUntil();
		for (String name : jobNames) {
			ScheduledJobSelector.stopNamed(name);
		}
		scheduleAll();
		if (jobNames.contains(AutomationResumeJob.JOB_NAME) && pauseEnds != null) {
			AutomationResumeJob.scheduleAt(pauseEnds);
		}
		List<String> stoppedOnly = new List<String>();
		for (String name : jobNames) {
			if (!ScheduledJobSelector.isScheduled(name)) {
				stoppedOnly.add(name);
			}
		}
		return stoppedOnly;
	}

	// -------------------------------------------------------------------------------------
	// Rows
	// -------------------------------------------------------------------------------------

	/** Every row by key (matched as job names are, ignoring case, colons and spacing). */
	public static Map<String, Nightly_Job__c> rows() {
		if (rowsByKey == null) {
			rowsByKey = new Map<String, Nightly_Job__c>();
			for (Nightly_Job__c row : [
				SELECT
					Id,
					Name,
					Switch__c,
					Last_Started__c,
					Last_Finished__c,
					Last_Outcome__c,
					Last_Message__c
				FROM Nightly_Job__c
				WITH SYSTEM_MODE
				ORDER BY CreatedDate
				LIMIT 500
			]) {
				rowsByKey.put(rowKey(row.Name), row);
			}
		}
		return rowsByKey;
	}

	/** The row for this key, made (not saved) when there is none yet. */
	public static Nightly_Job__c rowFor(String key) {
		Nightly_Job__c row = rows().get(rowKey(key));
		if (row == null) {
			row = new Nightly_Job__c(Name = key.left(80));
			rowsByKey.put(rowKey(key), row);
		}
		return row;
	}

	/** Saves rows in system mode; a failure is logged, never thrown, so a run goes on. */
	public static void save(List<Nightly_Job__c> changed) {
		if (changed == null || changed.isEmpty()) {
			return;
		}
		try {
			Database.upsert(changed, true, AccessLevel.SYSTEM_MODE);
		} catch (Exception failed) {
			ErrorLogger.log(failed, ERROR_CONTEXT);
		}
	}

	/** Forgets the rows and steps read, so the next question reads them again. */
	@NamespaceAccessible
	public static void forget() {
		rowsByKey = null;
		builtSteps = null;
	}

	private static String rowKey(String key) {
		return ScheduledJobSelector.nameKey(key);
	}
}
