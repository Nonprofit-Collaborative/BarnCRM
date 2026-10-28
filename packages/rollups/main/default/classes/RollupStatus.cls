/**
 * How each rollup's recalculation stands, for its row in the rollup list (Rollup Builder ease of
 * use U6, ADR-0136): switched off, records that could not be saved, a full run going, records
 * waiting in the Rollup Queue, or nothing waiting. Needs Attention says the same for every rollup
 * at once; this splits it by rollup.
 *
 * A queue entry names the definitions whose change queued it (`Definition_Ids__c`); one that
 * names none is for every active definition on its target entity (R-R11). Read in user mode,
 * for someone who can manage settings only, as Needs Attention is.
 */
public with sharing class RollupStatus {
    public static final String LEVEL_OFF = 'off';
    public static final String LEVEL_FAILED = 'failed';
    public static final String LEVEL_RUNNING = 'running';
    public static final String LEVEL_WAITING = 'waiting';
    public static final String LEVEL_CLEAR = 'clear';

    /** Queue entries read at most, so a long backlog never slows the list. */
    @TestVisible
    private static final Integer ENTRIES_READ = 2000;

    /** One rollup's state: a level the list styles, and the words it shows. */
    public class State {
        public String level;
        public String text;

        public State(String level, String text) {
            this.level = level;
            this.text = text;
        }
    }

    /** The state of each definition given, by its Id. */
    public static Map<Id, State> of(List<Rollup_Definition__c> definitions) {
        Map<Id, Decimal> waiting = new Map<Id, Decimal>();
        Map<Id, Decimal> failed = new Map<Id, Decimal>();
        countQueue(definitions, waiting, failed);
        Boolean running = RollupFullRecalcBatch.runningJobId() != null;
        Map<Id, State> states = new Map<Id, State>();
        for (Rollup_Definition__c definition : definitions) {
            states.put(
                definition.Id,
                stateOf(definition, running, waiting.get(definition.Id), failed.get(definition.Id))
            );
        }
        return states;
    }

    @TestVisible
    private static State stateOf(
        Rollup_Definition__c definition,
        Boolean running,
        Decimal waiting,
        Decimal failed
    ) {
        if (definition.Active__c != true) {
            return new State(LEVEL_OFF, Label.Core_RollupEase_StatusOff);
        }
        if (failed != null && failed > 0) {
            return new State(
                LEVEL_FAILED,
                String.format(
                    Label.Core_RollupEase_StatusFailed,
                    new List<String>{ failed.format() }
                )
            );
        }
        if (running) {
            return new State(LEVEL_RUNNING, Label.Core_RollupEase_StatusRunning);
        }
        if (waiting != null && waiting > 0) {
            return new State(
                LEVEL_WAITING,
                String.format(
                    Label.Core_RollupEase_StatusWaiting,
                    new List<String>{ waiting.format() }
                )
            );
        }
        return new State(LEVEL_CLEAR, Label.Core_RollupEase_StatusClear);
    }

    /** Adds each queue entry's record count to every definition it is for. */
    private static void countQueue(
        List<Rollup_Definition__c> definitions,
        Map<Id, Decimal> waiting,
        Map<Id, Decimal> failed
    ) {
        Map<Schema.SObjectType, List<Id>> activeByTarget = new Map<Schema.SObjectType, List<Id>>();
        Set<Id> known = new Set<Id>();
        for (Rollup_Definition__c definition : definitions) {
            known.add(definition.Id);
            Schema.SObjectType target = SettingsService.typeByName(definition.Target_Object__c);
            if (definition.Active__c == true && target != null) {
                if (!activeByTarget.containsKey(target)) {
                    activeByTarget.put(target, new List<Id>());
                }
                activeByTarget.get(target).add(definition.Id);
            }
        }
        for (Rollup_Queue__c entry : [
            SELECT Status__c, Target_Object__c, Definition_Ids__c, Record_Count__c
            FROM Rollup_Queue__c
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT :ENTRIES_READ
        ]) {
            Map<Id, Decimal> counts = entry.Status__c == RollupQueue.STATUS_FAILED
                ? failed
                : waiting;
            Decimal records = entry.Record_Count__c == null ? 0 : entry.Record_Count__c;
            for (Id definitionId : definitionsOf(entry, activeByTarget, known)) {
                Decimal sum = counts.get(definitionId);
                counts.put(definitionId, (sum == null ? 0 : sum) + records);
            }
        }
    }

    private static List<Id> definitionsOf(
        Rollup_Queue__c entry,
        Map<Schema.SObjectType, List<Id>> activeByTarget,
        Set<Id> known
    ) {
        List<Id> named = new List<Id>();
        if (String.isNotBlank(entry.Definition_Ids__c)) {
            for (String text : entry.Definition_Ids__c.split(',')) {
                Id definitionId = idOrNull(text.trim());
                if (definitionId != null && known.contains(definitionId)) {
                    named.add(definitionId);
                }
            }
            return named;
        }
        List<Id> forTarget = activeByTarget.get(SettingsService.typeByName(entry.Target_Object__c));
        return forTarget == null ? named : forTarget;
    }

    private static Id idOrNull(String text) {
        try {
            return Id.valueOf(text);
        } catch (StringException notAnId) {
            return null;
        }
    }
}
