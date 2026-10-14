/**
 * Runs an import undo's passes in one test transaction, in order, as the job would, carrying
 * what each pass found to the next (canonical model R-IB8, R-IB9). The job chains its passes
 * from each one's finish, which a test runs only once.
 *
 * A test can stop after the passes that come before the people's, to change something as the
 * platform would between two passes (a rollup set off by the gifts the undo deleted, saved by
 * the Automated Process user), then run the rest.
 *
 * Public and namespace accessible, never global (ADR-0017), so a module package's tests can
 * call it. Test only.
 */
@IsTest
@NamespaceAccessible
public class ImportUndoTestSupport {
    /** One undo's passes, run on demand. */
    @NamespaceAccessible
    public class Run {
        private ImportUndoBatch job;
        private final List<String> passes = ImportUndoBatch.passes();
        private Integer next = 0;

        /**
         * @param batchId the import batch to undo
         * @param total the count the person confirmed
         * @param undoStartedAt when Undo was pressed, to the second
         */
        @NamespaceAccessible
        public Run(Id batchId, Integer total, Datetime undoStartedAt) {
            job = new ImportUndoBatch(batchId, total, passes[0], 0, false, undoStartedAt);
        }

        /** Runs every pass before the people's: the restore, the judging, a module's own. */
        @NamespaceAccessible
        public void beforePeople() {
            while (next < passes.size() && passes[next] != ImportUndoBatch.PASS_CONTACTS) {
                runNext();
            }
        }

        /** Runs every pass not run yet, and finishes the undo. */
        @NamespaceAccessible
        public void rest() {
            while (next < passes.size()) {
                runNext();
            }
            job.finish(null);
        }

        /**
         * Queues the rest to run as a job of its own, with limits of its own, as the platform
         * runs each pass. Called between Test.startTest and Test.stopTest.
         */
        @NamespaceAccessible
        public void queueRest() {
            System.enqueueJob(new Rest(this));
        }

        private void runNext() {
            if (next > 0) {
                job = job.followedBy(passes[next]);
            }
            next++;
            Database.QueryLocatorIterator records = job.start(null).iterator();
            List<SObject> chunk = new List<SObject>();
            while (records.hasNext()) {
                chunk.add(records.next());
                if (chunk.size() == 100) {
                    job.execute(null, chunk);
                    chunk = new List<SObject>();
                }
            }
            if (!chunk.isEmpty()) {
                job.execute(null, chunk);
            }
        }
    }

    /** The rest of one undo's passes, as a job. */
    private class Rest implements Queueable {
        private final Run run;

        Rest(Run run) {
            this.run = run;
        }

        public void execute(QueueableContext context) {
            run.rest();
        }
    }
}
