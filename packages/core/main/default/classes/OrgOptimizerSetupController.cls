/**
 * Org Optimizer's Unused setup section (ADR-NEXT org-optimizer-and-data-manager-pages, admin
 * guide org-optimizer.md): setup that nobody seems to use any more, so an administrator can
 * decide whether to tidy it up. Users who have not logged in for 90 days, permission sets with
 * nobody assigned, reports not run for a year, email templates never used, flows left
 * inactive, and scheduled jobs owned by inactive users.
 *
 * Read only: it changes nothing and links each finding to its Setup page. Requires Manage
 * BarnCRM Settings (owner decision 2026-10-13: these checks are admin only). Every query is
 * dynamic and runs in user mode, so an org that hides one of these objects from the person, or
 * lacks one, reports that check as "could not check" instead of failing the section.
 */
public with sharing class OrgOptimizerSetupController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';
    /** The most rows read per check; above it the page says "more than". */
    @TestVisible
    private static final Integer COUNT_CAP = 1000;
    /** How many names each check shows as examples. */
    private static final Integer EXAMPLES = 5;
    /** A user who has not logged in for this many days counts as inactive. */
    private static final Integer LOGIN_DAYS = 90;
    /** A report not run for this many days counts as stale. */
    private static final Integer REPORT_DAYS = 365;
    /** Templates and flows younger than this are left out: they may be new work. */
    private static final Integer NEW_DAYS = 90;

    @TestVisible
    private static Boolean permissionOverride;
    /** A check key whose query is made to fail, to test "could not check". */
    @TestVisible
    private static String failCheck;

    /** One check's result. */
    public class Finding {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public Integer count;
        /** True when the count stopped at the cap. */
        @AuraEnabled
        public Boolean moreThan = false;
        /** True when the query could not run; count is then null. */
        @AuraEnabled
        public Boolean failed = false;
        @AuraEnabled
        public List<String> examples = new List<String>();
        @AuraEnabled
        public String setupUrl;
    }

    public class Result {
        @AuraEnabled
        public List<Finding> findings = new List<Finding>();
        @AuraEnabled
        public Integer countCap = COUNT_CAP;
        @AuraEnabled
        public Integer loginDays = LOGIN_DAYS;
        @AuraEnabled
        public Integer reportDays = REPORT_DAYS;
    }

    private class Check {
        String key;
        String soql;
        /** The field that names a row; a dotted name reads through one relationship. */
        String nameField;
        String setupUrl;

        Check(String key, String soql, String nameField, String setupUrl) {
            this.key = key;
            this.soql = soql;
            this.nameField = nameField;
            this.setupUrl = setupUrl;
        }
    }

    @AuraEnabled
    public static Result getFindings() {
        if (!hasPermission()) {
            throw asAuraError(Label.Core_OrgOptimizer_ErrorNoPermission);
        }
        Datetime now = Datetime.now();
        Map<String, Object> binds = new Map<String, Object>{
            'loginCutoff' => now.addDays(-LOGIN_DAYS),
            'reportCutoff' => now.addDays(-REPORT_DAYS),
            'newCutoff' => now.addDays(-NEW_DAYS),
            'readUpTo' => COUNT_CAP + 1
        };
        Result result = new Result();
        for (Check check : checks()) {
            result.findings.add(run(check, binds));
        }
        return result;
    }

    private static List<Check> checks() {
        return new List<Check>{
            new Check(
                'inactiveUsers',
                'SELECT Name FROM User WHERE IsActive = true AND UserType = \'Standard\'' +
                ' AND (LastLoginDate = null OR LastLoginDate < :loginCutoff) ORDER BY Name',
                'Name',
                '/lightning/setup/ManageUsers/home'
            ),
            new Check(
                'unassignedPermissionSets',
                'SELECT Label FROM PermissionSet WHERE IsOwnedByProfile = false AND IsCustom = true' +
                    ' AND NamespacePrefix = null AND Type = \'Regular\'' +
                    ' AND Id NOT IN (SELECT PermissionSetId FROM PermissionSetAssignment)' +
                    // A set inside a permission set group is assigned through the group.
                    ' AND Id NOT IN (SELECT PermissionSetId FROM PermissionSetGroupComponent) ORDER BY Label',
                'Label',
                '/lightning/setup/PermSets/home'
            ),
            new Check(
                'staleReports',
                'SELECT Name FROM Report WHERE NamespacePrefix = null' +
                ' AND (LastRunDate = null OR LastRunDate < :reportCutoff) ORDER BY Name',
                'Name',
                '/lightning/o/Report/home'
            ),
            new Check(
                'unusedEmailTemplates',
                'SELECT Name FROM EmailTemplate WHERE NamespacePrefix = null' +
                ' AND (TimesUsed = null OR TimesUsed = 0) AND CreatedDate < :newCutoff ORDER BY Name',
                'Name',
                '/lightning/setup/CommunicationTemplatesEmail/home'
            ),
            new Check(
                'inactiveFlows',
                'SELECT Label FROM FlowDefinitionView WHERE IsActive = false' +
                ' AND NamespacePrefix = null AND LastModifiedDate < :newCutoff ORDER BY Label',
                'Label',
                '/lightning/setup/Flows/home'
            ),
            new Check(
                'jobsOfInactiveUsers',
                'SELECT CronJobDetail.Name FROM CronTrigger' +
                    ' WHERE State NOT IN (\'DELETED\', \'COMPLETE\')' +
                    ' AND OwnerId IN (SELECT Id FROM User WHERE IsActive = false)' +
                    ' ORDER BY CronJobDetail.Name',
                'CronJobDetail.Name',
                '/lightning/setup/ScheduledJobs/home'
            )
        };
    }

    private static Finding run(Check check, Map<String, Object> binds) {
        Finding finding = new Finding();
        finding.key = check.key;
        finding.setupUrl = check.setupUrl;
        try {
            String soql = check.key == failCheck ? check.soql + ' BROKEN' : check.soql;
            List<SObject> rows = Database.queryWithBinds(
                soql + ' LIMIT :readUpTo',
                binds,
                AccessLevel.USER_MODE
            );
            finding.moreThan = rows.size() > COUNT_CAP;
            finding.count = Math.min(rows.size(), COUNT_CAP);
            for (Integer index = 0; index < Math.min(rows.size(), EXAMPLES); index++) {
                finding.examples.add(nameOf(rows[index], check.nameField));
            }
        } catch (Exception caught) {
            // One check that cannot run (no access, or an object this org lacks) must not hide
            // the others; the page says "could not check" for it.
            finding.failed = true;
            finding.count = null;
            finding.examples.clear();
        }
        return finding;
    }

    private static String nameOf(SObject row, String field) {
        if (field.contains('.')) {
            SObject parent = row.getSObject(field.substringBefore('.'));
            return parent == null ? null : String.valueOf(parent.get(field.substringAfter('.')));
        }
        return String.valueOf(row.get(field));
    }

    private static Boolean hasPermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission(PERMISSION);
    }

    private static AuraHandledException asAuraError(String message) {
        AuraHandledException error = new AuraHandledException(message);
        error.setMessage(message);
        return error;
    }
}
