/**
 * The class Core finds by name (in `HealthCheckExtensions.EXTENSION_CLASSES`) and calls to add
 * Mirror's findings to the one Health Check report (ADR-0057, as the ADR on the Opportunity
 * mirror amends it; X-01, R-OM8).
 *
 * One finding per mirror, for the Opportunity mirror and the Gift Transaction mirror (X-07): its
 * nightly run is scheduled, a direction is chosen and the automation is switched on, yet no run
 * has completed for more than two days. The run executes
 * as the person who scheduled it, so when that person is deactivated or loses access every run
 * fails before it starts and nothing else says so. Asked only of a viewer who may manage
 * settings, as Core's own settings checks are.
 *
 * `@NamespaceAccessible` for the reason `GivingHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorHealthCheckExtension implements HealthCheckExtension {
    public static final String MIRROR_STALE_KEY = 'opportunity_mirror_not_run';
    public static final String GIFT_TRANSACTION_MIRROR_STALE_KEY = 'gift_transaction_mirror_not_run';
    private static final Integer STALE_DAYS = 2;

    /** Test seam: the moment the report is read. */
    @TestVisible
    private static Datetime nowForTest;

    @NamespaceAccessible
    public MirrorHealthCheckExtension() {
        return;
    }

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        for (
            HealthCheckService.Finding stale : new List<HealthCheckService.Finding>{
                staleMirrorRun(),
                staleGiftTransactionMirrorRun()
            }
        ) {
            if (stale != null) {
                found.add(stale);
            }
        }
        return found;
    }

    private static HealthCheckService.Finding staleMirrorRun() {
        if (
            !HealthCheckService.canManageSettings() ||
            !OpportunityMirrorService.isAvailable() ||
            OpportunityMirrorService.direction() == OpportunityMirrorService.OFF ||
            !AutomationControl.isEnabled(OpportunityMirrorService.AUTOMATION_NAME)
        ) {
            return null;
        }
        Datetime since = staleSince(
            OpportunityMirrorSchedulable.scheduledAt(),
            Mirror_Settings__c.getOrgDefaults()?.Opportunity_Mirror_Last_Run__c
        );
        return since == null
            ? null
            : new HealthCheckService.Finding(
                  MIRROR_STALE_KEY,
                  Label.Mirror_HealthCheck_MirrorNotRunTitle,
                  String.format(
                      Label.Mirror_HealthCheck_MirrorNotRunDetail,
                      new List<Object>{ since.format() }
                  ),
                  HealthCheckService.SEVERITY_WARNING,
                  HealthCheckService.CATEGORY_SETTINGS
              );
    }

    /** The same finding for the Gift Transaction mirror (X-07, R-GT6). */
    private static HealthCheckService.Finding staleGiftTransactionMirrorRun() {
        if (
            !HealthCheckService.canManageSettings() ||
            !GiftTransactionMirrorService.isOn() ||
            !AutomationControl.isEnabled(GiftTransactionMirrorService.AUTOMATION_NAME)
        ) {
            return null;
        }
        Datetime since = staleSince(
            GiftTransactionMirrorSchedulable.scheduledAt(),
            Mirror_Settings__c.getOrgDefaults()?.Gift_Transaction_Mirror_Last_Run__c
        );
        return since == null
            ? null
            : new HealthCheckService.Finding(
                  GIFT_TRANSACTION_MIRROR_STALE_KEY,
                  Label.Mirror_HealthCheck_GiftTransactionMirrorNotRunTitle,
                  String.format(
                      Label.Mirror_HealthCheck_GiftTransactionMirrorNotRunDetail,
                      new List<Object>{ since.format() }
                  ),
                  HealthCheckService.SEVERITY_WARNING,
                  HealthCheckService.CATEGORY_SETTINGS
              );
    }

    /**
     * Since when a scheduled run has not completed, or null when it is not scheduled or completed
     * within the last two days. A run recorded before the job was scheduled says nothing about
     * this schedule.
     */
    private static Datetime staleSince(Datetime scheduledAt, Datetime lastRun) {
        if (scheduledAt == null) {
            return null;
        }
        Datetime since = lastRun == null || lastRun < scheduledAt ? scheduledAt : lastRun;
        Datetime now = nowForTest != null ? nowForTest : System.now();
        return since.addDays(STALE_DAYS) > now ? null : since;
    }
}
