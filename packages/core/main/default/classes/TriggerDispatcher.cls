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
 * handler with no registry row, for tests.
 *
 * Before it invokes anything, the dispatcher asks three questions in order: is this handler
 * bypassed for this transaction, is all automation paused for the org, and is this automation
 * switched on. Any "no" and the handler simply does not run.
 *
 * It asks none of them for an automation whose registry row carries `Always_Runs__c`. That row
 * enforces a rule rather than providing a convenience, so there is nothing an administrator, a
 * pause or a bypass can say that should stop it (ADR-0024).
 *
 * Failure handling is a deliberate choice. Whatever a handler throws is logged to the Error Log
 * first, so R-E1 holds even when the user never sees the failure. Then:
 *
 *   - in a before context the dispatcher calls addError on the records, so the save is refused
 *     with a message Maria can act on rather than with a stack trace, and the transaction is
 *     left in the user's hands;
 *   - in an after context there is nothing useful to attach a message to, so the dispatcher
 *     rethrows with the same friendly message, which rolls the transaction back.
 *
 * Either way the original exception is already recorded, so nothing is swallowed.
 *
 * A handler method takes no arguments. The dispatcher works out the context and calls the method
 * that matches; the handler reads `Trigger.new`, `Trigger.old`, `Trigger.newMap`, and
 * `Trigger.oldMap` itself. `Context` therefore says which method to call and gives the dispatcher
 * something to hang an error on, and is not passed to the handler.
 */
@NamespaceAccessible
public with sharing class TriggerDispatcher {
    @NamespaceAccessible
    public class TriggerDispatcherException extends Exception {
    }

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
        if (String.isBlank(objectApiName) || context == null) {
            return;
        }
        PauseCheck pause = new PauseCheck();
        List<Deferred> deferred = new List<Deferred>();
        DEFERRED_BY_RUN.add(deferred);
        try {
            for (
                Automation_Registry__mdt entry : AutomationRegistrySelector.selectForObject(
                    objectApiName
                )
            ) {
                TriggerHandler handler = instantiate(entry, objectApiName);
                if (handler != null) {
                    run(handler, context, entry.DeveloperName, entry.Always_Runs__c == true, pause);
                }
            }
        } catch (Exception thrown) {
            // A failure the dispatcher rethrows rolls the save back: the deferred work goes too.
            DEFERRED_BY_RUN.remove(DEFERRED_BY_RUN.size() - 1);
            throw thrown;
        }
        DEFERRED_BY_RUN.remove(DEFERRED_BY_RUN.size() - 1);
        runDeferred(deferred, objectApiName, context);
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

    private static void runDeferred(
        List<Deferred> deferred,
        String objectApiName,
        Context context
    ) {
        for (Deferred work : deferred) {
            try {
                work.run();
            } catch (Exception caught) {
                ErrorLogger.log(
                    caught,
                    'Trigger dispatch: ' + objectApiName,
                    firstRecordId(context)
                );
                reportToUser(context, caught);
            }
        }
    }

    @NamespaceAccessible
    public static void run(TriggerHandler handler, Context context) {
        if (handler == null) {
            return;
        }
        // A handler run directly, without a registry row, is an ordinary switchable automation:
        // only a shipped registry record can say that an automation always runs.
        run(handler, context, handler.getName(), false, new PauseCheck());
    }

    /**
     * Whether all automation is paused, asked once per trigger run and only when a handler that
     * can be paused gets that far, rather than once for each of its handlers.
     */
    private class PauseCheck {
        private Boolean paused;

        Boolean isPaused() {
            if (this.paused == null) {
                this.paused = AutomationControl.isPaused();
            }
            return this.paused;
        }
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
     * `alwaysRuns` is carried here from the registry row the same way `registeredName` is,
     * because it is a property of the automation the row declares and not of the handler class:
     * a rule enforcing automation (ADR-0024) is not bypassed, not paused, and not switched off.
     * Nothing else changes: it is dispatched and its failures are logged like any other.
     */
    private static void run(
        TriggerHandler handler,
        Context context,
        String registeredName,
        Boolean alwaysRuns,
        PauseCheck pause
    ) {
        if (handler == null || context == null || context.operation == null) {
            return;
        }
        String automationName = String.isBlank(registeredName) ? handler.getName() : registeredName;
        if (alwaysRuns != true) {
            if (AutomationControl.isBypassed(automationName)) {
                return;
            }
            if (pause.isPaused()) {
                return;
            }
            if (!AutomationControl.isEnabled(automationName)) {
                return;
            }
        }
        try {
            dispatch(handler, context);
        } catch (Exception caught) {
            ErrorLogger.log(caught, automationName, firstRecordId(context));
            reportToUser(context, caught);
        }
    }

    /**
     * Calls the one method this context names. Every handler method takes no arguments: the
     * handler reads `Trigger.new` and its companions itself (see `TriggerHandler`), so the
     * context is only used here to decide which method to call.
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

    private static void reportToUser(Context context, Exception caught) {
        List<SObject> targets = null;
        if (context.isBefore()) {
            targets = context.newRecords == null ? context.oldRecords : context.newRecords;
        }
        if (targets != null && !targets.isEmpty() && Trigger.isExecuting) {
            for (SObject record : targets) {
                record.addError(Label.Core_Automation_UnexpectedError);
            }
            return;
        }
        throw new TriggerDispatcherException(Label.Core_Automation_UnexpectedError, caught);
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
