/**
 * The Health Check questions about people: who administers Open Impact and who cannot see
 * it at all (plan Section 4.8, feature C-11). Who holds Giving's receipt lock override is
 * Giving's question, asked through its Health Check extension (ADR-0059).
 *
 * Every question here is a question about the whole org, and Salesforce shows an ordinary
 * user only their own access, so a count taken without the administrator permission is
 * confidently wrong. HealthCheckService.steps() therefore runs these only for a viewer who
 * may manage settings, and runs NeedsAdminCheck for everyone else. The counts arrive as an
 * AccessCounts so a test can choose them.
 *
 * Every finding is created exactly as HealthCheckService created it before ADR-0039 moved
 * it here: same keys, same severities, same categories, same labels, same fix targets.
 */
public with sharing class HealthCheckAccessChecks {
    /** Whether anybody at all can administer Open Impact. */
    public class NoAdminCheck implements HealthCheckService.Check {
        private final HealthCheckService.AccessCounts counts;

        public NoAdminCheck(HealthCheckService.AccessCounts counts) {
            this.counts = counts;
        }

        public HealthCheckService.Finding run() {
            return noAdminFinding(counts);
        }
    }

    /** How many active people hold no packaged role and so cannot see the app. */
    public class UsersWithoutAccessCheck implements HealthCheckService.Check {
        private final HealthCheckService.AccessCounts counts;

        public UsersWithoutAccessCheck(HealthCheckService.AccessCounts counts) {
            this.counts = counts;
        }

        public HealthCheckService.Finding run() {
            return usersWithoutAccessFinding(counts);
        }
    }

    /**
     * What a viewer without the administrator permission is told in place of the three
     * checks above, so that silence is never read as a pass.
     */
    public class NeedsAdminCheck implements HealthCheckService.Check {
        public HealthCheckService.Finding run() {
            return new HealthCheckService.Finding(
                'access_checks_need_admin',
                System.Label.Core_HealthCheck_AccessNeedsAdminTitle,
                System.Label.Core_HealthCheck_AccessNeedsAdminDetail,
                HealthCheckService.SEVERITY_INFO,
                HealthCheckService.CATEGORY_ACCESS
            );
        }
    }

    private static HealthCheckService.Finding noAdminFinding(
        HealthCheckService.AccessCounts counts
    ) {
        Integer admins = counts.administrators();
        if (admins > 0) {
            return null;
        }

        return new HealthCheckService.Finding(
                'no_nonprofit_admin',
                System.Label.Core_HealthCheck_NoAdminTitle,
                System.Label.Core_HealthCheck_NoAdminDetail,
                HealthCheckService.SEVERITY_ERROR,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, HealthCheckService.SECTION_ACCESS);
    }

    private static HealthCheckService.Finding usersWithoutAccessFinding(
        HealthCheckService.AccessCounts counts
    ) {
        Integer without = counts.usersWithoutAccess();
        if (without <= 0) {
            return null;
        }

        List<Object> count = new List<Object>{ String.valueOf(without) };
        return new HealthCheckService.Finding(
                'users_without_access',
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessTitle, count),
                String.format(System.Label.Core_HealthCheck_UsersWithoutAccessDetail, count),
                HealthCheckService.SEVERITY_WARNING,
                HealthCheckService.CATEGORY_ACCESS
            )
            .withFix(System.Label.Core_HealthCheck_AccessFix, HealthCheckService.SECTION_ACCESS);
    }
}
