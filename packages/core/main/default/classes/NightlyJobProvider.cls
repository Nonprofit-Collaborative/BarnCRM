/**
 * The seam a dependent package uses to have its nightly jobs counted and scheduled by Health
 * Check, without Core depending on it (ADR-NEXT, health-check-schedules-every-nightly-job; the
 * same shape as `HealthCheckExtension`, ADR-0057). Core finds an implementation by class name
 * with `Type.forName` in `NightlyJobs` and calls it only when it is installed.
 */
@NamespaceAccessible
public interface NightlyJobProvider {
    /**
     * The jobs this package wants scheduled in this org now. Only a job with one right answer
     * belongs here: a job whose running is the organization's choice (one that emails donors,
     * or one switched off by a setting) is left out. Never null.
     */
    List<NightlyJob> nightlyJobs();
}
