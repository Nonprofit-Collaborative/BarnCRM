/**
 * The single entry point every packaged trigger uses.
 *
 * A trigger contains one line, naming its object:
 *
 *     trigger ContactTrigger on Contact (before insert, after insert) {
 *         TriggerDispatcher.run('Contact');
 *     }
 *
 * The dispatcher reads the shipped registry for that object, in execution order, and runs each
 * handler it names (ADR-0017). A module ships its handler class and its registry record and
 * never edits another feature's trigger. The `run(TriggerHandler, Context)` overload runs one
 * handler with no registry row, for tests and for a module's own trigger entry point.
 *
 * Before it invokes anything, the dispatcher asks three questions in order: is this handler
 * bypassed for this transaction, is all automation paused (the timed pause for the org, or the
 * BarnCRM Automation Control setting's Pause All or Bypass for the person saving), and is this
 * automation switched on. Any "no" and the handler simply does not run.
 *
 * It asks none of them for an automation whose registry row carries `Always_Runs__c`. That row
 * enforces a rule rather than providing a convenience, so there is nothing an administrator, a
 * pause or a bypass can say that should stop it (ADR-0024).
 *
 * FAILURES (ADR-0165 dispatcher error contract). Whatever a handler throws is logged to the
 * Error Log first, so R-E1 holds even when the user never sees the failure. Then only the records
 * the failure belongs to are refused, and the rest of the save goes ahead:
 *
 *   - one record: it is refused with a message Maria can act on, in a before or an after context;
 *   - several records, inside a trigger: the dispatcher undoes the failed attempt to a savepoint
 *     it took before the first handler ran, and runs every handler again over each half of the
 *     records, halving the half that fails again until the failure is pinned on single records.
 *     Those are refused; every other record is processed and saved. Each record refused is also
 *     written to the Error Log, by its row in the save. Records a handler had already refused
 *     with a message of its own keep that message and are not run again;
 *   - a failure of an automation that always runs (ADR-0024) is not narrowed: every record in
 *     front of it is refused, as before, because an integrity rule that could not be checked
 *     lets nothing through;
 *   - when the transaction has too little room left to run the handlers again (queries, DML
 *     statements, rows or CPU time, measured on the failed attempt), the records not yet cleared
 *     are refused together rather than risk a limit failure that would refuse everything;
 *   - outside a trigger (a handler run directly, from a test or a bulk operation) there is no
 *     record to put a message on, so the dispatcher throws the same friendly message.
 *
 * Narrowing works because a handler reads its records through `TriggerHandler.newRecords()` and
 * its companions, which the dispatcher points at the half being run; it never reads
 * `Trigger.new` itself. Running a handler again over records it already worked on is the same
 * thing a partial save's retry does, which every handler already has to be safe for
 * (`TriggerHandler` says so); the recursion guard's claims are put back with the savepoint.
 *
 * A handler method takes no arguments. The dispatcher works out the context and calls the method
 * that matches; the handler reads its records through the `TriggerHandler` accessors. `Context`
 * therefore says which method to call and which records there are, and is not passed to the
 * handler.
 */
