/**
 * The module's own bookkeeping on Connector Recipe and Connector Run, past sharing (canonical
 * model R-RUN1; ADR-0021; without sharing register). A Flow action queues a run for someone who
 * cannot see the private recipe, and the runner and the recipe clock, as a recipe identity, read
 * and update every recipe and run of their lane. Its own queries and writes touch no other
 * object; the two exceptions are `runInSystemMode` and `pollInSystemMode`, through which only a
 * recipe an admin set to System runs its steps and polls its object. The webhook receiver's
 * Site guest, which has no object access, finds its recipe by token hash and stores a Received
 * run here (R-CR10), and reads its own Error Log warnings to write one an hour.
 */
public without sharing class ConnectorRunStore {
	public static final String QUEUED = 'Queued';
	/** A webhook post stored by the receiver, run as a Queued run is (R-CR10). */
	public static final String RECEIVED = 'Received';
	/** The statuses the runner takes. */
	public static final Set<String> READY = new Set<String>{ QUEUED, RECEIVED };
	public static final String WAITING = 'Waiting';
	public static final String SUCCEEDED = 'Succeeded';
	public static final String SKIPPED = 'Skipped';
	public static final String FAILED = 'Failed';
	public static final String ACTIVE = 'Active';
	public static final String PAUSED = 'Paused';
	public static final String PAUSED_BY_FAILURES = 'PausedByFailures';
	/** The trigger kinds the clock runs (R-CR6). */
	public static final Set<String> CLOCK_KINDS = new Set<String>{ 'Schedule', 'RecordChange' };
	/** Runs the nightly step may delete (R-RUN2). */
	public static final Set<String> FINISHED = new Set<String>{ SUCCEEDED, SKIPPED, FAILED, 'Rejected' };
	public static final Set<String> ALL_RUN_AS = new Set<String>{ 'Automation', 'System', 'IntegrationUser' };
	/** The longest a run's input, state or step log may be (Long Text Area 131072). */
	public static final Integer MAX_TEXT = 131072;
	/** Runs the nightly step deletes at most in one night. */
	public static final Integer MOST_DELETED = 9000;

	/** Every lane's queued runs, oldest first. */
	public static List<Connector_Run__c> queued(Integer most) {
		return queued(most, ALL_RUN_AS, false);
	}

	/**
	 * A lane's queued runs, oldest first, with what the runner needs of their recipes: Test runs,
	 * and runs of Active recipes unless `testsOnly` (paused, R-CR7).
	 */
	public static List<Connector_Run__c> queued(Integer most, Set<String> runAs, Boolean testsOnly) {
		Set<String> runnable = runnableStatuses(testsOnly);
		return [
			SELECT
				Id,
				Name,
				Recipe__c,
				Recipe__r.Name,
				Recipe__r.Definition_JSON__c,
				Recipe__r.Draft_JSON__c,
				Recipe__r.Record_Owner_Id__c,
				Recipe__r.Retry_Attempts__c,
				Status__c,
				Started_By__c,
				Ran_As__c,
				Recipe_Version__c,
				Input_JSON__c,
				State_JSON__c,
				Step_Log_JSON__c,
				Attempt__c,
				Started_At__c,
				Records_Written__c,
				Is_Test__c
			FROM Connector_Run__c
			WHERE
				Status__c IN :READY
				AND Ran_As__c IN :runAs
				AND (Is_Test__c = TRUE
				OR Recipe__r.Status__c IN :runnable)
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
			LIMIT :most
		];
	}

	public static Boolean anyQueued() {
		return anyQueued(ALL_RUN_AS, false);
	}

	public static Boolean anyQueued(Set<String> runAs, Boolean testsOnly) {
		Set<String> runnable = runnableStatuses(testsOnly);
		return [
				SELECT COUNT()
				FROM Connector_Run__c
				WHERE
					Status__c IN :READY
					AND Ran_As__c IN :runAs
					AND (Is_Test__c = TRUE
					OR Recipe__r.Status__c IN :runnable)
				WITH SYSTEM_MODE
				LIMIT 1
			] > 0;
	}

	/** An Active recipe by name, for the Flow action, whoever runs the flow. */
	public static Connector_Recipe__c activeByName(String name) {
		for (Connector_Recipe__c recipe : [
			SELECT Id, Name, Run_As__c, Version__c, Trigger_Kind__c
			FROM Connector_Recipe__c
			WHERE Name = :name AND Status__c = :ACTIVE
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return recipe;
		}
		return null;
	}

	private static Set<String> runnableStatuses(Boolean testsOnly) {
		return testsOnly == true ? new Set<String>() : new Set<String>{ ACTIVE };
	}

	/**
	 * Whether a lane needs its heartbeat (R-CR6): an Active Schedule or Record Change recipe, or a
	 * Waiting or Queued run it may run.
	 */
	public static Boolean clockNeeded(Set<String> runAs) {
		Set<String> open = new Set<String>{ QUEUED, RECEIVED, WAITING };
		return [
				SELECT COUNT()
				FROM Connector_Recipe__c
				WHERE Status__c = :ACTIVE AND Trigger_Kind__c IN :CLOCK_KINDS AND Run_As__c IN :runAs
				WITH SYSTEM_MODE
				LIMIT 1
			] > 0 ||
			[
				SELECT COUNT()
				FROM Connector_Run__c
				WHERE
					Status__c IN :open
					AND Ran_As__c IN :runAs
					AND (Is_Test__c = TRUE
					OR Recipe__r.Status__c = :ACTIVE)
				WITH SYSTEM_MODE
				LIMIT 1
			] > 0;
	}

	/** A lane's Active Schedule and Record Change recipes that are due, most overdue first. */
	public static List<Connector_Recipe__c> due(Set<String> runAs, Datetime now) {
		return [
			SELECT
				Id,
				Name,
				Status__c,
				Run_As__c,
				Version__c,
				Trigger_Kind__c,
				Definition_JSON__c,
				Watermark__c,
				Next_Run_At__c,
				Ignore_Own_Changes__c,
				Consecutive_Failures__c,
				Pause_After_Failures__c
			FROM Connector_Recipe__c
			WHERE
				Status__c = :ACTIVE
				AND Trigger_Kind__c IN :CLOCK_KINDS
				AND Run_As__c IN :runAs
				AND (Next_Run_At__c = NULL
				OR Next_Run_At__c <= :now)
			WITH SYSTEM_MODE
			ORDER BY Next_Run_At__c NULLS FIRST
			LIMIT 50
		];
	}

	/**
	 * Waiting runs whose time has come are queued again (R-CR7): a retry, which has a failed step,
	 * counts an attempt; a run waiting on a Load Rows pass does not (R-CR9).
	 */
	public static void releaseWaiting(Set<String> runAs) {
		Datetime now = Datetime.now();
		List<Connector_Run__c> due = [
			SELECT Id, Attempt__c, Failed_Step__c
			FROM Connector_Run__c
			WHERE Status__c = :WAITING AND Ran_As__c IN :runAs AND Next_Attempt_At__c <= :now
			WITH SYSTEM_MODE
			LIMIT 200
		];
		for (Connector_Run__c run : due) {
			run.Status__c = QUEUED;
			if (run.Failed_Step__c != null) {
				run.Attempt__c = (run.Attempt__c == null ? 0 : run.Attempt__c) + 1;
			}
			run.Failed_Step__c = null;
			run.Next_Attempt_At__c = null;
		}
		update as system due;
	}

	/** The clock's writes for one beat: the runs it started and the recipes it moved on. */
	public static void clockSave(List<Connector_Run__c> runs, List<Connector_Recipe__c> recipes) {
		insert as system runs;
		update as system recipes;
	}

	/**
	 * Inserts Queued runs and publishes each lane's start event after commit; its trigger starts
	 * the runner as that lane's identity (R-CR4), never as the person asking.
	 */
	public static List<Connector_Run__c> queue(List<Connector_Run__c> runs) {
		Set<String> lanes = new Set<String>();
		for (Connector_Run__c run : runs) {
			run.Status__c = QUEUED;
			lanes.add(ConnectorClock.laneOf(run.Ran_As__c));
			if (run.Input_JSON__c != null && run.Input_JSON__c.length() > MAX_TEXT) {
				throw new ConnectorRecipeDocument.DocumentException(
					BarnHelp.text('Connector', 'Connector_Run_ErrorTooLarge')
				);
			}
		}
		insert as system runs;
		ConnectorClock.publish(lanes);
		return runs;
	}

	/**
	 * Saves what the runner did and each finished recipe's Last Run At, and counts failures in a
	 * row (R-CR7): a finished non-test run resets the count or adds one, and a recipe that reaches
	 * its Pause After Failures is Paused by Failures. Returns an Error Log line per paused recipe.
	 */
	public static List<String> save(List<Connector_Run__c> runs, Map<Id, Datetime> lastRuns) {
		update as system runs;
		Map<Id, Connector_Recipe__c> recipes = new Map<Id, Connector_Recipe__c>(
			[
				SELECT Id, Name, Status__c, Consecutive_Failures__c, Pause_After_Failures__c
				FROM Connector_Recipe__c
				WHERE Id IN :lastRuns.keySet()
				WITH SYSTEM_MODE
			]
		);
		List<String> paused = new List<String>();
		for (Connector_Run__c run : runs) {
			Connector_Recipe__c recipe = recipes.get(run.Recipe__c);
			if (recipe != null && run.Is_Test__c != true) {
				count(recipe, run.Status__c, paused);
			}
		}
		for (Id recipeId : lastRuns.keySet()) {
			if (recipes.containsKey(recipeId)) {
				recipes.get(recipeId).Last_Run_At__c = lastRuns.get(recipeId);
			}
		}
		update as system recipes.values();
		return paused;
	}

	private static void count(Connector_Recipe__c recipe, String status, List<String> paused) {
		if (status == SUCCEEDED || status == SKIPPED) {
			recipe.Consecutive_Failures__c = 0;
		} else if (status == FAILED) {
			recipe.Consecutive_Failures__c =
				(recipe.Consecutive_Failures__c == null ? 0 : recipe.Consecutive_Failures__c) + 1;
			if (recipe.Status__c == ACTIVE && recipe.Consecutive_Failures__c >= ConnectorRecipes.pauseAfter(recipe)) {
				recipe.Status__c = PAUSED_BY_FAILURES;
				paused.add(
					BarnHelp.text(
						'Connector',
						'Connector_Log_Paused',
						new List<Object>{ recipe.Name, recipe.Consecutive_Failures__c.intValue() }
					)
				);
			}
		}
	}

	/** Failed runs queued again from their failed steps (R-RUN4); the start events follow. */
	public static void retry(List<Connector_Run__c> runs) {
		Set<String> lanes = new Set<String>();
		for (Connector_Run__c run : runs) {
			run.Status__c = QUEUED;
			run.Attempt__c = (run.Attempt__c == null ? 0 : run.Attempt__c) + 1;
			run.Failed_Step__c = null;
			run.Error_Message__c = null;
			run.Finished_At__c = null;
			run.Next_Attempt_At__c = null;
			lanes.add(ConnectorClock.laneOf(run.Ran_As__c));
		}
		update as system runs;
		ConnectorClock.publish(lanes);
	}

	public static void retry(Connector_Run__c run) {
		retry(new List<Connector_Run__c>{ run });
	}

	/**
	 * A System recipe's steps (R-CR4): the admin chose, with a confirmation, that this recipe skips
	 * object, field and sharing checks, and Health Check lists it. `ConnectorStepRunner` runs every
	 * query and write of such a run in system mode; calling it from here skips sharing too.
	 */
	public static Connector_Run__c runInSystemMode(ConnectorStepRunner steps) {
		return steps.execute();
	}

	/** A System recipe's Record Change poll, past sharing, for the same reason (R-CR6). */
	public static List<Connector_Run__c> pollInSystemMode(ConnectorTriggers poller) {
		return poller.poll();
	}

	/** Marks runs a crashed runner left mid-way as failed, with a plain message (the Finalizer). */
	public static void failStopped(Set<Id> runIds, String message) {
		List<Connector_Run__c> runs = new List<Connector_Run__c>();
		for (Id runId : runIds) {
			runs.add(
				new Connector_Run__c(
					Id = runId,
					Status__c = FAILED,
					Error_Message__c = message.left(1000),
					Finished_At__c = Datetime.now()
				)
			);
		}
		update as system runs;
	}

	/**
	 * The nightly cleanup (R-RUN2): finished runs older than their recipe's Keep Runs Days, at most
	 * 9,000 a night; what is left goes the next night. Returns how many were deleted.
	 */
	public static Integer deleteExpired() {
		Map<Integer, Set<Id>> byDays = new Map<Integer, Set<Id>>();
		for (Connector_Recipe__c recipe : [
			SELECT Id, Keep_Runs_Days__c
			FROM Connector_Recipe__c
			WITH SYSTEM_MODE
			LIMIT 2000
		]) {
			Integer days = ConnectorRecipes.keepDays(recipe);
			if (!byDays.containsKey(days)) {
				byDays.put(days, new Set<Id>());
			}
			byDays.get(days).add(recipe.Id);
		}
		Integer deleted = 0;
		for (Integer days : byDays.keySet()) {
			Integer room = MOST_DELETED - deleted;
			if (room <= 0) {
				break;
			}
			Set<Id> recipeIds = byDays.get(days);
			Datetime cutoff = Datetime.now().addDays(-days);
			List<Connector_Run__c> old = [
				SELECT Id
				FROM Connector_Run__c
				WHERE Recipe__c IN :recipeIds AND CreatedDate < :cutoff AND Status__c IN :FINISHED
				WITH SYSTEM_MODE
				LIMIT :room
			];
			delete as system old;
			deleted += old.size();
		}
		return deleted;
	}

	/** How many runs it may run have waited Queued longer than the minutes given (R-CR8). */
	public static Integer queuedLongerThan(Integer minutes) {
		Datetime before = Datetime.now().addMinutes(-minutes);
		return [
			SELECT COUNT()
			FROM Connector_Run__c
			WHERE
				Status__c IN :READY
				AND LastModifiedDate < :before
				AND (Is_Test__c = TRUE
				OR Recipe__r.Status__c = :ACTIVE)
			WITH SYSTEM_MODE
		];
	}

	// ---------------------------------------------------------------------------------------
	// The webhook receiver (R-CR10): the Site guest has no object access
	// ---------------------------------------------------------------------------------------

	/** A published Webhook recipe by its token hash, or null. */
	public static Connector_Recipe__c webhookRecipe(String tokenHash) {
		for (Connector_Recipe__c recipe : [
			SELECT Id, Name, Run_As__c, Version__c, Definition_JSON__c, Webhook_Hourly_Cap__c
			FROM Connector_Recipe__c
			WHERE
				Webhook_Token_Hash__c = :tokenHash
				AND Trigger_Kind__c = :ConnectorWebhooks.WEBHOOK
				AND Status__c != :ConnectorRecipes.DRAFT
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return recipe;
		}
		return null;
	}

	/** Posts stored for a recipe since a time, counted up to `most`. */
	public static Integer webhookPostsSince(Id recipeId, Datetime since, Integer most) {
		return [
			SELECT COUNT()
			FROM Connector_Run__c
			WHERE Recipe__c = :recipeId AND Started_By__c = :ConnectorWebhooks.WEBHOOK AND CreatedDate > :since
			WITH SYSTEM_MODE
			LIMIT :most
		];
	}

	/** Whether the receiver already wrote an Error Log entry about this recipe since a time. */
	public static Boolean loggedSince(String context, Id recipeId, Datetime since) {
		String reference = String.valueOf(recipeId);
		return [
				SELECT COUNT()
				FROM Error_Log__c
				WHERE Context__c = :context AND Record_Reference__c = :reference AND CreatedDate > :since
				WITH SYSTEM_MODE
				LIMIT 1
			] > 0;
	}

	/**
	 * Stores a Received run. Returns its Reference, or, when its Event Key was stored before (a
	 * resend), the first run's Reference and stores nothing.
	 */
	public static String storeReceived(Connector_Run__c run) {
		Database.SaveResult saved = Database.insert(run, false, AccessLevel.SYSTEM_MODE);
		if (saved.isSuccess()) {
			return run.Reference__c;
		}
		if (run.Event_Key__c == null || saved.getErrors()[0].getStatusCode() != StatusCode.DUPLICATE_VALUE) {
			throw new DmlException(BarnHelp.text('Connector', 'Connector_Log_WebhookStore'));
		}
		for (Connector_Run__c first : [
			SELECT Reference__c
			FROM Connector_Run__c
			WHERE Event_Key__c = :run.Event_Key__c
			WITH SYSTEM_MODE
			LIMIT 1
		]) {
			return first.Reference__c;
		}
		return '';
	}
}
