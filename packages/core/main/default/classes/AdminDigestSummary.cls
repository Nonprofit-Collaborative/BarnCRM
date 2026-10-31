/**
 * The admin summary half of the weekly digest (C-54, extends the error digest of C-23): what an
 * administrator would otherwise have to go and look for. Org limits at or above 80 percent,
 * BarnCRM data jobs that failed in the window, and duplicate suggestions waiting for review.
 * Setup changes (C-56) join it once the Setup Changes Log exists.
 *
 * Like the error digest it counts and names, and never copies a record's content: a failed job
 * is named by its record name and operation, and a duplicate suggestion is only counted. Every
 * read runs in user mode as the administrator who scheduled the digest.
 */
public with sharing class AdminDigestSummary {
    /** A limit is reported from this share of its allowance. */
    @TestVisible
    private static final Integer LIMIT_THRESHOLD_PERCENT = 80;
    /** How many failed jobs one digest names; the rest are counted. */
    @TestVisible
    private static final Integer JOBS_LISTED = 10;
    /** The most duplicate suggestions counted; above it the digest says "more than". */
    @TestVisible
    private static final Integer DUPLICATES_CAP = 1000;

    /** What the summary found. Everything is read once. */
    public class Summary {
        /** Limits at or above the threshold, one ready-made line each. */
        public List<String> limits = new List<String>();
        public Integer failedJobs = 0;
        public List<Import_Batch__c> failedJobList = new List<Import_Batch__c>();
        public Integer duplicatesWaiting = 0;
        public Boolean duplicatesCapped = false;

        /** True when there is something to say. */
        public Boolean hasContent() {
            return !limits.isEmpty() || failedJobs > 0 || duplicatesWaiting > 0;
        }
    }

    /** Reads the summary for the window the digest covers. */
    public static Summary build(Datetime after, Datetime upTo) {
        Summary summary = new Summary();
        for (
            OrgOptimizerStorageController.LimitUse use : OrgOptimizerStorageController.limitsAtOrAbove(
                LIMIT_THRESHOLD_PERCENT
            )
        ) {
            summary.limits.add(
                String.format(
                    System.Label.Core_AdminDigest_LimitLine,
                    new List<Object>{
                        use.name.replaceAll('([a-z])([A-Z])', '$1 $2'),
                        String.valueOf(use.percent),
                        String.valueOf(use.used),
                        String.valueOf(use.max)
                    }
                )
            );
        }
        summary.failedJobs = failedJobCount(after, upTo);
        if (summary.failedJobs > 0) {
            summary.failedJobList = failedJobs(after, upTo);
        }
        Integer waiting = DuplicateSelector.openSetCount(DUPLICATES_CAP + 1);
        summary.duplicatesCapped = waiting > DUPLICATES_CAP;
        summary.duplicatesWaiting = Math.min(waiting, DUPLICATES_CAP);
        return summary;
    }

    /** The summary's lines for the email body, ending with a blank line, or none when empty. */
    public static List<String> lines(Summary summary, String base) {
        List<String> lines = new List<String>();
        if (summary == null || !summary.hasContent()) {
            return lines;
        }
        lines.add(System.Label.Core_AdminDigest_Heading);
        if (!summary.limits.isEmpty()) {
            lines.add(System.Label.Core_AdminDigest_Limits);
            for (String limitLine : summary.limits) {
                lines.add('  ' + limitLine);
            }
        }
        if (summary.failedJobs > 0) {
            lines.add(
                String.format(
                    System.Label.Core_AdminDigest_FailedJobs,
                    new List<Object>{ String.valueOf(summary.failedJobs) }
                )
            );
            for (Import_Batch__c job : summary.failedJobList) {
                lines.add('  ' + job.Name + ', ' + job.Operation__c + ': ' + base + '/' + job.Id);
            }
            Integer unlisted = summary.failedJobs - summary.failedJobList.size();
            if (unlisted > 0) {
                lines.add(
                    String.format(
                        System.Label.Core_AdminDigest_MoreJobs,
                        new List<Object>{ String.valueOf(unlisted) }
                    )
                );
            }
        }
        if (summary.duplicatesWaiting > 0) {
            lines.add(
                String.format(
                    System.Label.Core_AdminDigest_Duplicates,
                    new List<Object>{
                        summary.duplicatesCapped
                            ? summary.duplicatesWaiting + '+'
                            : String.valueOf(summary.duplicatesWaiting)
                    }
                )
            );
        }
        lines.add('');
        return lines;
    }

    private static Integer failedJobCount(Datetime after, Datetime upTo) {
        String failed = ImportBatchService.STATUS_FAILED;
        return [
            SELECT COUNT()
            FROM Import_Batch__c
            WHERE Status__c = :failed AND LastModifiedDate > :after AND LastModifiedDate <= :upTo
            WITH USER_MODE
        ];
    }

    private static List<Import_Batch__c> failedJobs(Datetime after, Datetime upTo) {
        String failed = ImportBatchService.STATUS_FAILED;
        return [
            SELECT Id, Name, Operation__c
            FROM Import_Batch__c
            WHERE Status__c = :failed AND LastModifiedDate > :after AND LastModifiedDate <= :upTo
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT :JOBS_LISTED
        ];
    }
}
