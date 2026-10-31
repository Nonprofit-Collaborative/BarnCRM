/**
 * The rules every ask follows however it is saved (canonical model Section 25R): the stage comes
 * from the organization's own list (R-SO2), Stage Changed Date follows the stage (R-SO4), and
 * Closed Date follows the outcome (R-SO3).
 *
 * The stage list is one org-wide setting, `Ask_Stages__c` on Giving Settings: names in order,
 * separated by semicolons. An empty setting means the shipped list. Parsing lives here so the
 * trigger, the board and the tests all read the same list.
 */
public with sharing class AskRules {
    public static final String DEFAULT_STAGES = 'Identified;Qualified;Cultivating;Ask Planned;Asked';
    public static final String OUTCOME_OPEN = 'Open';
    public static final String OUTCOME_WON = 'Won';
    public static final String OUTCOME_DECLINED = 'Declined';
    public static final String OUTCOME_WITHDRAWN = 'Withdrawn';
    public static final Set<String> CLOSED_OUTCOMES = new Set<String>{
        OUTCOME_WON,
        OUTCOME_DECLINED,
        OUTCOME_WITHDRAWN
    };

    /** The longest stage name an ask can hold (the length of `Stage__c`). */
    private static final Integer STAGE_LENGTH = 80;

    /**
     * The stages in a setting value, in order: split on semicolons or line breaks, trimmed, empty
     * entries dropped, and a name repeated with different capitals kept once, as first written.
     */
    public static List<String> parse(String value) {
        List<String> stages = new List<String>();
        if (String.isBlank(value)) {
            return stages;
        }
        Set<String> seen = new Set<String>();
        for (String part : value.split('[;\\n\\r]')) {
            String stage = part.trim().left(STAGE_LENGTH).trim();
            if (String.isBlank(stage) || seen.contains(stage.toLowerCase())) {
                continue;
            }
            seen.add(stage.toLowerCase());
            stages.add(stage);
        }
        return stages;
    }

    /** The organization's stages: the setting, or the shipped list when it is empty. */
    public static List<String> stages() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        List<String> configured = parse(settings == null ? null : settings.Ask_Stages__c);
        return configured.isEmpty() ? parse(DEFAULT_STAGES) : configured;
    }

    /**
     * The stage in the list that a typed value names, ignoring capitals, spelled as the list
     * spells it; null when the list has no such stage.
     */
    public static String matchStage(String value, List<String> stages) {
        if (String.isBlank(value)) {
            return null;
        }
        String wanted = value.trim().toLowerCase();
        for (String stage : stages) {
            if (stage.toLowerCase() == wanted) {
                return stage;
            }
        }
        return null;
    }

    /**
     * Applies R-SO2 to R-SO4 to asks about to be saved. `oldById` is null on insert. A stage is
     * checked only when the ask is new or its stage changed, so taking a stage out of the list
     * never blocks other edits to the asks still in it.
     */
    public static void beforeSave(List<SObject> records, Map<Id, SObject> oldById) {
        if (records == null || records.isEmpty()) {
            return;
        }
        List<String> stages = null;
        Date today = System.today();
        for (SObject record : records) {
            Ask__c ask = (Ask__c) record;
            Ask__c old = oldById == null ? null : (Ask__c) oldById.get(ask.Id);
            if (stages == null) {
                stages = stages();
            }
            applyStage(ask, old, stages, today);
            applyOutcome(ask, today);
        }
    }

    private static void applyStage(Ask__c ask, Ask__c old, List<String> stages, Date today) {
        if (String.isBlank(ask.Stage__c)) {
            ask.Stage__c = stages[0];
        } else if (old == null || ask.Stage__c != old.Stage__c) {
            String matched = matchStage(ask.Stage__c, stages);
            if (matched == null) {
                ask.addError(
                    Ask__c.Stage__c,
                    String.format(
                        Label.Giving_Ask_ErrorStageNotInList,
                        new List<Object>{ ask.Stage__c, String.join(stages, ', ') }
                    )
                );
                return;
            }
            ask.Stage__c = matched;
        }
        Boolean stageChanged = old != null && ask.Stage__c != old.Stage__c;
        if (stageChanged || (old == null && ask.Stage_Changed_Date__c == null)) {
            ask.Stage_Changed_Date__c = today;
        }
    }

    private static void applyOutcome(Ask__c ask, Date today) {
        if (String.isBlank(ask.Outcome__c)) {
            ask.Outcome__c = OUTCOME_OPEN;
        }
        if (ask.Outcome__c == OUTCOME_OPEN) {
            ask.Closed_Date__c = null;
        } else if (ask.Closed_Date__c == null) {
            ask.Closed_Date__c = today;
        }
    }
}
