/**
 * Recipes and their runs on Super Connector (canonical model 29CN2, 29CN3, R-CR1 to R-CR5,
 * R-RUN4; design Sections 3.7, 3.8 and 3.10). Only Connector admins (Manage BarnCRM Connector)
 * save, publish, run, test, retry, delete and set Run As (R-CR3); Connector viewers read.
 * Recipes are read and written as the admin, in user mode; runs are written only through
 * `ConnectorRunStore` (R-RUN1).
 */
public with sharing class ConnectorRecipes {
	public static final String RUN_AS_AUTOMATION = 'Automation';
	public static final String RUN_AS_SYSTEM = 'System';
	public static final String RUN_AS_USER = 'IntegrationUser';
	public static final String DRAFT = 'Draft';
	public static final String MANUAL = 'Manual';
	public static final String SCHEDULE = 'Schedule';
	public static final String RECORD_CHANGE = 'RecordChange';
	public static final Integer MAX_RUNS = 50;
	/** Failed runs Retry All Failed queues at once. */
	public static final Integer MAX_RETRIED = 200;
	private static final Map<String, String> KIND_BY_TRIGGER = new Map<String, String>{
		'manual' => MANUAL,
		'schedule' => SCHEDULE,
		'record' => RECORD_CHANGE,
		'webhook' => ConnectorWebhooks.WEBHOOK,
		'appPoll' => ConnectorAppPoll.APP_POLL
	};

	/** Pause After Failures, 1 to 100; blank or out of range is 10 (R-CR7). */
	public static Integer pauseAfter(Connector_Recipe__c recipe) {
		return bounded(recipe?.Pause_After_Failures__c, 1, 100, 10);
	}

	/** Retry Attempts, 0 to 4; blank or out of range is 3 (R-CR7). */
	public static Integer retryAttempts(Connector_Recipe__c recipe) {
		return bounded(recipe?.Retry_Attempts__c, 0, 4, 3);
	}

	/** Keep Runs Days, 7 to 365; blank or out of range is 30 (R-RUN2). */
	public static Integer keepDays(Connector_Recipe__c recipe) {
		return bounded(recipe?.Keep_Runs_Days__c, 7, 365, 30);
	}

	private static Integer bounded(Decimal value, Integer least, Integer most, Integer otherwise) {
		return value == null || value < least || value > most ? otherwise : value.intValue();
	}

	/** The Trigger Kind a document's trigger is listed under. */
	public static String kindOf(Map<String, Object> document) {
		String kind = KIND_BY_TRIGGER.get(
			ConnectorRecipeDocument.textOf(ConnectorRecipeDocument.mapOf(document.get('trigger')).get('kind'))
		);
		return kind == null ? MANUAL : kind;
	}

	/** One recipe in the list and the editor. */
	public class Recipe {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String description;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String runAs;
		@AuraEnabled
		public String runAsChosenBy;
		@AuraEnabled
		public Datetime runAsChosenAt;
		@AuraEnabled
		public Integer version;
		@AuraEnabled
		public Datetime lastRunAt;
		/** True when the draft differs from what is published. */
		@AuraEnabled
		public Boolean unpublished;
		@AuraEnabled
		public String draftJson;
		@AuraEnabled
		public String recordOwnerId;
		@AuraEnabled
		public String triggerKind;
		@AuraEnabled
		public Datetime nextRunAt;
		@AuraEnabled
		public Integer retryAttempts;
		@AuraEnabled
		public Integer pauseAfterFailures;
		@AuraEnabled
		public Integer keepRunsDays;
		@AuraEnabled
		public Boolean ignoreOwnChanges;
		@AuraEnabled
		public Integer consecutiveFailures;
		/** True while the definition before the last Publish is kept, for Roll Back (R-CR13). */
		@AuraEnabled
		public Boolean canRollBack;
		/** True once published: Discard Draft Changes has a definition to go back to. */
		@AuraEnabled
		public Boolean published;
	}

	/** A saved map or saved query a step can use. */
	public class Option {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;
		/** For a map, `record` or `json`; for a query, its object. */
		@AuraEnabled
		public String kind;
		/** For a query, its document, copied into a Find step. */
		@AuraEnabled
		public String document;
	}

	/** The Recipes section. */
	public class RecipesPage {
		@AuraEnabled
		public Boolean canManage;
		/** Whether an active integration user is chosen (Run As Integration User may be set). */
		@AuraEnabled
		public Boolean integrationUserReady;
		@AuraEnabled
		public List<Recipe> recipes = new List<Recipe>();
		@AuraEnabled
		public List<Option> connections = new List<Option>();
		@AuraEnabled
		public List<Option> maps = new List<Option>();
		@AuraEnabled
		public List<Option> queries = new List<Option>();
		/** Active Super Importer templates a Load Rows step can use (R-CR9). */
		@AuraEnabled
		public List<Option> templates = new List<Option>();
	}

	/** One run in Run History, with its steps when opened. */
	public class Run {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String recipeId;
		@AuraEnabled
		public String recipeName;
		@AuraEnabled
		public String status;
		@AuraEnabled
		public String startedBy;
		@AuraEnabled
		public String ranAs;
		@AuraEnabled
		public Integer version;
		@AuraEnabled
		public Datetime createdAt;
		@AuraEnabled
		public Datetime finishedAt;
		@AuraEnabled
		public Integer recordsWritten;
		@AuraEnabled
		public String failedStep;
		@AuraEnabled
		public String errorMessage;
		@AuraEnabled
		public Boolean isTest;
		@AuraEnabled
		public Integer attempt;
		/** When a Waiting run is tried again (R-CR7). */
		@AuraEnabled
		public Datetime nextAttemptAt;
		/** A webhook run's reference, as its app was given it (R-CR10). */
		@AuraEnabled
		public String reference;
		/** Opened only: the step log and, for a Test run, what each step would have done. */
		@AuraEnabled
		public String stepLogJson;
		@AuraEnabled
		public String resultsJson;
	}

	// ---------------------------------------------------------------------------------------
	// Reading
	// ---------------------------------------------------------------------------------------

	public static void requireViewer() {
		if (!Schema.SObjectType.Connector_Recipe__c.isAccessible()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Error_NoView'));
		}
	}

	public static RecipesPage page() {
		requireViewer();
		RecipesPage result = new RecipesPage();
		result.canManage = ConnectorConnections.canManage();
		result.integrationUserReady = ConnectorIntegrationUser.ready();
		for (Connector_Recipe__c row : [
			SELECT
				Id,
				Name,
				Description__c,
				Status__c,
				Run_As__c,
				Run_As_Chosen_By__r.Name,
				Run_As_Chosen_At__c,
				Version__c,
				Last_Run_At__c,
				Definition_JSON__c,
				Draft_JSON__c,
				Record_Owner_Id__c,
				Trigger_Kind__c,
				Next_Run_At__c,
				Retry_Attempts__c,
				Pause_After_Failures__c,
				Keep_Runs_Days__c,
				Ignore_Own_Changes__c,
				Consecutive_Failures__c,
				Previous_JSON__c
			FROM Connector_Recipe__c
			WITH USER_MODE
			ORDER BY Name
			LIMIT 500
		]) {
			result.recipes.add(shown(row));
		}
		if (result.canManage) {
			for (ConnectorConnections.Connection connection : ConnectorConnections.page().connections) {
				result.connections.add(option(connection.name, connection.label, connection.host, null));
			}
			for (Saved_Transform__c row : [
				SELECT Id, Name, Object_Name__c, Definition_JSON__c
				FROM Saved_Transform__c
				WHERE Kind__c = :ConnectorMapRuntime.KIND_MAP
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				Map<String, Object> document = ConnectorRecipeDocument.mapOf(parsedOrNull(row.Definition_JSON__c));
				String target = String.isBlank(ConnectorMapRuntime.objectOf(document)) ? 'json' : 'record';
				result.maps.add(option(row.Id, row.Name, target, null));
			}
			for (Saved_Query__c row : [
				SELECT Id, Name, Object_Name__c, Query_JSON__c
				FROM Saved_Query__c
				WITH USER_MODE
				ORDER BY Name
				LIMIT 500
			]) {
				result.queries.add(option(row.Id, row.Name, row.Object_Name__c, row.Query_JSON__c));
			}
			List<Import_Template__c> templates = Schema.SObjectType.Import_Template__c.isAccessible()
				? ImportTemplateSelector.selectActive()
				: new List<Import_Template__c>();
			for (Import_Template__c row : templates) {
				if (ImportObjectSchema.operationOf(row) != ImportObjectSchema.OPERATION_DELETE) {
					result.templates.add(option(row.Id, row.Name, null, null));
				}
			}
		}
		return result;
	}

	private static Option option(String value, String label, String kind, String document) {
		Option result = new Option();
		result.value = value;
		result.label = label;
		result.kind = kind;
		result.document = document;
		return result;
	}

	private static Recipe shown(Connector_Recipe__c row) {
		Recipe result = new Recipe();
		result.id = row.Id;
		result.name = row.Name;
		result.description = row.Description__c;
		result.status = row.Status__c;
		result.runAs = row.Run_As__c;
		result.runAsChosenBy = row.Run_As_Chosen_By__r?.Name;
		result.runAsChosenAt = row.Run_As_Chosen_At__c;
		result.version = row.Version__c == null ? 0 : row.Version__c.intValue();
		result.lastRunAt = row.Last_Run_At__c;
		result.unpublished = row.Draft_JSON__c != row.Definition_JSON__c;
		result.draftJson = row.Draft_JSON__c;
		result.recordOwnerId = row.Record_Owner_Id__c;
		result.triggerKind = row.Trigger_Kind__c;
		result.nextRunAt = row.Next_Run_At__c;
		result.retryAttempts = retryAttempts(row);
		result.pauseAfterFailures = pauseAfter(row);
		result.keepRunsDays = keepDays(row);
		result.ignoreOwnChanges = row.Ignore_Own_Changes__c != false;
		result.consecutiveFailures = row.Consecutive_Failures__c == null ? 0 : row.Consecutive_Failures__c.intValue();
		result.canRollBack = String.isNotBlank(row.Previous_JSON__c);
		result.published = String.isNotBlank(row.Definition_JSON__c);
		return result;
	}

	private static Connector_Recipe__c recipe(Id recipeId) {
		List<Connector_Recipe__c> rows = [
			SELECT
				Id,
				Name,
				Status__c,
				Run_As__c,
				Version__c,
				Definition_JSON__c,
				Draft_JSON__c,
				Record_Owner_Id__c,
				Trigger_Kind__c,
				Watermark__c,
				Previous_JSON__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty()) {
			throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Recipe_ErrorGone'));
		}
		return rows[0];
	}

	// ---------------------------------------------------------------------------------------
	// Saving, publishing, Run As, deleting (R-CR1 to R-CR4)
	// ---------------------------------------------------------------------------------------

	/** Saves a new recipe (no Id) or a recipe's draft, checked as a save is (R-CR1). */
	public static Recipe saveDraft(Id recipeId, String name, String description, String draftJson, String ownerId) {
		ConnectorConnections.requireManager();
		String checkedName = ConnectorConnections.checkedLabel(name);
		// Not named "draft": Apex names are case-insensitive, so it would hide the DRAFT status.
		Map<String, Object> document = ConnectorRecipeDocument.parse(draftJson);
		refuseProblems(ConnectorRecipeDocument.problems(document));
		if (String.isNotBlank(description) && description.contains('{!')) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorMergeField')
			);
		}
		if (
			[SELECT COUNT() FROM Connector_Recipe__c WHERE Name = :checkedName AND Id != :recipeId WITH SYSTEM_MODE] > 0
		) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorNameTaken')
			);
		}
		String owner = String.isBlank(ownerId) ? null : ownerId.trim();
		if (
			owner != null &&
			(!ConnectorRecipeDocument.isId(owner) ||
			[SELECT COUNT() FROM User WHERE Id = :owner AND IsActive = TRUE WITH SYSTEM_MODE] == 0)
		) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorOwner')
			);
		}
		Connector_Recipe__c stored = recipeId == null ? null : recipe(recipeId);
		Connector_Recipe__c row = recipeId == null
			? new Connector_Recipe__c(Status__c = DRAFT, Run_As__c = RUN_AS_AUTOMATION, Version__c = 0)
			: new Connector_Recipe__c(Id = stored.Id);
		row.Name = checkedName;
		row.Description__c = description;
		row.Draft_JSON__c = draftJson;
		// The clock reads Trigger Kind, so a published recipe keeps its definition's until Publish.
		if (stored == null || String.isBlank(stored.Definition_JSON__c)) {
			row.Trigger_Kind__c = kindOf(document);
		}
		row.Record_Owner_Id__c = owner == null ? null : String.valueOf(Id.valueOf(owner));
		if (recipeId == null) {
			row.Run_As_Chosen_By__c = UserInfo.getUserId();
			row.Run_As_Chosen_At__c = Datetime.now();
			Database.insert(row, AccessLevel.USER_MODE);
		} else {
			Database.update(row, AccessLevel.USER_MODE);
		}
		return shown(reread(row.Id));
	}

	/**
	 * Publishes the draft (R-CR2): checked again, its connections ready, its maps present and of
	 * the right kind, its Find steps compiled as the publisher, and, for BarnCRM Automation, its
	 * record maps checked against the identity's access. Then Definition takes the draft, Version
	 * goes up and the recipe is Active.
	 */
	public static Recipe publish(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		return makeLive(row, row.Draft_JSON__c);
	}

	/**
	 * Roll Back (R-CR13): the definition before the last Publish, checked as Publish checks a
	 * draft, swaps with the published one and the version goes up; the draft is left alone.
	 */
	public static Recipe rollBack(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		if (String.isBlank(row.Previous_JSON__c)) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorNoPrevious')
			);
		}
		return makeLive(row, row.Previous_JSON__c);
	}

	/** Discard Draft Changes (R-CR13): the draft starts again from the published definition. */
	public static Recipe discardDraft(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		if (String.isBlank(row.Definition_JSON__c)) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorNotPublished')
			);
		}
		Database.update(
			new Connector_Recipe__c(Id = row.Id, Draft_JSON__c = row.Definition_JSON__c),
			AccessLevel.USER_MODE
		);
		return shown(reread(row.Id));
	}

	/**
	 * Makes a definition the published one: checked (R-CR2), the one it replaces kept as Previous
	 * Definition (R-CR13), the version up, the recipe Active and its clock started.
	 */
	private static Recipe makeLive(Connector_Recipe__c row, String source) {
		Map<String, Object> document = ConnectorRecipeDocument.parse(source);
		refuseProblems(publishProblems(document, row.Run_As__c));
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		Connector_Recipe__c published = new Connector_Recipe__c(
			Id = row.Id,
			Definition_JSON__c = source,
			Previous_JSON__c = source == row.Definition_JSON__c ? row.Previous_JSON__c : row.Definition_JSON__c,
			Version__c = (row.Version__c == null ? 0 : row.Version__c) + 1,
			Status__c = ConnectorRunStore.ACTIVE,
			Trigger_Kind__c = kindOf(document)
		);
		started(
			published,
			published.Trigger_Kind__c,
			starter,
			String.isBlank(row.Definition_JSON__c) ||
				String.isBlank(row.Watermark__c) ||
				row.Trigger_Kind__c != published.Trigger_Kind__c ||
				watchedObject(ConnectorRecipeDocument.parse(row.Definition_JSON__c)) != watchedObject(document)
		);
		Database.update(published, AccessLevel.USER_MODE);
		if (ConnectorRunStore.CLOCK_KINDS.contains(published.Trigger_Kind__c)) {
			ConnectorClock.publish(new Set<String>{ ConnectorClock.laneOf(row.Run_As__c) });
		}
		return shown(reread(row.Id));
	}

	/**
	 * Every problem Publish refuses (R-CR2): the save checks, each connection ready, a Record
	 * Change query, and each step's map, query or template against the identity's access. Import
	 * shows the same list as what to fix before Publish (R-CR13).
	 */
	public static List<String> publishProblems(Map<String, Object> document, String runAs) {
		List<String> found = ConnectorRecipeDocument.problems(document);
		Map<String, ConnectorConnections.Connection> ready = new Map<String, ConnectorConnections.Connection>();
		for (ConnectorConnections.Connection connection : ConnectorConnections.page().connections) {
			ready.put(connection.name, connection);
		}
		for (String name : ConnectorRecipeDocument.connections(document)) {
			ConnectorConnections.Connection connection = ready.get(name);
			if (connection == null || !connection.keyStored || !connection.calloutsEnabled) {
				found.add(BarnHelp.text('Connector', 'Connector_Publish_Connection', new List<Object>{ name }));
			}
		}
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		if (ConnectorRecipeDocument.textOf(starter.get('kind')) == 'record') {
			String problem = ConnectorTriggers.publishProblem(starter);
			if (problem != null) {
				found.add(problem);
			}
		}
		Id identity = identityFor(runAs);
		for (Map<String, Object> step : ConnectorRecipeDocument.allSteps(document)) {
			found.addAll(stepPublishProblems(step, runAs, identity));
		}
		return found;
	}

	/** The object a Record Change trigger watches, or blank for any other trigger. */
	private static String watchedObject(Map<String, Object> document) {
		Map<String, Object> starter = ConnectorRecipeDocument.mapOf(document.get('trigger'));
		return ConnectorRecipeDocument.textOf(ConnectorRecipeDocument.mapOf(starter.get('query')).get('object'));
	}

	/**
	 * The clock's starting point for a Schedule or Record Change recipe (R-CR6): its next time,
	 * and for Record Change a Watermark at now when it has none, its trigger kind changed or it
	 * watches another object, so
	 * the first poll looks only at changes from here on. The caller publishes the lane's start
	 * event, so the heartbeat starts after commit.
	 */
	private static void started(Connector_Recipe__c row, String kind, Map<String, Object> starter, Boolean fresh) {
		Datetime now = Datetime.now();
		if (kind == SCHEDULE) {
			row.Next_Run_At__c = ConnectorTriggers.nextAt(starter, now);
		} else if (kind == RECORD_CHANGE) {
			row.Next_Run_At__c = now;
			if (fresh) {
				row.Watermark__c = ConnectorTriggers.watermark(now, null);
			}
		} else if (kind == ConnectorAppPoll.APP_POLL) {
			// The first poll sets the Watermark from the app's newest item (CN-13).
			row.Next_Run_At__c = now;
			if (fresh) {
				row.Watermark__c = null;
			}
		}
	}

	/** The user whose permission sets a recipe's Publish checks are made against (R-CR2). */
	private static Id identityFor(String runAs) {
		if (runAs != RUN_AS_USER) {
			return ConnectorIdentity.automatedProcessId();
		}
		if (!ConnectorIntegrationUser.ready()) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorNoUser')
			);
		}
		return ConnectorIntegrationUser.chosenId();
	}

	/** One step's Publish checks: its map and its Find query (R-CR2). */
	private static List<String> stepPublishProblems(Map<String, Object> step, String runAs, Id identity) {
		List<String> found = new List<String>();
		String kind = ConnectorRecipeDocument.textOf(step.get('kind'));
		String id = ConnectorRecipeDocument.textOf(step.get('id'));
		try {
			if (kind == 'find') {
				QueryCompiler.compile(JSON.serialize(step.get('query')));
			}
			if (kind == 'importRows') {
				return String.isBlank(ConnectorRecipeDocument.textOf(step.get('template')))
					? found
					: importProblems(step, id, identity);
			}
			Boolean calls = ConnectorRecipeDocument.CALL_KINDS.contains(kind);
			String mapId = ConnectorRecipeDocument.textOf(step.get(calls ? 'bodyMap' : 'map'));
			if (String.isBlank(mapId)) {
				return found;
			}
			ConnectorMapRuntime.SavedMap saved = ConnectorMapRuntime.load(mapId, AccessLevel.USER_MODE);
			String objectName = ConnectorMapRuntime.objectOf(saved.document);
			Boolean wantsRecord = !calls && kind != 'transform';
			if (wantsRecord == String.isBlank(objectName)) {
				found.add(BarnHelp.text('Connector', 'Connector_Publish_MapKind', new List<Object>{ id, saved.name }));
				return found;
			}
			if (JSON.serialize(saved.document).contains('{!')) {
				found.add(
					BarnHelp.text('Connector', 'Connector_Publish_MapMergeField', new List<Object>{ saved.name })
				);
			}
			String matchBy = ConnectorRecipeDocument.textOf(
				ConnectorRecipeDocument.mapOf(saved.document.get('match')).get('by')
			);
			if (kind == 'upsert' && matchBy != 'id' && matchBy != 'field' && matchBy != 'externalId') {
				found.add(BarnHelp.text('Connector', 'Connector_Publish_MapMatch', new List<Object>{ id, saved.name }));
			}
			if (wantsRecord && runAs != RUN_AS_SYSTEM) {
				List<String> fields = new List<String>();
				for (Object raw : ConnectorRecipeDocument.listOf(saved.document.get('columns'))) {
					fields.add(
						ConnectorRecipeDocument.textOf(ConnectorRecipeDocument.mapOf(raw).get('target'))
							.removeStart('Record.')
					);
				}
				found.addAll(ConnectorIdentity.mapProblems(identity, kind, objectName, fields));
			}
		} catch (Exception refused) {
			found.add(id + ': ' + refused.getMessage());
		}
		return found;
	}

	/**
	 * A Load Rows step's Publish checks (R-CR9): its template active and seen by the publisher, not
	 * a delete by file, and the identity able to create data jobs, since Super Importer stages and
	 * commits in user mode whatever the recipe's access mode.
	 */
	private static List<String> importProblems(Map<String, Object> step, String stepName, Id identity) {
		List<String> found = new List<String>();
		Import_Template__c template = ImportTemplateSelector.selectById(
			(Id) ConnectorRecipeDocument.textOf(step.get('template'))
		);
		if (
			template == null ||
			template.Active__c != true ||
			ImportObjectSchema.operationOf(template) == ImportObjectSchema.OPERATION_DELETE
		) {
			found.add(BarnHelp.text('Connector', 'Connector_Publish_Template', new List<Object>{ stepName }));
			return found;
		}
		found.addAll(
			ConnectorIdentity.mapProblems(
				identity,
				'create',
				Import_Batch__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).getName(),
				new List<String>()
			)
		);
		return found;
	}

	/** Sets Run As (R-CR4): System only with the confirmation; who and when are recorded. */
	public static Recipe setRunAs(Id recipeId, String runAs, Boolean confirmed) {
		ConnectorConnections.requireManager();
		if (runAs != RUN_AS_AUTOMATION && runAs != RUN_AS_SYSTEM && runAs != RUN_AS_USER) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorChoice')
			);
		}
		if (runAs == RUN_AS_USER && !ConnectorIntegrationUser.ready()) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorNoUser')
			);
		}
		if (runAs == RUN_AS_SYSTEM && confirmed != true) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorConfirm')
			);
		}
		Connector_Recipe__c row = recipe(recipeId);
		Database.update(
			new Connector_Recipe__c(
				Id = row.Id,
				Run_As__c = runAs,
				Run_As_Chosen_By__c = UserInfo.getUserId(),
				Run_As_Chosen_At__c = Datetime.now()
			),
			AccessLevel.USER_MODE
		);
		if (row.Status__c == ConnectorRunStore.ACTIVE) {
			// The recipe moves to the other lane's clock.
			ConnectorClock.publish(new Set<String>{ ConnectorClock.laneOf(runAs) });
		}
		return shown(reread(row.Id));
	}

	/**
	 * Saves a recipe's run settings (R-CR6, R-CR7, R-RUN2): Retry Attempts 0 to 4, Pause After
	 * Failures 1 to 100, Keep Runs Days 7 to 365 and Ignore Own Changes.
	 */
	public static Recipe saveSettings(
		Id recipeId,
		Integer retries,
		Integer pauseAfterFailures,
		Integer keepRunsDays,
		Boolean ignoreOwnChanges
	) {
		ConnectorConnections.requireManager();
		if (
			retries == null ||
			retries < 0 ||
			retries > 4 ||
			pauseAfterFailures == null ||
			pauseAfterFailures < 1 ||
			pauseAfterFailures > 100 ||
			keepRunsDays == null ||
			keepRunsDays < 7 ||
			keepRunsDays > 365
		) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Settings_ErrorRange')
			);
		}
		Connector_Recipe__c row = recipe(recipeId);
		Database.update(
			new Connector_Recipe__c(
				Id = row.Id,
				Retry_Attempts__c = retries,
				Pause_After_Failures__c = pauseAfterFailures,
				Keep_Runs_Days__c = keepRunsDays,
				Ignore_Own_Changes__c = ignoreOwnChanges != false
			),
			AccessLevel.USER_MODE
		);
		return shown(reread(row.Id));
	}

	/** Pauses an Active recipe (R-CR7): it neither polls nor runs; its queued runs wait. */
	public static Recipe pause(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		if (row.Status__c != ConnectorRunStore.ACTIVE) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorNotActive')
			);
		}
		Database.update(
			new Connector_Recipe__c(Id = row.Id, Status__c = ConnectorRunStore.PAUSED),
			AccessLevel.USER_MODE
		);
		return shown(reread(row.Id));
	}

	/**
	 * Resumes a Paused or Paused by Failures recipe (R-CR7): its failures in a row start again
	 * from 0, a schedule takes its next time, a Record Change carries on from its Watermark, and
	 * its lane's runner and clock start.
	 */
	public static Recipe resume(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		if (row.Status__c != ConnectorRunStore.PAUSED && row.Status__c != ConnectorRunStore.PAUSED_BY_FAILURES) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Recipe_ErrorNotPaused')
			);
		}
		Connector_Recipe__c resumed = new Connector_Recipe__c(
			Id = row.Id,
			Status__c = ConnectorRunStore.ACTIVE,
			Consecutive_Failures__c = 0
		);
		started(
			resumed,
			row.Trigger_Kind__c,
			ConnectorRecipeDocument.mapOf(ConnectorRecipeDocument.parse(row.Definition_JSON__c).get('trigger')),
			String.isBlank(row.Watermark__c)
		);
		Database.update(resumed, AccessLevel.USER_MODE);
		// Runs that waited while it was paused start now.
		ConnectorClock.publish(new Set<String>{ ConnectorClock.laneOf(row.Run_As__c) });
		return shown(reread(row.Id));
	}

	public static void remove(Id recipeId) {
		ConnectorConnections.requireManager();
		Database.delete(recipe(recipeId), AccessLevel.USER_MODE);
	}

	/**
	 * Whether any recipe's definition or draft names the connection (R-CN8). Long text cannot be
	 * filtered in SOQL, so each recipe is read; an org keeps tens of recipes, not thousands.
	 */
	public static Boolean connectionInUse(String name) {
		String quoted = '"' + name + '"';
		for (Connector_Recipe__c row : [
			SELECT Definition_JSON__c, Draft_JSON__c
			FROM Connector_Recipe__c
			WITH SYSTEM_MODE
			LIMIT 2000
		]) {
			if (
				(row.Definition_JSON__c != null && row.Definition_JSON__c.contains(quoted)) ||
				(row.Draft_JSON__c != null && row.Draft_JSON__c.contains(quoted))
			) {
				return true;
			}
		}
		return false;
	}

	// ---------------------------------------------------------------------------------------
	// Run Now, Test, Run History, Retry (R-CR4, R-CR5, R-RUN4)
	// ---------------------------------------------------------------------------------------

	/** Queues a run of the published recipe with the pasted JSON (blank is `{}`). */
	public static Run runNow(Id recipeId, String inputJson) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		if (row.Status__c != ConnectorRunStore.ACTIVE || String.isBlank(row.Definition_JSON__c)) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorNotActive')
			);
		}
		Object input = String.isBlank(inputJson) ? new Map<String, Object>() : sample(inputJson);
		return queued(row, MANUAL, JSON.serialize(input), false);
	}

	/**
	 * Queues a Test of the draft (R-CR5) on a pasted JSON sample, or on `{ "recordId" }` when a
	 * record Id is given; `sendForReal` lets methods other than GET call the app.
	 */
	public static Run test(Id recipeId, String sampleJson, String recordId, Boolean sendForReal) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		ConnectorRecipeDocument.parse(row.Draft_JSON__c);
		Object chosen;
		if (String.isNotBlank(recordId)) {
			if (!ConnectorRecipeDocument.isId(recordId.trim())) {
				throw new ConnectorConnections.ConnectorException(
					BarnHelp.text('Connector', 'Connector_Test_ErrorRecordId')
				);
			}
			chosen = new Map<String, Object>{ 'recordId' => Id.valueOf(recordId.trim()) };
		} else {
			chosen = String.isBlank(sampleJson) ? new Map<String, Object>() : sample(sampleJson);
		}
		Map<String, Object> wrapper = new Map<String, Object>{
			'sample' => chosen,
			'sendForReal' => sendForReal == true
		};
		return queued(row, 'Test', JSON.serialize(wrapper), true);
	}

	private static Object sample(String source) {
		Object parsed;
		try {
			parsed = JSON.deserializeUntyped(source);
		} catch (Exception unreadable) {
			parsed = null; // Refused below.
		}
		if (parsed instanceof Map<String, Object> || parsed instanceof List<Object>) {
			return parsed;
		}
		throw new ConnectorConnections.ConnectorException(BarnHelp.text('Connector', 'Connector_Run_ErrorInput'));
	}

	/** A Run Now or Test run; an Integration User recipe needs its user ready, or it never runs. */
	private static Run queued(Connector_Recipe__c row, String startedBy, String inputJson, Boolean isTest) {
		if (row.Run_As__c == RUN_AS_USER && !ConnectorIntegrationUser.ready()) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_RunAs_ErrorNoUser')
			);
		}
		Connector_Run__c run = new Connector_Run__c(
			Recipe__c = row.Id,
			Started_By__c = startedBy,
			Ran_As__c = row.Run_As__c,
			Recipe_Version__c = row.Version__c == null ? 0 : row.Version__c,
			Input_JSON__c = inputJson,
			Is_Test__c = isTest
		);
		ConnectorRunStore.queue(new List<Connector_Run__c>{ run });
		return runs(row.Id, run.Id)[0];
	}

	/** The latest runs, of one recipe or all, newest first; with `runId`, that run opened. */
	public static List<Run> runs(Id recipeId, Id runId) {
		requireViewer();
		String query =
			'SELECT Id, Name, Recipe__c, Recipe__r.Name, Status__c, Started_By__c, Ran_As__c, ' +
			'Recipe_Version__c, CreatedDate, Finished_At__c, Records_Written__c, Failed_Step__c, ' +
			'Error_Message__c, Is_Test__c, Attempt__c, Next_Attempt_At__c, Reference__c' +
			(runId == null ? '' : ', Step_Log_JSON__c, State_JSON__c') +
			' FROM Connector_Run__c' +
			(runId != null ? ' WHERE Id = :runId' : (recipeId != null ? ' WHERE Recipe__c = :recipeId' : '')) +
			' ORDER BY CreatedDate DESC, Id DESC LIMIT :most';
		Map<String, Object> binds = new Map<String, Object>{ 'most' => MAX_RUNS };
		if (runId != null) {
			binds.put('runId', runId);
		} else if (recipeId != null) {
			binds.put('recipeId', recipeId);
		}
		List<Run> found = new List<Run>();
		for (
			Connector_Run__c row : (List<Connector_Run__c>) Database.queryWithBinds(query, binds, AccessLevel.USER_MODE)
		) {
			found.add(shown(row, runId != null));
		}
		return found;
	}

	private static Run shown(Connector_Run__c row, Boolean opened) {
		Run result = new Run();
		result.id = row.Id;
		result.name = row.Name;
		result.recipeId = row.Recipe__c;
		result.recipeName = row.Recipe__r.Name;
		result.status = row.Status__c;
		result.startedBy = row.Started_By__c;
		result.ranAs = row.Ran_As__c;
		result.version = row.Recipe_Version__c == null ? 0 : row.Recipe_Version__c.intValue();
		result.createdAt = row.CreatedDate;
		result.finishedAt = row.Finished_At__c;
		result.recordsWritten = row.Records_Written__c == null ? 0 : row.Records_Written__c.intValue();
		result.failedStep = row.Failed_Step__c;
		result.errorMessage = row.Error_Message__c;
		result.isTest = row.Is_Test__c;
		result.attempt = row.Attempt__c == null ? 0 : row.Attempt__c.intValue();
		result.nextAttemptAt = row.Next_Attempt_At__c;
		result.reference = row.Reference__c;
		if (opened) {
			result.stepLogJson = row.Step_Log_JSON__c;
			// A Test run shows what each step would have written or sent (R-CR5).
			result.resultsJson = row.Is_Test__c == true
				? JSON.serialize(ConnectorRecipeDocument.mapOf(parsedOrNull(row.State_JSON__c)).get('steps'))
				: null;
		}
		return result;
	}

	/** Queues a failed run again from its failed step (R-RUN4). */
	public static Run retry(Id runId) {
		ConnectorConnections.requireManager();
		List<Connector_Run__c> rows = [
			SELECT Id, Recipe__c, Status__c, Attempt__c, Is_Test__c, Ran_As__c
			FROM Connector_Run__c
			WHERE Id = :runId
			WITH USER_MODE
			LIMIT 1
		];
		if (rows.isEmpty() || rows[0].Status__c != ConnectorRunStore.FAILED) {
			throw new ConnectorConnections.ConnectorException(
				BarnHelp.text('Connector', 'Connector_Run_ErrorNotFailed')
			);
		}
		ConnectorRunStore.retry(rows[0]);
		return runs(null, runId)[0];
	}

	/** Queues every Failed run of a recipe again from its failed step, at most 200; returns how many. */
	public static Integer retryAllFailed(Id recipeId) {
		ConnectorConnections.requireManager();
		Connector_Recipe__c row = recipe(recipeId);
		List<Connector_Run__c> failed = [
			SELECT Id, Recipe__c, Status__c, Attempt__c, Is_Test__c, Ran_As__c
			FROM Connector_Run__c
			WHERE Recipe__c = :row.Id AND Status__c = :ConnectorRunStore.FAILED AND Is_Test__c = FALSE
			WITH USER_MODE
			ORDER BY CreatedDate
			LIMIT :MAX_RETRIED
		];
		if (!failed.isEmpty()) {
			ConnectorRunStore.retry(failed);
		}
		return failed.size();
	}

	// ---------------------------------------------------------------------------------------
	// Helpers
	// ---------------------------------------------------------------------------------------

	private static Connector_Recipe__c reread(Id recipeId) {
		return [
			SELECT
				Id,
				Name,
				Description__c,
				Status__c,
				Run_As__c,
				Run_As_Chosen_By__r.Name,
				Run_As_Chosen_At__c,
				Version__c,
				Last_Run_At__c,
				Definition_JSON__c,
				Draft_JSON__c,
				Record_Owner_Id__c,
				Trigger_Kind__c,
				Next_Run_At__c,
				Retry_Attempts__c,
				Pause_After_Failures__c,
				Keep_Runs_Days__c,
				Ignore_Own_Changes__c,
				Consecutive_Failures__c,
				Previous_JSON__c
			FROM Connector_Recipe__c
			WHERE Id = :recipeId
			WITH USER_MODE
		];
	}

	private static void refuseProblems(List<String> found) {
		if (!found.isEmpty()) {
			throw new ConnectorConnections.ConnectorException(String.join(found, ' '));
		}
	}

	private static Object parsedOrNull(String source) {
		try {
			return String.isBlank(source) ? null : JSON.deserializeUntyped(source);
		} catch (Exception unreadable) {
			return null;
		}
	}
}
