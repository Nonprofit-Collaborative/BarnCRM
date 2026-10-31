/**
 * Org Optimizer's Setup Changes section (C-56, canonical model Section 29W, admin guide
 * setup-changes.md): the kept copy of the Setup Audit Trail, filtered and listed newest first,
 * and a button that copies new changes now.
 *
 * Every method requires Manage BarnCRM Settings (R-SU5). Kept rows are read in user mode, which
 * the BarnCRM Admin permission set allows; the copy itself is `SetupChangeCopyJob`'s. Nothing
 * here reads or changes Setup.
 */
public with sharing class SetupChangeController {
    private static final String PERMISSION = 'Manage_BarnCRM_Settings';

    /** Rows the table shows (R-SU6). */
    public static final Integer PAGE_ROWS = 200;
    /** Rows a CSV download holds at most (R-SU6). */
    public static final Integer EXPORT_ROWS = 5000;
    /** Kept rows one search looks at, newest first, before it stops (R-SU6). */
    @TestVisible
    private static Integer scanCap = 40000;
    /** Sections offered in the filter at most. */
    private static final Integer MAX_SECTIONS = 200;

    @TestVisible
    private static Boolean permissionOverride;

    /** What the section shows above the table. */
    public class Summary {
        @AuraEnabled
        public Integer keptCount = 0;
        @AuraEnabled
        public Datetime oldest;
        @AuraEnabled
        public Datetime newest;
        @AuraEnabled
        public Boolean scheduled = false;
        @AuraEnabled
        public Boolean running = false;
        @AuraEnabled
        public Integer retentionDays;
        @AuraEnabled
        public List<String> sections = new List<String>();
        @AuraEnabled
        public Integer pageRows = PAGE_ROWS;
        @AuraEnabled
        public Integer exportRows = EXPORT_ROWS;
    }

    /** One kept change, as the table and the CSV show it. */
    public class Change {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Datetime changedAt;
        @AuraEnabled
        public String changedBy;
        @AuraEnabled
        public String delegateUser;
        @AuraEnabled
        public String section;
        @AuraEnabled
        public String action;
        @AuraEnabled
        public String display;
    }

    /** One search's answer. */
    public class Result {
        @AuraEnabled
        public List<Change> rows = new List<Change>();
        /** True when more rows match than were returned. */
        @AuraEnabled
        public Boolean more = false;
        /** True when the search stopped at the scan cap, so later matches may be missing. */
        @AuraEnabled
        public Boolean scanStopped = false;
        @AuraEnabled
        public Integer scanCap = SetupChangeController.scanCap;
    }

    /** What `copyNow` did. */
    public class CopyResult {
        /** False when a copy was already waiting or running, so none was started. */
        @AuraEnabled
        public Boolean started = false;
        @AuraEnabled
        public Boolean scheduled = false;
    }

    @AuraEnabled
    public static Summary getSummary() {
        requirePermission();
        Summary summary = new Summary();
        summary.keptCount = [SELECT COUNT() FROM Setup_Change__c WITH USER_MODE];
        if (summary.keptCount > 0) {
            summary.oldest = [
                SELECT Changed_At__c
                FROM Setup_Change__c
                WITH USER_MODE
                ORDER BY Changed_At__c ASC NULLS LAST
                LIMIT 1
            ]
            .Changed_At__c;
            summary.newest = [
                SELECT Changed_At__c
                FROM Setup_Change__c
                WITH USER_MODE
                ORDER BY Changed_At__c DESC NULLS LAST
                LIMIT 1
            ]
            .Changed_At__c;
            for (AggregateResult row : [
                SELECT Section__c section, COUNT(Id) total
                FROM Setup_Change__c
                WHERE Section__c != NULL
                WITH USER_MODE
                GROUP BY Section__c
                ORDER BY Section__c
                LIMIT :MAX_SECTIONS
            ]) {
                summary.sections.add((String) row.get('section'));
            }
        }
        summary.scheduled = SetupChangeCopyJob.isScheduled();
        summary.running = SetupChangeCopyJob.isRunning();
        summary.retentionDays = SetupChangeCopyJob.retentionDays();
        return summary;
    }

    /**
     * Kept changes matching the filters, newest first (R-SU6). `fromDate` and `toDate` are
     * `YYYY-MM-DD` days in the person's time zone, both included, either may be blank; `section`
     * is an exact Section or blank; `search` is words that must each appear, ignoring capitals.
     * `maxRows` is held between 1 and the export cap.
     */
    @AuraEnabled
    public static Result getChanges(
        String fromDate,
        String toDate,
        String section,
        String search,
        Integer maxRows
    ) {
        requirePermission();
        Scan run = new Scan(
            maxRows == null ? PAGE_ROWS : Math.max(1, Math.min(maxRows, EXPORT_ROWS)),
            wordsOf(search)
        );
        // Blank dates read as no limit; the far ends keep one query shape for both cases.
        Datetime fromAt = startOfDay(fromDate, 0);
        fromAt = fromAt == null ? Datetime.newInstanceGmt(1900, 1, 1) : fromAt;
        Datetime toAt = startOfDay(toDate, 1);
        toAt = toAt == null ? Datetime.newInstanceGmt(4000, 1, 1) : toAt;
        Integer cap = scanCap;
        // SOQL for loops read 200 rows at a time, so a long scan never holds every row at once.
        if (String.isBlank(section)) {
            for (List<Setup_Change__c> chunk : [
                SELECT
                    Id,
                    Changed_At__c,
                    Changed_By__c,
                    Delegate_User__c,
                    Section__c,
                    Action__c,
                    Display__c
                FROM Setup_Change__c
                WHERE Changed_At__c >= :fromAt AND Changed_At__c < :toAt
                WITH USER_MODE
                ORDER BY Changed_At__c DESC, Id DESC
                LIMIT :cap
            ]) {
                if (run.take(chunk)) {
                    break;
                }
            }
        } else {
            for (List<Setup_Change__c> chunk : [
                SELECT
                    Id,
                    Changed_At__c,
                    Changed_By__c,
                    Delegate_User__c,
                    Section__c,
                    Action__c,
                    Display__c
                FROM Setup_Change__c
                WHERE Changed_At__c >= :fromAt AND Changed_At__c < :toAt AND Section__c = :section
                WITH USER_MODE
                ORDER BY Changed_At__c DESC, Id DESC
                LIMIT :cap
            ]) {
                if (run.take(chunk)) {
                    break;
                }
            }
        }
        run.result.scanStopped = !run.result.more && run.scanned >= cap;
        return run.result;
    }

    /** One search in progress: the rows found so far and how many were looked at. */
    private class Scan {
        Integer wanted;
        List<String> words;
        Integer scanned = 0;
        Result result = new Result();

        Scan(Integer wanted, List<String> words) {
            this.wanted = wanted;
            this.words = words;
        }

        /** Takes the matching rows of one chunk; true once one more match than wanted is seen. */
        Boolean take(List<Setup_Change__c> chunk) {
            for (Setup_Change__c row : chunk) {
                scanned++;
                if (!matches(row, words)) {
                    continue;
                }
                if (result.rows.size() == wanted) {
                    result.more = true;
                    return true;
                }
                result.rows.add(toChange(row));
            }
            return false;
        }
    }

    /**
     * Copies new changes now, as the running user, and schedules the nightly copy when it is not
     * scheduled (R-SU2). Starts nothing when a copy is already waiting or running.
     */
    @AuraEnabled
    public static CopyResult copyNow() {
        requirePermission();
        CopyResult result = new CopyResult();
        try {
            SetupChangeCopyJob.start();
            result.started = SetupChangeCopyJob.runNow();
            result.scheduled = SetupChangeCopyJob.isScheduled();
        } catch (Exception failed) {
            ErrorLogger.log(failed, 'SetupChangeController');
            throw UserErrors.message(failed.getMessage());
        }
        return result;
    }

    // -------------------------------------------------------------------------------------

    /** The start of the day given, plus the days given, in the person's time zone; null when blank. */
    private static Datetime startOfDay(String day, Integer plusDays) {
        if (String.isBlank(day)) {
            return null;
        }
        Date parsed;
        try {
            parsed = Date.valueOf(day.trim());
        } catch (Exception badDate) {
            throw UserErrors.message(
                String.format(Label.Core_SetupChanges_ErrorBadDate, new List<String>{ day })
            );
        }
        return Datetime.newInstance(parsed.addDays(plusDays), Time.newInstance(0, 0, 0, 0));
    }

    private static List<String> wordsOf(String search) {
        List<String> words = new List<String>();
        if (String.isBlank(search)) {
            return words;
        }
        for (String word : search.trim().toLowerCase().split('\\s+')) {
            if (String.isNotBlank(word)) {
                words.add(word);
            }
        }
        return words;
    }

    @TestVisible
    private static Boolean matches(Setup_Change__c row, List<String> words) {
        if (words.isEmpty()) {
            return true;
        }
        String text = '';
        for (
            String part : new List<String>{
                row.Display__c,
                row.Section__c,
                row.Action__c,
                row.Changed_By__c,
                row.Delegate_User__c
            }
        ) {
            text += part == null ? '\n' : part.toLowerCase() + '\n';
        }
        for (String word : words) {
            if (!text.contains(word)) {
                return false;
            }
        }
        return true;
    }

    private static Change toChange(Setup_Change__c row) {
        Change change = new Change();
        change.id = row.Id;
        change.changedAt = row.Changed_At__c;
        change.changedBy = row.Changed_By__c;
        change.delegateUser = row.Delegate_User__c;
        change.section = row.Section__c;
        change.action = row.Action__c;
        change.display = row.Display__c;
        return change;
    }

    private static void requirePermission() {
        Boolean allowed = permissionOverride != null
            ? permissionOverride
            : FeatureManagement.checkPermission(PERMISSION);
        if (!allowed) {
            throw UserErrors.message(Label.Core_OrgOptimizer_ErrorNoPermission);
        }
    }
}
