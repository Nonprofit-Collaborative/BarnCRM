/**
 * The system mode writes behind the Automation page: the org default `Nonprofit_Settings__c`
 * record for the automation pause, and the Automation Setting rows materialized from the
 * shipped registry.
 *
 * ADR-0021 (system mode writes for package owned data) is the authority for this class and
 * names it as one of its writers. Two writes, each for its own reason:
 *
 * 1. The pause. A protected hierarchy custom setting takes no object or field permissions in a
 *    subscriber org: there is no way to grant a BarnCRM Admin field access to it. Writing the
 *    pause setting in user mode therefore fails for everyone who is not a system administrator,
 *    which is most of the people this feature is for. Nothing is read here and one field is
 *    written: the caller passes a datetime it computed from a number of hours it has already
 *    validated.
 * 2. The switch rows. Each row carries `Always_Runs__c`, which no packaged permission set may
 *    edit (ADR-0024: an automation that enforces a rule must not be made switchable by editing
 *    its row), so a user mode insert of a complete row is refused for everyone. The rows are
 *    written by the post-install scripts, where no permission set is assigned yet, and by the
 *    Health Check fix. Every value is copied from the package's own shipped registry by
 *    `AutomationControl`; nothing an administrator types reaches this class.
 *
 * The permission is enforced before this class is reached: `AutomationControl` writes the pause
 * only after `FeatureManagement.checkPermission('Manage_Nonprofit_Settings')` passes, and the
 * Health Check fix checks the same permission in `HealthCheckController` before it asks for the
 * switch rows. The post-install scripts run as the platform's install user, which the platform
 * itself authorizes.
 */
public without sharing class AutomationSettingsWriter {
    public static void savePausedUntil(Datetime pausedUntil) {
        // Through the shared writer: a pause is often the first thing saved after install, and
        // that first save must keep the shipped defaults (OrgSettingsSystemWriter).
        OrgSettingsSystemWriter.save(
            new Map<Schema.SObjectField, Object>{
                Nonprofit_Settings__c.Automation_Paused_Until__c => pausedUntil
            }
        );
    }

    /** Inserts switch rows materialized from the shipped registry. */
    public static void insertSwitches(List<Automation_Setting__c> switches) {
        if (switches == null || switches.isEmpty()) {
            return;
        }
        Database.insert(switches, AccessLevel.SYSTEM_MODE);
    }
}
