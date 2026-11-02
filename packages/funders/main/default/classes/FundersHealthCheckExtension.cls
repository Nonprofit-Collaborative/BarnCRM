/**
 * The Funders module's Health Check findings (canonical model 29ZH, R-GN7; ADR-0057's extension
 * seam). Core finds this class by name (`HealthCheckExtensions.EXTENSION_CLASSES`) and folds the
 * findings into its one report.
 *
 * Open grant applications past their deadline: a grant at Prospect, Letter of Inquiry or Invited
 * to Apply whose Application Deadline has passed. Overdue grant requirements (29ZI, R-GQ5): an
 * open requirement whose Due Date has passed. Asked only of a viewer who may manage settings,
 * and not while the module is turned off. A check that throws becomes a single "check failed"
 * finding.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class FundersHealthCheckExtension implements HealthCheckExtension {
    @TestVisible
    private static final String KEY_PAST_DEADLINE = 'funders_applications_past_deadline';
    @TestVisible
    private static final String KEY_OVERDUE = 'funders_requirements_overdue';

    /** Counts stop here, and the finding says "more than" this many. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many example records a finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    @NamespaceAccessible
    public FundersHealthCheckExtension() {
        // Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
    }

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        if (
            !HealthCheckService.canManageSettings() ||
            ModuleManagerService.turnedOff()
                .contains(FundersAccessSync.MODULE_NAME.toLowerCase()) ||
            !Schema.SObjectType.Grant__c.isAccessible()
        ) {
            return found;
        }
        try {
            HealthCheckService.Finding finding = pastDeadline();
            if (finding != null) {
                found.add(finding);
            }
        } catch (Exception e) {
            found.add(HealthCheckService.checkFailed(KEY_PAST_DEADLINE, e));
        }
        if (!Schema.SObjectType.Grant_Requirement__c.isAccessible()) {
            return found;
        }
        try {
            HealthCheckService.Finding finding = overdueRequirements();
            if (finding != null) {
                found.add(finding);
            }
        } catch (Exception e) {
            found.add(HealthCheckService.checkFailed(KEY_OVERDUE, e));
        }
        return found;
    }

    /** R-GQ5: open requirements whose due date has passed. */
    private static HealthCheckService.Finding overdueRequirements() {
        Date today = Date.today();
        Integer cap = countCap + 1;
        List<Grant_Requirement__c> late = [
            SELECT Id, Name
            FROM Grant_Requirement__c
            WHERE Status__c IN :GrantRequirementService.OPEN_STATUSES AND Due_Date__c < :today
            WITH USER_MODE
            ORDER BY Due_Date__c, Name
            LIMIT :cap
        ];
        if (late.isEmpty()) {
            return null;
        }
        return finding(
            KEY_OVERDUE,
            late,
            Label.Funders_HealthCheck_OverdueTitleOne,
            Label.Funders_HealthCheck_OverdueTitle,
            Label.Funders_HealthCheck_OverdueDetail
        );
    }

    private static HealthCheckService.Finding pastDeadline() {
        Date today = Date.today();
        Integer cap = countCap + 1;
        List<Grant__c> late = [
            SELECT Id, Name
            FROM Grant__c
            WHERE Stage__c IN :GrantService.BEFORE_SUBMITTING AND Application_Deadline__c < :today
            WITH USER_MODE
            ORDER BY Application_Deadline__c, Name
            LIMIT :cap
        ];
        if (late.isEmpty()) {
            return null;
        }
        return finding(
            KEY_PAST_DEADLINE,
            late,
            Label.Funders_HealthCheck_PastDeadlineTitleOne,
            Label.Funders_HealthCheck_PastDeadlineTitle,
            Label.Funders_HealthCheck_PastDeadlineDetail
        );
    }

    /** One finding over the records found, linking the first few. */
    @TestVisible
    private static HealthCheckService.Finding finding(
        String key,
        List<SObject> records,
        String titleOne,
        String titleMany,
        String detail
    ) {
        Integer howMany = records.size();
        String counted = howMany > countCap
            ? String.format(
                  Label.Core_HealthCheck_OrphansMoreThan,
                  new List<Object>{ countCap.format() }
              )
            : howMany.format();
        List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
        for (Integer i = 0; i < howMany && i < LINKS_SHOWN; i++) {
            links.add(new HealthCheckService.Link(records[i]));
        }
        return new HealthCheckService.Finding(
                key,
                howMany == 1 ? titleOne : String.format(titleMany, new List<Object>{ counted }),
                detail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withLinks(links);
    }
}
