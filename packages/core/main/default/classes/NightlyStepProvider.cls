/**
 * The seam a dependent package uses to add its steps to BarnCRM's nightly run without Core
 * depending on it (ADR-NEXT nightly-job-dispatcher, the shape of ADR-0075 and ADR-0057). Core
 * finds an implementation by class name with `Type.forName` in `NightlyJobs` and calls it only
 * when it is installed.
 */
@NamespaceAccessible
public interface NightlyStepProvider {
    /**
     * Every nightly step this package has, on or off, built now so each reads its settings as
     * they are. Never null.
     */
    List<NightlyStep> nightlySteps();
}
