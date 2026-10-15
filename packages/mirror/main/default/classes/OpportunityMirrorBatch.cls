/**
 * A run of the Opportunity mirror (feature X-01, R-OM8), as the person who started or scheduled
 * it, in chunks. What it does follows the chosen direction:
 *
 * - Gifts to Opportunities: copies every gift in the totals that has no Opportunity yet, or, from
 *   the reconciliation page, every gift in the totals dated in a range (R-OM11).
 * - Opportunities to Gifts: makes a gift from every won Opportunity closed on or after the start
 *   date that no gift names (R-OM7).
 *
 * Refusals are gathered across the chunks and written when the run ends, one Warning per distinct
 * reason, with a summary at Info (R-OM6), so a nightly run over a refused rule writes one entry
 * rather than one per gift, and none per chunk.
 *
 * While automation is paused, or the Opportunity mirror is switched off on the Automation page, a
 * run does nothing and says so in one Info entry; the check is made when it starts and again for
 * each chunk (R-OM8). A run that is not a range records when it started and its summary on
 * Mirror Settings, for the page, for Health Check, and as the point from which the next run
 * rechecks linked gifts changed since.
 */
public with sharing class OpportunityMirrorBatch implements Database.Batchable<SObject>, Database.Stateful {
    public static final String CLASS_NAME = 'OpportunityMirrorBatch';
    /** Smaller than Campaign sync's: the org's own Opportunity automation runs on each chunk. */
    @TestVisible
    private static final Integer CHUNK_SIZE = 100;
    private static final String LOG_CONTEXT = 'Opportunity mirror: run';
    // Core's constant for this severity is not namespace accessible, so its value is repeated.
    private static final String SEVERITY_INFO = 'Info';

    private final String direction;
    private final Date fromDate;
    private final Date toDate;
    private final OpportunityMirrorService.Result totals = new OpportunityMirrorService.Result();
    private Datetime startedAt;
    /** Why chunks were left, when automation was paused or switched off during the run. */
    private String skipReason;
    private Boolean skippedAtStart = false;

    @TestVisible
    private OpportunityMirrorBatch(String direction, Date fromDate, Date toDate) {
        this.direction = direction;
        this.fromDate = fromDate;
        this.toDate = toDate;
    }

    /** Starts a run in the chosen direction and returns its job id, or null when it is off. */
    public static Id run() {
        String direction = OpportunityMirrorService.direction();
        if (direction == OpportunityMirrorService.OFF || !OpportunityMirrorService.isAvailable()) {
            return null;
        }
        return Database.executeBatch(new OpportunityMirrorBatch(direction, null, null), CHUNK_SIZE);
    }

    /** Copies again every gift in the totals dated in the range (Gifts to Opportunities only). */
    public static Id runRange(Date fromDate, Date toDate) {
        return Database.executeBatch(
            new OpportunityMirrorBatch(
                OpportunityMirrorService.GIFTS_TO_OPPORTUNITIES,
                fromDate,
                toDate
            ),
            CHUNK_SIZE
        );
    }

    /** Why a run must not work now, or null when it may. */
    private static String skipReason() {
        if (AutomationControl.isPaused()) {
            return Label.Mirror_OpportunityMirror_RunPaused;
        }
        if (!AutomationControl.isEnabled(OpportunityMirrorService.AUTOMATION_NAME)) {
            return Label.Mirror_OpportunityMirror_RunSwitchedOff;
        }
        return null;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        startedAt = System.now();
        skipReason = skipReason();
        if (skipReason != null) {
            skippedAtStart = true;
            return nothing();
        }
        if (direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS) {
            Date startDate = OpportunityGiftService.startDate();
            Set<Id> recordTypeIds = OpportunityGiftService.recordTypeIds();
            List<String> unknown = OpportunityGiftService.unknownRecordTypes();
            if (!unknown.isEmpty()) {
                // Once a run: a mistyped name otherwise matches nothing without a word.
                ErrorLogger.logMessage(
                    String.format(
                        Label.Mirror_OpportunityMirror_UnknownRecordTypes,
                        new List<Object>{ String.join(unknown, ', ') }
                    ),
                    LOG_CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            if (OpportunityGiftService.listsMasterRecordType()) {
                // Master is a real name, so it is not unknown, yet it matches no Opportunity.
                ErrorLogger.logMessage(
                    Label.Mirror_OpportunityMirror_MasterRecordType,
                    LOG_CONTEXT,
                    ErrorLogger.SEVERITY_WARNING
                );
            }
            if (recordTypeIds != null && recordTypeIds.isEmpty()) {
                // Nothing listed exists, and an org without record types has no field to filter.
                return nothing();
            }
            return Database.getQueryLocatorWithBinds(
                OpportunityMirrorSelector.wonOpportunitiesQuery(
                    OpportunityMirrorService.opportunityType().getDescribe().getName(),
                    OpportunityGiftService.opportunityFields(),
                    recordTypeIds != null
                ),
                // No start date, no Opportunity: a date no Opportunity closes on or after.
                new Map<String, Object>{
                    'startDate' => startDate == null ? Date.newInstance(4000, 12, 31) : startDate,
                    'recordTypeIds' => recordTypeIds
                },
                AccessLevel.USER_MODE
            );
        }
        Datetime lastRun = Mirror_Settings__c.getOrgDefaults()?.Opportunity_Mirror_Last_Run__c;
        return Database.getQueryLocatorWithBinds(
            OpportunityMirrorSelector.giftsToCopyQuery(fromDate != null, lastRun != null),
            new Map<String, Object>{
                'statuses' => OpportunityMirrorService.IN_TOTALS,
                'fromDate' => fromDate,
                'toDate' => toDate,
                'since' => lastRun
            },
            AccessLevel.USER_MODE
        );
    }

    private static Database.QueryLocator nothing() {
        return Database.getQueryLocator([SELECT Id FROM Gift__c WHERE Id = NULL WITH USER_MODE]);
    }

    public void execute(Database.BatchableContext context, List<SObject> scope) {
        // The direction may have changed since the run started; a run never works against it.
        String reason = skipReason();
        if (reason != null || OpportunityMirrorService.direction() != direction) {
            totals.skipped += scope.size();
            skipReason = skipReason == null ? reason : skipReason;
            return;
        }
        totals.add(
            direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS
                ? OpportunityGiftService.makeGifts(scope)
                : OpportunityMirrorService.syncSaved((List<Gift__c>) scope)
        );
    }

    public void finish(Database.BatchableContext context) {
        if (skippedAtStart) {
            ErrorLogger.logMessage(skipReason, LOG_CONTEXT, SEVERITY_INFO);
            return;
        }
        if (direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS) {
            totals.writeOpportunityRefusals();
        } else {
            totals.writeRefusals();
        }
        String summary = String.format(
            direction == OpportunityMirrorService.OPPORTUNITIES_TO_GIFTS
                ? Label.Mirror_OpportunityMirror_LogRunGifts
                : Label.Mirror_OpportunityMirror_LogRunOpportunities,
            new List<Object>{
                totals.created,
                totals.updated,
                totals.unchanged,
                totals.failed,
                totals.skipped
            }
        );
        ErrorLogger.logMessage(
            skipReason == null ? summary : summary + ' ' + skipReason,
            LOG_CONTEXT,
            SEVERITY_INFO
        );
        if (fromDate == null && skipReason == null) {
            MirrorSettingsWriter.recordOpportunityMirrorRun(startedAt, summary);
        }
    }
}
