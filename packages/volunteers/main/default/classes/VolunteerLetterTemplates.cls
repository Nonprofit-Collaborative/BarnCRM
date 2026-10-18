/**
 * The volunteer letter templates the package ships (canonical model Section 29U, R-VL5): copied
 * from `Volunteer_Letter_Template_Default__mdt` into `Volunteer_Letter_Template__c` at install
 * and at every upgrade, never changing a template the org already has (plan Section 4.8).
 */
public with sharing class VolunteerLetterTemplates {
    public static final String TYPE_HOURS_LETTER = 'Hours letter';
    public static final String TYPE_CERTIFICATE = 'Certificate';
    private static final String INSTALL_CONTEXT = 'VolunteerLetterTemplates.installDefaults';

    /**
     * For the post-install script: copies each shipped template whose key the org does not
     * have, Active when its type has no active template. Never throws, so an install cannot fail
     * on it; a failure goes to the Error Log.
     *
     * System mode: the install runs as the platform's package user, who holds no permission
     * set, and every value written comes from packaged custom metadata.
     *
     * @return the templates created, empty when there were none to create or the step failed
     */
    public static List<Volunteer_Letter_Template__c> installDefaultsDuringInstall() {
        try {
            Set<String> keys = new Set<String>();
            Set<String> activeTypes = new Set<String>();
            for (Volunteer_Letter_Template__c existing : [
                SELECT Template_Key__c, Type__c, Active__c
                FROM Volunteer_Letter_Template__c
                WITH SYSTEM_MODE
            ]) {
                keys.add(existing.Template_Key__c);
                if (existing.Active__c) {
                    activeTypes.add(existing.Type__c);
                }
            }
            List<Volunteer_Letter_Template__c> created = new List<Volunteer_Letter_Template__c>();
            for (Volunteer_Letter_Template_Default__mdt shipped : [
                SELECT DeveloperName, Template_Name__c, Letter_Type__c, Body__c
                FROM Volunteer_Letter_Template_Default__mdt
                WITH SYSTEM_MODE
                ORDER BY DeveloperName
            ]) {
                if (keys.contains(shipped.DeveloperName) || String.isBlank(shipped.Body__c)) {
                    continue;
                }
                created.add(
                    new Volunteer_Letter_Template__c(
                        Name = shipped.Template_Name__c,
                        Type__c = shipped.Letter_Type__c,
                        Body__c = shipped.Body__c,
                        Template_Key__c = shipped.DeveloperName,
                        // True only when the type had no active template yet.
                        Active__c = activeTypes.add(shipped.Letter_Type__c)
                    )
                );
            }
            Database.insert(created, true, AccessLevel.SYSTEM_MODE);
            return created;
        } catch (Exception failed) {
            ErrorLogger.log(failed, INSTALL_CONTEXT);
            return new List<Volunteer_Letter_Template__c>();
        }
    }
}
