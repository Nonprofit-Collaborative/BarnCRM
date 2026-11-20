/**
 * The module's own bookkeeping on Connector Recipe and Connector Run, past sharing (canonical
 * model R-RUN1; ADR-0021; without sharing register). A Flow action queues a run for someone who
 * cannot see the private recipe, and the runner, as the Automated Process user, reads and updates
 * every queued run. Its own queries and writes touch no other object; the one exception is
 * `runInSystemMode`, through which only a recipe an admin set to System runs its steps.
 */
public without sharing class ConnectorRunStore {
	public static final String QUEUED = 'Queued';
	public static final String SUCCEEDED = 'Succeeded';
	public static final String SKIPPED = 'Skipped';
	public static final String FAILED = 'Failed';
	public static final String ACTIVE = 'Active';
	/** The longest a run's input, state or step log may be (Long Text Area 131072). */
	public static final Integer MAX_TEXT = 131072;

	/** The queued runs, oldest first, with what the runner needs of their recipes. */
	public static List<Connector_Run__c> queued(Integer most) {
		return [
			SELECT
				Id,
				Name,
				Recipe__c,
				Recipe__r.Name,
				Recipe__r.Definition_JSON__c,
				Recipe__r.Draft_JSON__c,
				Recipe__r.Record_Owner_Id__c,
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
			WHERE Status__c = :QUEUED
			WITH SYSTEM_MODE
			ORDER BY CreatedDate, Id
			LIMIT :most
		];
	}

	public static Boolean anyQueued() {
		return [SELECT COUNT() FROM Connector_Run__c WHERE Status__c = :QUEUED WITH SYSTEM_MODE LIMIT 1] > 0;
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

	/**
	 * Inserts Queued runs and publishes one start event after commit; its trigger starts the
	 * runner as the Automated Process user (R-CR4), never as the person asking.
	 */
	public static List<Connector_Run__c> queue(List<Connector_Run__c> runs) {
		for (Connector_Run__c run : runs) {
			run.Status__c = QUEUED;
			if (run.Input_JSON__c != null && run.Input_JSON__c.length() > MAX_TEXT) {
				throw new ConnectorRecipeDocument.DocumentException(
					BarnHelp.text('Connector', 'Connector_Run_ErrorTooLarge')
				);
			}
		}
		insert as system runs;
		EventBus.publish(new Connector_Start__e());
		return runs;
	}

	/** Saves what the runner did, and each finished recipe's Last Run At. */
	public static void save(List<Connector_Run__c> runs, Map<Id, Datetime> lastRuns) {
		update as system runs;
		List<Connector_Recipe__c> recipes = new List<Connector_Recipe__c>();
		for (Id recipeId : lastRuns.keySet()) {
			recipes.add(new Connector_Recipe__c(Id = recipeId, Last_Run_At__c = lastRuns.get(recipeId)));
		}
		update as system recipes;
	}

	/** A failed run queued again from its failed step (R-RUN4); the start event follows. */
	public static void retry(Connector_Run__c run) {
		run.Status__c = QUEUED;
		run.Attempt__c = (run.Attempt__c == null ? 0 : run.Attempt__c) + 1;
		run.Failed_Step__c = null;
		run.Error_Message__c = null;
		run.Finished_At__c = null;
		update as system run;
		EventBus.publish(new Connector_Start__e());
	}

	/**
	 * A System recipe's steps (R-CR4): the admin chose, with a confirmation, that this recipe skips
	 * object, field and sharing checks, and Health Check lists it. `ConnectorStepRunner` runs every
	 * query and write of such a run in system mode; calling it from here skips sharing too.
	 */
	public static Connector_Run__c runInSystemMode(ConnectorStepRunner steps) {
		return steps.execute();
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
}
