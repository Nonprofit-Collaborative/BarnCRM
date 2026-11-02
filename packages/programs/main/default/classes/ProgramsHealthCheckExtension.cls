/**
 * The Programs module's Health Check findings (canonical model 29ZA, "On a person, Health Check
 * and sample data"; ADR-0057's extension seam). Core finds this class by name
 * (`HealthCheckExtensions.EXTENSION_CLASSES`) and folds the findings into its one report.
 *
 * Two questions. First: enrollments still open (Applied or Enrolled) in a program that has
 * ended, by Status Completed or by an End Date in the past. They still count as open (R-EN2), so
 * the person cannot be enrolled again, and they stay on the roster. Second (QA-F5): whether the
 * org also has Nonprofit Cloud Program Management, whose standard Program and Program Enrollment
 * objects are separate from BarnCRM's, an information finding that says the two do not share
 * records. Found by describe, so Programs depends on nothing Nonprofit Cloud ships.
 *
 * Asked only of a viewer who may manage settings, and not while the module is turned off. A check
 * that throws becomes a single "check failed" finding.
 *
 * `@NamespaceAccessible`, public, with a public no-argument constructor, because Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class ProgramsHealthCheckExtension implements HealthCheckExtension {
    @TestVisible
    private static final String KEY = 'program_enrollments_open_after_end';
    @TestVisible
    private static final String NPC_KEY = 'nonprofit_cloud_program_management_present';

    /** The Nonprofit Cloud Program Management objects, looked up by name only. */
    private static final String NPC_PROGRAM = 'Program'; // detection-only: describe key, reported only
    private static final String NPC_ENROLLMENT = 'ProgramEnrollment'; // detection-only: describe key, reported only
    private static final List<String> NPC_PROGRAM_OBJECTS = new List<String>{
        NPC_PROGRAM,
        NPC_ENROLLMENT
    };

    /** Test seam: stands in for the org's answer to whether those objects are here. */
    @TestVisible
    private static Boolean npcProgramsOverride;

    /** Counts stop here, and the finding says "more than" this many. */
    @TestVisible
    private static Integer countCap = 1000;

    /** How many example enrollments the finding links to. */
    private static final Integer LINKS_SHOWN = 5;

    @NamespaceAccessible
    public ProgramsHealthCheckExtension() {
        // Built by name from Core (HealthCheckExtensions), so it needs a public constructor.
    }

    public List<HealthCheckService.Finding> findings() {
        List<HealthCheckService.Finding> found = new List<HealthCheckService.Finding>();
        if (
            !HealthCheckService.canManageSettings() ||
            ModuleManagerService.turnedOff().contains(ProgramsAccessSync.MODULE_NAME.toLowerCase())
        ) {
            return found;
        }
        if (Schema.SObjectType.Enrollment__c.isAccessible()) {
            try {
                HealthCheckService.Finding finding = openAfterEnd();
                if (finding != null) {
                    found.add(finding);
                }
            } catch (Exception e) {
                found.add(HealthCheckService.checkFailed(KEY, e));
            }
        }
        if (hasNonprofitCloudPrograms()) {
            found.add(
                new HealthCheckService.Finding(
                    NPC_KEY,
                    Label.Programs_HealthCheck_NpcProgramsTitle,
                    Label.Programs_HealthCheck_NpcProgramsDetail,
                    HealthCheckService.SEVERITY_INFO,
                    HealthCheckService.CATEGORY_ORG_SHAPE
                )
            );
        }
        return found;
    }

    /** True when every Nonprofit Cloud Program Management object named above is in the org. */
    @TestVisible
    private static Boolean hasNonprofitCloudPrograms() {
        if (npcProgramsOverride != null) {
            return npcProgramsOverride;
        }
        Map<String, Schema.SObjectType> described = NamespaceUtil.globalDescribe();
        for (String objectName : NPC_PROGRAM_OBJECTS) {
            if (!described.containsKey(objectName.toLowerCase())) {
                return false;
            }
        }
        return true;
    }

    private static HealthCheckService.Finding openAfterEnd() {
        Date today = Date.today();
        Integer cap = countCap + 1;
        List<Enrollment__c> open = [
            SELECT Id, Name
            FROM Enrollment__c
            WHERE
                Stage__c IN :EnrollmentService.OPEN_STAGES
                AND (Program__r.Status__c = 'Completed'
                OR Program__r.End_Date__c < :today)
            WITH USER_MODE
            ORDER BY Program__r.Name, Name
            LIMIT :cap
        ];
        if (open.isEmpty()) {
            return null;
        }
        Integer howMany = open.size();
        String counted = howMany > countCap
            ? String.format(
                  Label.Programs_HealthCheck_MoreThan,
                  new List<Object>{ countCap.format() }
              )
            : howMany.format();
        List<HealthCheckService.Link> links = new List<HealthCheckService.Link>();
        for (Integer i = 0; i < howMany && i < LINKS_SHOWN; i++) {
            links.add(new HealthCheckService.Link(open[i]));
        }
        return new HealthCheckService.Finding(
                KEY,
                howMany == 1
                    ? Label.Programs_HealthCheck_OpenAfterEndTitleOne
                    : String.format(
                          Label.Programs_HealthCheck_OpenAfterEndTitle,
                          new List<Object>{ counted }
                      ),
                Label.Programs_HealthCheck_OpenAfterEndDetail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_SETTINGS
            )
            .withLinks(links);
    }
}
