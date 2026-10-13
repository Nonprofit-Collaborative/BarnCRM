/**
 * The last full Health Check result, kept so BarnCRM Home can show it instead of running every
 * check on each load (ADMIN-7, ADR-0106 health-check-on-home-shows-the-last-result).
 *
 * The one place that records and reads it. A page that wants "last result plus Run now" sets
 * the panel's lastResultFirst property; nothing else needs to know how the result is kept.
 *
 * The run record is package owned bookkeeping saved through OrgSettingsSystemWriter without an
 * audit row, like the other run stamps (ADR-0021). Only a run by someone with Manage BarnCRM
 * Settings is kept, because anyone else's run skips the access checks.
 */
public with sharing class HealthCheckLastRun {
    /** What the panel shows before anyone clicks Run now. */
    public class Summary {
        /** When Health Check last ran in full, or null when it never has. */
        @AuraEnabled
        public Datetime ranAt;
        /** The counts as a sentence in the reader's language, or null when it never ran. */
        @AuraEnabled
        public String result;
        @AuraEnabled
        public Integer errors;
        @AuraEnabled
        public Integer warnings;
        @AuraEnabled
        public Integer infos;
    }

    /** Records the report's time and counts, when it ran for someone who sees every check. */
    public static void record(HealthCheckService.Report report) {
        if (report == null || report.canManageSettings != true) {
            return;
        }
        Integer errors = 0;
        Integer warnings = 0;
        Integer infos = 0;
        for (HealthCheckService.Finding finding : report.findings) {
            if (HealthCheckService.SEVERITY_ERROR.equals(finding.severity)) {
                errors++;
            } else if (HealthCheckService.SEVERITY_WARNING.equals(finding.severity)) {
                warnings++;
            } else {
                infos++;
            }
        }
        OrgSettingsSystemWriter.save(
            new Map<Schema.SObjectField, Object>{
                BarnCRM_Settings__c.Health_Check_Last_Run__c => Datetime.now(),
                BarnCRM_Settings__c.Health_Check_Last_Result__c => errors +
                ',' +
                warnings +
                ',' +
                infos
            }
        );
    }

    /** The last recorded result; every field is null when Health Check has never run. */
    public static Summary read() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        Summary summary = new Summary();
        summary.ranAt = settings.Health_Check_Last_Run__c;
        List<String> counts = String.isBlank(settings.Health_Check_Last_Result__c)
            ? new List<String>()
            : settings.Health_Check_Last_Result__c.split(',');
        if (summary.ranAt == null || counts.size() != 3) {
            summary.ranAt = null;
            return summary;
        }
        try {
            summary.errors = Integer.valueOf(counts[0].trim());
            summary.warnings = Integer.valueOf(counts[1].trim());
            summary.infos = Integer.valueOf(counts[2].trim());
        } catch (TypeException unreadable) {
            // A value nobody can read is shown as "has not run yet", and the next run fixes it.
            return new Summary();
        }
        summary.result = String.format(
            System.Label.Core_HealthCheck_LastResult,
            new List<Object>{ summary.errors, summary.warnings, summary.infos }
        );
        return summary;
    }
}
