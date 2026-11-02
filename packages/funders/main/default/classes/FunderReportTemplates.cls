/**
 * The funder report templates the package ships (canonical model Section 29ZO, R-FT3): copied
 * from `Funder_Report_Template_Default__mdt` into `Funder_Report_Template__c` at install, at every
 * upgrade and by Finish Setup, never changing a template the org already has (plan Section 4.8).
 * The Volunteers letter template pattern (`VolunteerLetterTemplates`), restated so Funders does
 * not need Volunteers.
 */
public with sharing class FunderReportTemplates {
    private static final String INSTALL_CONTEXT = 'FunderReportTemplates.installDefaults';

    /**
     * For the post-install script: copies each shipped template whose key the org does not have,
     * active. Never throws, so an install cannot fail on it; a failure goes to the Error Log.
     *
     * System mode: the install runs as the platform's package user, who holds no permission set,
     * and every value written comes from packaged custom metadata.
     *
     * @return the templates created, empty when there were none to create or the step failed
     */
    public static List<Funder_Report_Template__c> installDefaultsDuringInstall() {
        try {
            Set<String> keys = new Set<String>();
            for (Funder_Report_Template__c existing : [
                SELECT Template_Key__c
                FROM Funder_Report_Template__c
                WHERE Template_Key__c != NULL
                WITH SYSTEM_MODE
            ]) {
                keys.add(existing.Template_Key__c.toLowerCase());
            }
            List<Funder_Report_Template__c> created = new List<Funder_Report_Template__c>();
            for (Funder_Report_Template_Default__mdt shipped : [
                SELECT DeveloperName, Template_Name__c, Body__c
                FROM Funder_Report_Template_Default__mdt
                WITH SYSTEM_MODE
                ORDER BY DeveloperName
            ]) {
                if (
                    keys.contains(shipped.DeveloperName.toLowerCase()) ||
                    String.isBlank(shipped.Body__c)
                ) {
                    continue;
                }
                created.add(
                    new Funder_Report_Template__c(
                        Name = shipped.Template_Name__c,
                        Body__c = shipped.Body__c,
                        Template_Key__c = shipped.DeveloperName,
                        Active__c = true
                    )
                );
            }
            Database.insert(created, true, AccessLevel.SYSTEM_MODE);
            return created;
        } catch (Exception failed) {
            ErrorLogger.log(failed, INSTALL_CONTEXT);
            return new List<Funder_Report_Template__c>();
        }
    }
}
