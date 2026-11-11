/**
 * The Migration Assistant (MIG-01, ADR-NEXT migration-assistant, canonical model Section 29ZS and
 * R-MK1): the kits this org has, a kit's run with each step's status and verification, and the
 * actions that move a run on. Loading is the Import engine's own: an import step creates one
 * Import Batch whose rows `MigrationStageBatch` reads from the other product, and its dry run,
 * commit and undo are the Super Importer's.
 *
 * Every object and field name a kit holds is data, resolved through describe at run time, so
 * Core never names another product's schema (ADR-0013, ADR-0062). Runs are read and written in
 * the running administrator's access.
 */
public with sharing class MigrationKitService {
	public static final String KIND_IMPORT = 'import';
	public static final String KIND_TOOL = 'tool';
	public static final String NOT_STARTED = 'NotStarted';
	public static final String WAITING = 'Waiting';
	public static final String RUNNING = 'Running';
	public static final String REVIEW = 'Review';
	public static final String DONE = 'Done';
	public static final String UNDONE = 'Undone';
	public static final String FAILED = 'Failed';
	private static final String IN_PROGRESS = 'In Progress';
	private static final String RUN_COMPLETE = 'Complete';
	private static final Integer MAX_HOPS = 5;
	private static final String CONTEXT = 'MigrationKitService';

	/** Stands in for the shipped kits in tests. */
	@TestVisible
	private static List<Migration_Kit__mdt> catalogOverride;

	/** Stands in for a kit's extension in tests, by class name. */
	@TestVisible
	private static Map<String, MigrationKitExtension> extensionOverride = new Map<String, MigrationKitExtension>();

	/** Refuses an action in words the page shows. */
	public class MigrationException extends Exception {
	}

	/** One step of a kit, as its JSON writes it (R-MK1). */
	public class Step {
		public String key;
		public String label;
		public String kind;
		public String help;
		public String source;
		public List<String> fields;
		public List<Condition> filters;
		public String templateKey;
		public String tab;
		public String toolLabel;
	}

	/** One condition of an import step's `filters`: the field equals the value. */
	public class Condition {
		public String field;
		public Object value;
	}

	/** One retire checklist item. */
	public class Item {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String text;
		@AuraEnabled
		public Boolean ticked;
	}

	/** Tool steps marked done (and empty import steps) and checklist items ticked, by key. */
	private class State {
		Map<String, Boolean> done = new Map<String, Boolean>();
		Map<String, Boolean> ticked = new Map<String, Boolean>();
	}

	/** A kit as the Assistant shows it. */
	public class KitView {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String description;
		/** Why the kit cannot run, or null. */
		@AuraEnabled
		public String problem;
		@AuraEnabled
		public Boolean allDone = true;
		@AuraEnabled
		public Boolean complete = false;
		@AuraEnabled
		public List<StepView> steps = new List<StepView>();
		@AuraEnabled
		public List<Item> checklist = new List<Item>();
	}

	/** One step with where it stands, what may be done next and its verification (R-MR3). */
	public class StepView {
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public String help;
		/** NotStarted, Waiting, Running, Review, Done, Undone or Failed. */
		@AuraEnabled
		public String status;
		@AuraEnabled
		public Id batchId;
		@AuraEnabled
		public Boolean canStart = false;
		@AuraEnabled
		public Boolean canLoad = false;
		@AuraEnabled
		public Boolean canUndo = false;
		@AuraEnabled
		public Boolean canMarkDone = false;
		@AuraEnabled
		public Boolean canUnmark = false;
		/** For a tool step, the tab it opens, prefixed as this org needs. */
		@AuraEnabled
		public String tab;
		@AuraEnabled
		public String toolLabel;
		@AuraEnabled
		public Integer sourceCount;
		@AuraEnabled
		public Integer staged;
		@AuraEnabled
		public Integer loaded;
		@AuraEnabled
		public Integer rejected;
		@AuraEnabled
		public Integer checkSource;
		@AuraEnabled
		public Integer checkDone;
		@AuraEnabled
		public Boolean verified = false;
		@AuraEnabled
		public Boolean hasVerification = false;
	}

	// ------------------------------------------------------------------------------- catalog

	/** The kit key for each product key, for the products whose kit ships in this org. */
	public static Map<String, String> kitKeysByApp() {
		Map<String, String> byApp = new Map<String, String>();
		for (Migration_Kit__mdt kit : catalog()) {
			if (String.isNotBlank(kit.Source_App__c) && !byApp.containsKey(kit.Source_App__c)) {
				byApp.put(kit.Source_App__c, kit.DeveloperName);
			}
		}
		return byApp;
	}

	private static List<Migration_Kit__mdt> catalog() {
		if (catalogOverride != null) {
			return catalogOverride;
		}
		// A query, not getAll(): getAll() cuts long text to 255 characters.
		return [
			SELECT
				DeveloperName,
				MasterLabel,
				Source_App__c,
				Description__c,
				Steps_JSON__c,
				Retire_Checklist_JSON__c,
				Extension_Class__c,
				Sort_Order__c
			FROM Migration_Kit__mdt
			WITH SYSTEM_MODE
			ORDER BY Sort_Order__c, DeveloperName
		];
	}

	/** The kit, when it ships here and the product it moves from is detected; else refused. */
	private static Migration_Kit__mdt offeredKit(String kitKey) {
		for (Migration_Kit__mdt kit : catalog()) {
			if (kit.DeveloperName == kitKey) {
				if (!IntegrationAppService.detectedKeys().contains(kit.Source_App__c)) {
					throw refusal(
						BarnHelp.text('Core', 'Core_Migration_ErrorNotDetected'),
						kit.MasterLabel
					);
				}
				return kit;
			}
		}
		throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownKit'), null);
	}

	/** The kit's steps in order, refused with the reason when the JSON cannot be read. */
	@TestVisible
	private static List<Step> steps(Migration_Kit__mdt kit) {
		List<Step> parsed;
		try {
			parsed = (List<Step>) JSON.deserialize(
				String.isBlank(kit.Steps_JSON__c) ? '[]' : kit.Steps_JSON__c,
				List<Step>.class
			);
		} catch (JSONException unreadable) {
			throw refusal(
				BarnHelp.text('Core', 'Core_Migration_ErrorKitUnreadable'),
				unreadable.getMessage()
			);
		}
		Set<String> keys = new Set<String>();
		for (Step step : parsed) {
			Boolean known = step != null && (step.kind == KIND_IMPORT || step.kind == KIND_TOOL);
			if (!known || String.isBlank(step.key) || !keys.add(step.key)) {
				throw refusal(
					BarnHelp.text('Core', 'Core_Migration_ErrorKitUnreadable'),
					step == null ? '' : step.key
				);
			}
			if (
				step.kind == KIND_IMPORT &&
				(String.isBlank(step.source) || String.isBlank(step.templateKey))
			) {
				throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorKitUnreadable'), step.key);
			}
		}
		return parsed;
	}

	private static List<Item> checklist(Migration_Kit__mdt kit) {
		if (String.isBlank(kit.Retire_Checklist_JSON__c)) {
			return new List<Item>();
		}
		try {
			return (List<Item>) JSON.deserialize(kit.Retire_Checklist_JSON__c, List<Item>.class);
		} catch (JSONException unreadable) {
			throw refusal(
				BarnHelp.text('Core', 'Core_Migration_ErrorKitUnreadable'),
				unreadable.getMessage()
			);
		}
	}

	private static MigrationKitExtension extensionOf(Migration_Kit__mdt kit) {
		String name = kit.Extension_Class__c;
		if (String.isBlank(name)) {
			return null;
		}
		if (extensionOverride.containsKey(name)) {
			return extensionOverride.get(name);
		}
		return (MigrationKitExtension) NamespaceUtil.build(
			name,
			MigrationKitExtension.class,
			CONTEXT
		);
	}

	// ---------------------------------------------------------------------------------- view

	/** The kit, its steps in order with their status and verification, and its checklist. */
	public static KitView view(String kitKey) {
		requirePermission();
		Migration_Kit__mdt kit = offeredKit(kitKey);
		KitView view = new KitView();
		view.key = kit.DeveloperName;
		view.label = kit.MasterLabel;
		view.description = kit.Description__c;
		List<Step> steps;
		try {
			steps = steps(kit);
			view.checklist = checklist(kit);
		} catch (MigrationException unreadable) {
			view.problem = unreadable.getMessage();
			view.allDone = false;
			return view;
		}
		Migration_Run__c run = runFor(kitKey, false);
		State state = stateOf(run);
		Map<String, Import_Batch__c> batches = latestBatches(run == null ? null : run.Id);
		MigrationKitExtension extension = extensionOf(kit);
		List<Boolean> doneFlags = new List<Boolean>();
		for (Step step : steps) {
			StepView shown = stepView(step, batches.get(step.key), state, view.allDone);
			verify(shown, step, batches.get(step.key), extension);
			Boolean done = shown.status == DONE;
			doneFlags.add(done);
			view.allDone = view.allDone && done;
			view.steps.add(shown);
		}
		// Backwards: only a step with nothing done after it can be undone or unmarked (R-MR2).
		Boolean laterDone = false;
		for (Integer index = view.steps.size() - 1; index >= 0; index--) {
			StepView shown = view.steps[index];
			Boolean undoable =
				shown.batchId != null &&
				(shown.status == DONE ||
				ImportBatchService.STATUS_UNDO_FAILED.equals(batches.get(shown.key).Status__c));
			shown.canUndo = !laterDone && shown.kind == KIND_IMPORT && undoable;
			shown.canUnmark = !laterDone && shown.kind == KIND_TOOL && shown.status == DONE;
			laterDone = laterDone || doneFlags[index];
		}
		Boolean allTicked = true;
		for (Item item : view.checklist) {
			item.ticked = state.ticked.get(item.key) == true;
			allTicked = allTicked && item.ticked;
		}
		view.complete = view.allDone && allTicked;
		syncStatus(run, view.complete);
		return view;
	}

	private static StepView stepView(
		Step step,
		Import_Batch__c batch,
		State state,
		Boolean priorDone
	) {
		StepView shown = new StepView();
		shown.key = step.key;
		shown.label = step.label;
		shown.kind = step.kind;
		shown.help = step.help;
		Boolean markedDone = state.done.get(step.key) == true;
		if (step.kind == KIND_TOOL) {
			shown.tab = NamespaceUtil.qualify(step.tab);
			shown.toolLabel = step.toolLabel;
			shown.status = markedDone ? DONE : NOT_STARTED;
			shown.canMarkDone = priorDone && !markedDone;
		} else {
			shown.batchId = batch == null ? null : batch.Id;
			shown.status = batch == null
				? (markedDone ? DONE : NOT_STARTED)
				: importStatus(batch.Status__c);
			Boolean restartable = batch == null
				? !markedDone
				: shown.status == UNDONE ||
				  ImportBatchService.STATUS_FAILED.equals(batch.Status__c);
			shown.canStart = priorDone && restartable;
			shown.canLoad = priorDone && shown.status == REVIEW;
		}
		if (!priorDone && shown.status == NOT_STARTED) {
			shown.status = WAITING;
		}
		return shown;
	}

	/** An Import Batch status as a step status. */
	@TestVisible
	private static String importStatus(String batchStatus) {
		if (batchStatus == ImportBatchService.STATUS_COMPLETE) {
			return DONE;
		}
		if (
			batchStatus == ImportBatchService.STATUS_DRY_RUN_COMPLETE ||
			batchStatus == ImportBatchService.STATUS_TRIAL_COMPLETE
		) {
			return REVIEW;
		}
		if (batchStatus == ImportBatchService.STATUS_UNDONE) {
			return UNDONE;
		}
		if (
			batchStatus == ImportBatchService.STATUS_FAILED ||
			batchStatus == ImportBatchService.STATUS_UNDO_FAILED
		) {
			return FAILED;
		}
		return RUNNING;
	}

	/** The verification numbers of a step (R-MR3). */
	private static void verify(
		StepView shown,
		Step step,
		Import_Batch__c batch,
		MigrationKitExtension extension
	) {
		MigrationCheck check = extension == null ? null : extension.verify(step.key);
		Boolean checkAgrees = check == null || (check.source != null && check.source == check.done);
		if (check != null) {
			shown.checkSource = check.source;
			shown.checkDone = check.done;
			shown.hasVerification = true;
		}
		if (step.kind == KIND_TOOL) {
			shown.verified = check != null && checkAgrees;
			return;
		}
		if (batch == null && shown.status != DONE) {
			return;
		}
		shown.hasVerification = true;
		try {
			shown.sourceCount = new Source(step).count();
		} catch (Exception unreadable) {
			ErrorLogger.log(unreadable, CONTEXT);
		}
		shown.staged = batch == null ? 0 : whole(batch.Row_Count__c);
		shown.loaded = batch == null
			? 0
			: whole(batch.Rows_Created__c) +
			  whole(batch.Rows_Updated__c) +
			  whole(batch.Rows_Matched__c);
		shown.rejected = batch == null ? 0 : whole(batch.Rows_Rejected__c);
		shown.verified =
			shown.status == DONE &&
			checkAgrees &&
			shown.sourceCount == shown.staged &&
			shown.staged == shown.loaded &&
			shown.rejected == 0;
	}

	private static Integer whole(Decimal value) {
		return value == null ? 0 : value.intValue();
	}

	// ------------------------------------------------------------------------------- actions

	/**
	 * Starts an import step (R-MR2): counts the source, creates the Import Batch and queues the
	 * staging job, which starts the dry run when it ends. An empty source marks the step done.
	 */
	public static void startStep(String kitKey, String stepKey) {
		StepView shown = actionable(kitKey, stepKey, KIND_IMPORT);
		if (!shown.canStart) {
			throw refusal(
				shown.status == WAITING
					? BarnHelp.text('Core', 'Core_Migration_ErrorOutOfOrder')
					: BarnHelp.text('Core', 'Core_Migration_ErrorAlreadyStarted'),
				null
			);
		}
		Migration_Kit__mdt kit = offeredKit(kitKey);
		Step step = stepNamed(kit, stepKey);
		Source source = new Source(step);
		Integer total = source.count();
		Migration_Run__c run = runFor(kitKey, true);
		if (total == 0) {
			State state = stateOf(run);
			state.done.put(step.key, true);
			save(run, state);
			return;
		}
		Import_Template__c template = templateFor(step.templateKey);
		Import_Batch__c batch = ImportBatchService.create(
			template.Id,
			null,
			(kit.MasterLabel + ': ' + step.label).abbreviate(255),
			String.isBlank(kit.Extension_Class__c) ? total : null,
			null,
			null,
			false
		);
		Database.update(
			new Import_Batch__c(
				Id = batch.Id,
				Migration_Run__c = run.Id,
				Migration_Step__c = step.key
			),
			AccessLevel.USER_MODE
		);
		Database.executeBatch(
			new MigrationStageBatch(batch.Id, kitKey, step.key),
			ImportBatchService.chunkSize()
		);
	}

	/** Marks a tool step done, or not done while no later step is done (R-MR2). */
	public static void markToolStep(String kitKey, String stepKey, Boolean done) {
		StepView shown = actionable(kitKey, stepKey, KIND_TOOL);
		if (done == true && !shown.canMarkDone) {
			throw refusal(
				shown.status == WAITING
					? BarnHelp.text('Core', 'Core_Migration_ErrorOutOfOrder')
					: BarnHelp.text('Core', 'Core_Migration_ErrorAlreadyStarted'),
				null
			);
		}
		if (done != true && !shown.canUnmark) {
			throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorLaterStepDone'), null);
		}
		Migration_Run__c run = runFor(kitKey, true);
		State state = stateOf(run);
		if (done == true) {
			state.done.put(stepKey, true);
		} else {
			state.done.remove(stepKey);
		}
		save(run, state);
		view(kitKey);
	}

	/** Ticks a retire checklist item, once every step is done, or unticks it (R-MR3). */
	public static void tick(String kitKey, String itemKey, Boolean ticked) {
		KitView current = view(kitKey);
		Boolean known = false;
		for (Item item : current.checklist) {
			known = known || item.key == itemKey;
		}
		if (!known) {
			throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownStep'), null);
		}
		if (ticked == true && !current.allDone) {
			throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorNotAllDone'), null);
		}
		Migration_Run__c run = runFor(kitKey, true);
		State state = stateOf(run);
		if (ticked == true) {
			state.ticked.put(itemKey, true);
		} else {
			state.ticked.remove(itemKey);
		}
		save(run, state);
		view(kitKey);
	}

	/** The step as the view shows it, refused when it is not in the kit or not of this kind. */
	private static StepView actionable(String kitKey, String stepKey, String kind) {
		KitView current = view(kitKey);
		if (current.problem != null) {
			throw new MigrationException(current.problem);
		}
		for (StepView shown : current.steps) {
			if (shown.key == stepKey && shown.kind == kind) {
				return shown;
			}
		}
		throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownStep'), null);
	}

	/** The named step of a kit, for the staging job. */
	public static Step stepNamed(Migration_Kit__mdt kit, String stepKey) {
		for (Step step : steps(kit)) {
			if (step.key == stepKey) {
				return step;
			}
		}
		throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownStep'), null);
	}

	/** The kit by key, whether or not its product is still detected, for the staging job. */
	public static Migration_Kit__mdt kitNamed(String kitKey) {
		for (Migration_Kit__mdt kit : catalog()) {
			if (kit.DeveloperName == kitKey) {
				return kit;
			}
		}
		throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownKit'), null);
	}

	/** The kit's extension, for the staging job, or null. */
	public static MigrationKitExtension extensionFor(Migration_Kit__mdt kit) {
		return extensionOf(kit);
	}

	private static Import_Template__c templateFor(String templateKey) {
		Set<String> keys = new Set<String>{ templateKey };
		Import_Template__c template = ImportTemplateSelector.selectByKeys(keys).get(templateKey);
		if (template == null) {
			ImportTemplateService.materializeDefaults();
			template = ImportTemplateSelector.selectByKeys(keys).get(templateKey);
		}
		if (template == null) {
			throw refusal(
				BarnHelp.text('Core', 'Core_Migration_ErrorTemplateMissing'),
				templateKey
			);
		}
		return template;
	}

	// ----------------------------------------------------------------------------------- run

	private static Migration_Run__c runFor(String kitKey, Boolean create) {
		List<Migration_Run__c> runs = [
			SELECT Id, Status__c, State_JSON__c
			FROM Migration_Run__c
			WHERE Kit__c = :kitKey
			WITH USER_MODE
			ORDER BY CreatedDate DESC, Id DESC
			LIMIT 1
		];
		if (!runs.isEmpty() || create != true) {
			return runs.isEmpty() ? null : runs[0];
		}
		Migration_Run__c run = new Migration_Run__c(Kit__c = kitKey, Status__c = IN_PROGRESS);
		Database.insert(run, AccessLevel.USER_MODE);
		return run;
	}

	private static State stateOf(Migration_Run__c run) {
		State state = new State();
		if (run == null || String.isBlank(run.State_JSON__c)) {
			return state;
		}
		try {
			State read = (State) JSON.deserialize(run.State_JSON__c, State.class);
			state.done = read.done == null ? state.done : read.done;
			state.ticked = read.ticked == null ? state.ticked : read.ticked;
		} catch (JSONException unreadable) {
			ErrorLogger.log(unreadable, CONTEXT);
		}
		return state;
	}

	private static void save(Migration_Run__c run, State state) {
		run.State_JSON__c = JSON.serialize(state);
		Database.update(
			new Migration_Run__c(Id = run.Id, State_JSON__c = run.State_JSON__c),
			AccessLevel.USER_MODE
		);
	}

	/** Complete once every step is done and every item ticked; reopened otherwise. */
	private static void syncStatus(Migration_Run__c run, Boolean complete) {
		String status = complete ? RUN_COMPLETE : IN_PROGRESS;
		if (run != null && run.Status__c != status) {
			run.Status__c = status;
			Database.update(
				new Migration_Run__c(Id = run.Id, Status__c = status),
				AccessLevel.USER_MODE
			);
		}
	}

	/** The latest Import Batch of each step of the run. */
	private static Map<String, Import_Batch__c> latestBatches(Id runId) {
		Map<String, Import_Batch__c> byStep = new Map<String, Import_Batch__c>();
		if (runId == null) {
			return byStep;
		}
		for (Import_Batch__c batch : [
			SELECT
				Id,
				Status__c,
				Migration_Step__c,
				Row_Count__c,
				Rows_Created__c,
				Rows_Updated__c,
				Rows_Matched__c,
				Rows_Rejected__c
			FROM Import_Batch__c
			WHERE Migration_Run__c = :runId
			WITH USER_MODE
			ORDER BY CreatedDate DESC, Id DESC
			LIMIT 500
		]) {
			if (!byStep.containsKey(batch.Migration_Step__c)) {
				byStep.put(batch.Migration_Step__c, batch);
			}
		}
		return byStep;
	}

	// -------------------------------------------------------------------------------- source

	/**
	 * An import step's source: its object, fields and conditions resolved through describe, the
	 * query that reads it in the running user's access, and a record as a staged row keyed by
	 * the field names as the step writes them. Holds only text, so a batch job can keep it.
	 */
	public class Source {
		private String objectName;
		private List<String> written = new List<String>{ 'Id' };
		private List<String> paths = new List<String>{ 'Id' };
		private String whereClause = '';
		private Map<String, Object> binds = new Map<String, Object>();

		public Source(Step step) {
			Schema.SObjectType type = NamespaceUtil.globalDescribe()
				.get(step.source.trim().replace('.', '__').toLowerCase());
			if (type == null || !type.getDescribe(SObjectDescribeOptions.DEFERRED).isAccessible()) {
				throw refusal(
					BarnHelp.text('Core', 'Core_Migration_ErrorUnknownName'),
					step.source
				);
			}
			objectName = String.valueOf(type);
			for (String field : step.fields == null ? new List<String>() : step.fields) {
				if (String.isNotBlank(field) && !written.contains(field.trim())) {
					written.add(field.trim());
					paths.add(path(type, field.trim(), false));
				}
			}
			List<String> clauses = new List<String>();
			for (
				Condition condition : step.filters == null ? new List<Condition>() : step.filters
			) {
				String field = path(type, condition == null ? null : condition.field, true);
				if (condition.value == null) {
					clauses.add(field + ' = null');
				} else {
					String name = 'w' + binds.size();
					binds.put(name, condition.value);
					clauses.add(field + ' = :' + name);
				}
			}
			whereClause = clauses.isEmpty() ? '' : ' WHERE ' + String.join(clauses, ' AND ');
		}

		/** How many records the step reads now. */
		public Integer count() {
			// Every name came from describe, never from the request; every value is a bind.
			return Database.countQueryWithBinds(
				'SELECT COUNT() FROM ' + objectName + whereClause,
				binds,
				AccessLevel.USER_MODE
			);
		}

		/** The records in Id order, in the running user's access, for the staging job. */
		public Database.QueryLocator locator() {
			return Database.getQueryLocatorWithBinds(
				'SELECT ' +
					String.join(new List<String>(new Set<String>(paths)), ', ') +
					' FROM ' +
					objectName +
					whereClause +
					' ORDER BY Id',
				binds,
				AccessLevel.USER_MODE
			);
		}

		/** Each record as one row, its values as text, keyed by the step's field names. */
		public List<Map<String, Object>> rows(List<SObject> records) {
			List<Map<String, Object>> rows = new List<Map<String, Object>>();
			for (SObject record : records) {
				Map<String, Object> row = new Map<String, Object>();
				for (Integer index = 0; index < written.size(); index++) {
					row.put(written[index], text(valueAt(record, paths[index])));
				}
				rows.add(row);
			}
			return rows;
		}
	}

	/**
	 * A field path as the platform names it. Each dot is first read as a relationship, then as
	 * a namespace separator (`ns.Field__c`), so `npsp.Primary_Contact__r.Email` and
	 * `Account.npsp.Code__c` both resolve. Refused, naming the path, when any part is missing or
	 * unreadable, or when a filter field cannot be filtered on.
	 */
	@TestVisible
	private static String path(Schema.SObjectType start, String written, Boolean filter) {
		if (String.isBlank(written)) {
			throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownName'), '');
		}
		List<String> parts = written.trim().split('\\.');
		List<String> resolved = new List<String>();
		Schema.SObjectType at = start;
		Integer index = 0;
		while (index < parts.size()) {
			Map<String, Schema.SObjectField> fields = at.getDescribe(
					SObjectDescribeOptions.DEFERRED
				)
				.fields.getMap();
			Schema.DescribeFieldResult found;
			Integer used = 0;
			for (
				Integer take = 1; take <= 2 && found == null && index + take <= parts.size(); take++
			) {
				String name = take == 1 ? parts[index] : parts[index] + '__' + parts[index + 1];
				Boolean last = index + take == parts.size();
				found = last ? fieldNamed(fields, name) : relationshipNamed(fields, name);
				used = found == null ? used : take;
			}
			Boolean last = found != null && index + used == parts.size();
			if (
				found == null ||
				!found.isAccessible() ||
				(last &&
				filter &&
				!found.isFilterable()) ||
				resolved.size() >= MAX_HOPS
			) {
				throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorUnknownName'), written);
			}
			index += used;
			if (last) {
				resolved.add(found.getName());
			} else {
				resolved.add(found.getRelationshipName());
				at = found.getReferenceTo()[0];
			}
		}
		return String.join(resolved, '.');
	}

	private static Schema.DescribeFieldResult fieldNamed(
		Map<String, Schema.SObjectField> fields,
		String name
	) {
		Schema.SObjectField field = fields.get(name.toLowerCase());
		return field == null ? null : field.getDescribe();
	}

	private static Schema.DescribeFieldResult relationshipNamed(
		Map<String, Schema.SObjectField> fields,
		String name
	) {
		for (Schema.SObjectField field : fields.values()) {
			Schema.DescribeFieldResult described = field.getDescribe();
			if (
				described.getRelationshipName() != null &&
				described.getRelationshipName().equalsIgnoreCase(name) &&
				!described.getReferenceTo().isEmpty()
			) {
				return described;
			}
		}
		return null;
	}

	private static Object valueAt(SObject record, String path) {
		List<String> parts = path.split('\\.');
		SObject at = record;
		for (Integer index = 0; at != null && index < parts.size() - 1; index++) {
			at = at.getSObject(parts[index]);
		}
		return at == null ? null : at.get(parts[parts.size() - 1]);
	}

	/** A value as a file would hold it: dates and times in ISO 8601, numbers plain. */
	@TestVisible
	private static String text(Object value) {
		if (value == null) {
			return '';
		}
		if (value instanceof Datetime) {
			return JSON.serialize(value).remove('"');
		}
		if (value instanceof Date) {
			return String.valueOf(value).left(10);
		}
		if (value instanceof Decimal) {
			return ((Decimal) value).toPlainString();
		}
		return String.valueOf(value);
	}

	// ------------------------------------------------------------------------------- helpers

	private static void requirePermission() {
		if (!BarnCRMPermissions.canManageSettings()) {
			throw refusal(BarnHelp.text('Core', 'Core_Migration_ErrorNoPermission'), null);
		}
	}

	private static MigrationException refusal(String text, String value) {
		return new MigrationException(
			value == null ? text : String.format(text, new List<String>{ value })
		);
	}
}
