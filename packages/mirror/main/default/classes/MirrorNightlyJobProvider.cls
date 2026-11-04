/**
 * The class Core finds by name (in `NightlyJobs.PROVIDER_CLASSES`) to add Mirror's steps to the
 * one nightly run (ADR-NEXT nightly-job-dispatcher): the nightly run of the Opportunity mirror
 * and of the Gift Transaction mirror (X-07). Each step is in tonight's run only while that
 * mirror's direction is chosen and its object exists, and its page switches it on and off.
 *
 * `@NamespaceAccessible` for the reason `MirrorHealthCheckExtension` is: Core resolves it with
 * `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorNightlyJobProvider implements NightlyStepProvider {
    @NamespaceAccessible
    public MirrorNightlyJobProvider() {
        return;
    }

    public List<NightlyStep> nightlySteps() {
        return new List<NightlyStep>{
            OpportunityMirrorSchedulable.step(),
            GiftTransactionMirrorSchedulable.step()
        };
    }
}