@NamespaceAccessible
public with sharing class TriggerDispatcher {
	@NamespaceAccessible
	public class TriggerDispatcherException extends Exception {
	}

	/** Queries, DML statements, rows and CPU milliseconds kept back after a narrowing attempt. */
	private static final Integer RESERVE_QUERIES = 10;
	private static final Integer RESERVE_DML_STATEMENTS = 10;
	private static final Integer RESERVE_DML_ROWS = 500;
	private static final Integer RESERVE_CPU_MS = 2000;

	/** Test seam: answers that no room is left to narrow a failure, as in a crowded save. */
	@TestVisible
	private static Boolean noRoomForTest = false;

	/**
	 * The trigger context, passed explicitly so that a handler can be dispatched from a test or
	 * from a bulk operation without a real trigger.
	 */
	@NamespaceAccessible
	public class Context {
		public System.TriggerOperation operation { get; private set; }
		public List<SObject> newRecords { get; private set; }
		public Map<Id, SObject> newRecordsById { get; private set; }
		public List<SObject> oldRecords { get; private set; }
		public Map<Id, SObject> oldRecordsById { get; private set; }

		@NamespaceAccessible
		public Context(
			System.TriggerOperation operation,
			List<SObject> newRecords,
			Map<Id, SObject> newRecordsById,
			List<SObject> oldRecords,
			Map<Id, SObject> oldRecordsById
		) {
			this.operation = operation;
			this.newRecords = newRecords;
			this.newRecordsById = newRecordsById;
			this.oldRecords = oldRecords;
			this.oldRecordsById = oldRecordsById;
		}

		@NamespaceAccessible
		public Boolean isBefore() {
			return operation == System.TriggerOperation.BEFORE_INSERT ||
				operation == System.TriggerOperation.BEFORE_UPDATE ||
				operation == System.TriggerOperation.BEFORE_DELETE;
		}

		/** The records a message goes on: the new ones, or the old ones of a delete. */
		List<SObject> targets() {
			List<SObject> records = newRecords == null ? oldRecords : newRecords;
			return records == null ? new List<SObject>() : records;
		}
	}

	/**
	 * The line a packaged trigger contains: run every automation the registry lists for this
	 * object, in execution order.
	 */
	@NamespaceAccessible
	public static void run(String objectApiName) {
		if (!Trigger.isExecuting) {
			return;
		}
		// Before and after: a partial save's retry is told apart from the attempt it repeats.
		TriggerHandler.noteTriggerProgress();
		run(objectApiName, currentContext());
		TriggerHandler.noteTriggerProgress();
	}

	@NamespaceAccessible
	public static void run(String objectApiName, Context context) {
		if (String.isBlank(objectApiName) || context == null || context.operation == null) {
			return;
		}
		List<Registered> handlers = new List<Registered>();
		for (
			Automation_Registry__mdt entry : AutomationRegistrySelector.selectForObject(
				objectApiName
			)
		) {
			TriggerHandler handler = instantiate(entry, objectApiName);
			if (handler != null) {
				handlers.add(
					new Registered(handler, entry.DeveloperName, entry.Always_Runs__c == true)
				);
			}
		}
		new TriggerRun('Trigger dispatch: ' + objectApiName, context, handlers).start();
	}

	@NamespaceAccessible
	public static void run(TriggerHandler handler, Context context) {
		if (handler == null || context == null || context.operation == null) {
			return;
		}
		// A handler run directly, without a registry row, is an ordinary switchable automation:
		// only a shipped registry record can say that an automation always runs.
		new TriggerRun(
				handler.getName(),
				context,
				new List<Registered>{ new Registered(handler, handler.getName(), false) }
			)
			.start();
	}

	/**
	 * Work a handler hands back to run once every handler of the same trigger run has run, so
	 * two handlers that save the same records can save them once (D-143).
	 */
	@NamespaceAccessible
	public interface Deferred {
		void run();
	}

	/** The deferred work of each trigger run under way, the innermost last. */
	private static final List<List<Deferred>> DEFERRED_BY_RUN = new List<List<Deferred>>();

	/**
	 * Runs `work` once every handler of the trigger run under way has run, or at once when no
	 * trigger run is under way (a handler run directly, or a call from outside a trigger). A
	 * failure is logged and reported as a handler's is.
	 */
	@NamespaceAccessible
	public static void afterHandlers(Deferred work) {
		if (work == null) {
			return;
		}
		if (DEFERRED_BY_RUN.isEmpty()) {
			work.run();
			return;
		}
		DEFERRED_BY_RUN[DEFERRED_BY_RUN.size() - 1].add(work);
	}

	/** A handler with the registry row it came from. */
	private class Registered {
		final TriggerHandler handler;
		final String automationName;
		/**
		 * Carried from the registry row the same way the name is, because it is a property of
		 * the automation the row declares and not of the handler class: a rule enforcing
		 * automation (ADR-0024) is not bypassed, not paused, and not switched off.
		 */
		final Boolean alwaysRuns;

		Registered(TriggerHandler handler, String registeredName, Boolean alwaysRuns) {
			this.handler = handler;
			this.automationName = String.isBlank(registeredName)
				? handler.getName()
				: registeredName;
			this.alwaysRuns = alwaysRuns == true;
		}

		Boolean shouldRun(PauseCheck pause) {
			if (alwaysRuns) {
				return true;
			}
			return !AutomationControl.isBypassed(automationName) &&
				!pause.isPaused() &&
				AutomationControl.isEnabled(automationName);
		}
	}

	/** What failed in an attempt, and whether it was an automation that always runs. */
	private class Failure {
		final Exception error;
		final String automationName;
		final Boolean alwaysRuns;

		Failure(Exception error, String automationName, Boolean alwaysRuns) {
			this.error = error;
			this.automationName = automationName;
			this.alwaysRuns = alwaysRuns == true;
		}
	}

	/**
	 * Whether all automation is paused, asked once per trigger run and only when a handler that
	 * can be paused gets that far, rather than once for each of its handlers.
	 */
	private class PauseCheck {
		private Boolean paused;

		Boolean isPaused() {
			if (this.paused == null) {
				// The timed pause, or the BarnCRM Automation Control setting that applies to the
				// person saving (Pause All or Bypass), read alongside each other.
				this.paused =
					AutomationControl.isOffForRunningUser() || AutomationControl.isPaused();
			}
			return this.paused;
		}
	}

	/** What a failed attempt spent, so a narrowing attempt runs only when the same fits again. */
	private class Spend {
		private final Integer queriesAtStart = Limits.getQueries();
		private final Integer statementsAtStart = Limits.getDmlStatements();
		private final Integer rowsAtStart = Limits.getDmlRows();
		private final Integer cpuAtStart = Limits.getCpuTime();
		private Integer queries = 0;
		private Integer statements = 0;
		private Integer rows = 0;
		private Integer cpu = 0;

		void stop() {
			queries = Limits.getQueries() - queriesAtStart;
			statements = Limits.getDmlStatements() - statementsAtStart;
			rows = Limits.getDmlRows() - rowsAtStart;
			cpu = Limits.getCpuTime() - cpuAtStart;
		}

		/** Room for one more attempt, its savepoint and rollback, and a margin. */
		Boolean roomForAnother() {
			if (noRoomForTest) {
				return false;
			}
			return Limits.getLimitQueries() - Limits.getQueries() >
				queries + RESERVE_QUERIES &&
				Limits.getLimitDmlStatements() - Limits.getDmlStatements() >
				statements + 2 + RESERVE_DML_STATEMENTS &&
				Limits.getLimitDmlRows() - Limits.getDmlRows() >
				rows + RESERVE_DML_ROWS &&
				Limits.getLimitCpuTime() - Limits.getCpuTime() >
				cpu + RESERVE_CPU_MS;
		}
	}

	/** One trigger run: its handlers over its records, and what to do when one fails. */
	private class TriggerRun {
		private final String logContext;
		private final Context context;
		private final List<Registered> handlers;
		private final PauseCheck pause = new PauseCheck();
		/** One Error Log message per record refused while narrowing, with its record id. */
		private final List<String> refusedMessages = new List<String>();
		private final List<Id> refusedIds = new List<Id>();
		/** True once the failure is being narrowed, when each refusal is worth its own entry. */
		private Boolean narrowing = false;

		TriggerRun(String logContext, Context context, List<Registered> handlers) {
			this.logContext = logContext;
			this.context = context;
			this.handlers = handlers;
		}

		void start() {
			TriggerHandler.enterRun();
			try {
				execute();
			} finally {
				TriggerHandler.leaveRun();
			}
		}

		private void execute() {
			Integer size = context.targets().size();
			Boolean narrowable = Trigger.isExecuting && size > 1 && anyNarrowableHandler();
			Savepoint beforeRun = narrowable ? Database.setSavepoint() : null;
			Map<String, Set<Id>> claims = narrowable ? TriggerHandler.copyRunClaims() : null;
			Spend spend = new Spend();
			Failure failed = attempt(null);
			if (failed == null) {
				return;
			}
			spend.stop();
			ErrorLogger.log(failed.error, failed.automationName, firstRecordId(context));
			if (!Trigger.isExecuting || size == 0) {
				throw new TriggerDispatcherException(
					Label.Core_Automation_UnexpectedError,
					failed.error
				);
			}
			if (beforeRun == null || failed.alwaysRuns) {
				refuse(allRows(size));
				return;
			}
			Database.rollback(beforeRun);
			TriggerHandler.restoreRunClaims(claims);
			List<Integer> open = stillOpen(allRows(size));
			if (!open.isEmpty()) {
				narrowing = true;
				narrow(open, spend);
			}
			if (!refusedMessages.isEmpty()) {
				ErrorLogger.logMessages(
					refusedMessages,
					refusedIds,
					logContext,
					ErrorLogger.SEVERITY_WARNING
				);
			}
		}

		/** True when some handler that is not an always-run rule would run now. */
		private Boolean anyNarrowableHandler() {
			for (Registered entry : handlers) {
				if (!entry.alwaysRuns && entry.shouldRun(pause)) {
					return true;
				}
			}
			return false;
		}

		/**
		 * Runs every handler that should run, then the deferred work, over `rows` (null for all
		 * the records), and answers the first failure, or null.
		 */
		private Failure attempt(List<Integer> rows) {
			TriggerHandler.narrowRun(rows == null ? null : scopeOf(rows));
			List<Deferred> deferred = new List<Deferred>();
			DEFERRED_BY_RUN.add(deferred);
			Failure failure = null;
			try {
				for (Registered entry : handlers) {
					if (!entry.shouldRun(pause)) {
						continue;
					}
					try {
						dispatch(entry.handler, context);
					} catch (Exception caught) {
						failure = new Failure(caught, entry.automationName, entry.alwaysRuns);
						break;
					}
				}
			} finally {
				DEFERRED_BY_RUN.remove(DEFERRED_BY_RUN.size() - 1);
			}
			try {
				if (failure != null) {
					return failure;
				}
				for (Deferred work : deferred) {
					try {
						work.run();
					} catch (Exception caught) {
						return new Failure(caught, logContext, false);
					}
				}
				return null;
			} finally {
				TriggerHandler.narrowRun(null);
			}
		}

		/**
		 * Finds which of `rows` the failure belongs to: runs each half again, keeps a half that
		 * succeeds, and halves a half that fails until single records are left to refuse.
		 */
		private void narrow(List<Integer> rows, Spend spend) {
			if (rows.size() == 1) {
				probe(rows, spend);
				return;
			}
			Integer middle = rows.size() / 2;
			probe(slice(rows, 0, middle), spend);
			probe(slice(rows, middle, rows.size()), spend);
		}

		/**
		 * Runs the handlers over `rows` alone. Success keeps the work; a failure is undone and
		 * narrowed further, or refused when it is one record, an always-run rule, or there is no
		 * room left to try again.
		 */
		private void probe(List<Integer> rows, Spend spend) {
			if (rows.isEmpty()) {
				return;
			}
			if (!spend.roomForAnother()) {
				refuse(rows);
				return;
			}
			Savepoint beforeProbe = Database.setSavepoint();
			Map<String, Set<Id>> claims = TriggerHandler.copyRunClaims();
			Failure failed = attempt(rows);
			if (failed == null) {
				return;
			}
			Database.rollback(beforeProbe);
			TriggerHandler.restoreRunClaims(claims);
			if (failed.alwaysRuns || rows.size() == 1) {
				refuse(rows);
				return;
			}
			List<Integer> open = stillOpen(rows);
			if (!open.isEmpty()) {
				narrow(open, spend);
			}
		}

		/** Puts the friendly message on each of these records that carries no error yet. */
		private void refuse(List<Integer> rows) {
			List<SObject> targets = context.targets();
			for (Integer row : rows) {
				SObject record = targets[row];
				if (record.hasErrors()) {
					continue;
				}
				try {
					record.addError(Label.Core_Automation_UnexpectedError);
				} catch (Exception cannotRefuse) {
					// A record the platform will not take a message on: the whole save is
					// refused instead, as before this contract, and the failure is already logged.
					throw new TriggerDispatcherException(
						Label.Core_Automation_UnexpectedError,
						cannotRefuse
					);
				}
				if (!narrowing) {
					continue;
				}
				String note = BarnHelp.text(
					'Core',
					'Core_Automation_RecordRefused',
					new List<Object>{ String.valueOf(row + 1) }
				);
				// A help catalog that cannot be read must not cost the entry its place in the log.
				refusedMessages.add(
					String.isBlank(note)
						? Label.Core_Automation_UnexpectedError + ' (' + (row + 1) + ')'
						: note
				);
				refusedIds.add(record.Id);
			}
		}

		/** Rows whose record carries no error yet: one already refused is not run again. */
		private List<Integer> stillOpen(List<Integer> rows) {
			List<SObject> targets = context.targets();
			List<Integer> open = new List<Integer>();
			for (Integer row : rows) {
				if (!targets[row].hasErrors()) {
					open.add(row);
				}
			}
			return open;
		}

		/**
		 * These rows as the four collections a handler reads, typed as the trigger's own (a
		 * handler casts them to `List<Contact>`, which a plain `List<SObject>` would refuse).
		 */
		private TriggerHandler.Scope scopeOf(List<Integer> rows) {
			return new TriggerHandler.Scope(
				listOf(context.newRecords, rows),
				mapOf(context.newRecords, context.newRecordsById, rows),
				listOf(context.oldRecords, rows),
				mapOf(context.oldRecords, context.oldRecordsById, rows)
			);
		}
	}

	private static List<SObject> listOf(List<SObject> records, List<Integer> rows) {
		if (records == null) {
			return null;
		}
		List<SObject> part = (List<SObject>) Type.forName(
				'List<' + String.valueOf(records.getSObjectType()) + '>'
			)
			.newInstance();
		for (Integer row : rows) {
			part.add(records[row]);
		}
		return part;
	}

	private static Map<Id, SObject> mapOf(
		List<SObject> records,
		Map<Id, SObject> byId,
		List<Integer> rows
	) {
		if (records == null || byId == null) {
			return null;
		}
		Map<Id, SObject> part = (Map<Id, SObject>) Type.forName(
				'Map<Id,' + String.valueOf(records.getSObjectType()) + '>'
			)
			.newInstance();
		for (Integer row : rows) {
			Id recordId = records[row].Id;
			if (recordId != null && byId.containsKey(recordId)) {
				part.put(recordId, byId.get(recordId));
			}
		}
		return part;
	}

	private static List<Integer> allRows(Integer size) {
		List<Integer> rows = new List<Integer>();
		for (Integer i = 0; i < size; i++) {
			rows.add(i);
		}
		return rows;
	}

	private static List<Integer> slice(List<Integer> rows, Integer fromIndex, Integer toIndex) {
		List<Integer> part = new List<Integer>();
		for (Integer i = fromIndex; i < toIndex; i++) {
			part.add(rows[i]);
		}
		return part;
	}

	private static Context currentContext() {
		return new Context(
			Trigger.operationType,
			Trigger.new,
			Trigger.newMap,
			Trigger.old,
			Trigger.oldMap
		);
	}

	/**
	 * Calls the one method this context names. Every handler method takes no arguments: the
	 * handler reads its records through the `TriggerHandler` accessors, so the context is only
	 * used here to decide which method to call.
	 */
	private static void dispatch(TriggerHandler handler, Context context) {
		switch on context.operation {
			when BEFORE_INSERT {
				handler.beforeInsert();
			}
			when AFTER_INSERT {
				handler.afterInsert();
			}
			when BEFORE_UPDATE {
				handler.beforeUpdate();
			}
			when AFTER_UPDATE {
				handler.afterUpdate();
			}
			when BEFORE_DELETE {
				handler.beforeDelete();
			}
			when AFTER_DELETE {
				handler.afterDelete();
			}
			when AFTER_UNDELETE {
				handler.afterUndelete();
			}
			when else {
				return;
			}
		}
	}

	/**
	 * Builds the handler a registry record names. A handler that cannot be built is skipped with
	 * a warning in the Error Log rather than failing the save: one broken automation must not
	 * stop a person entering data.
	 */
	private static TriggerHandler instantiate(
		Automation_Registry__mdt entry,
		String objectApiName
	) {
		String className = entry.Handler_Class__c;
		if (String.isBlank(className)) {
			skip(className, objectApiName);
			return null;
		}
		Type handlerType = NamespaceUtil.resolveType(className);
		if (handlerType == null) {
			skip(className, objectApiName);
			return null;
		}
		Object handler;
		try {
			handler = handlerType.newInstance();
		} catch (Exception cannotBuild) {
			skip(className, objectApiName);
			return null;
		}
		if (!(handler instanceof TriggerHandler)) {
			skip(className, objectApiName);
			return null;
		}
		return (TriggerHandler) handler;
	}

	private static void skip(String className, String objectApiName) {
		ErrorLogger.logMessage(
			String.format(
				Label.Core_Automation_HandlerUnavailable,
				new List<String>{ className == null ? '' : className }
			),
			'Trigger dispatch: ' + objectApiName,
			ErrorLogger.SEVERITY_WARNING
		);
	}

	private static Id firstRecordId(Context context) {
		if (context.newRecordsById != null && !context.newRecordsById.isEmpty()) {
			return new List<Id>(context.newRecordsById.keySet())[0];
		}
		if (context.oldRecordsById != null && !context.oldRecordsById.isEmpty()) {
			return new List<Id>(context.oldRecordsById.keySet())[0];
		}
		return null;
	}
}
