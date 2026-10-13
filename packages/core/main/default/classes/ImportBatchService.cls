/**
 * The life of one import: created from an uploaded file, staged a chunk at a time, dry run,
 * committed, and finished with counts an administrator can trust.
 *
 * The rules this class exists to keep are R-IB1 and R-IB5. A commit is refused until a dry
 * run of the same file and template has completed, and the counts it reports come from the
 * staged rows themselves, never from a total carried in memory, so what the results screen
 * says is what is actually on the rows.
 */
@NamespaceAccessible
public with sharing class ImportBatchService {
    @NamespaceAccessible
    public static final String STATUS_DRAFT = 'Draft';
    @NamespaceAccessible
    public static final String STATUS_PARSING = 'Parsing';
    @NamespaceAccessible
    public static final String STATUS_DRY_RUN = 'Dry run';
    @NamespaceAccessible
    public static final String STATUS_DRY_RUN_COMPLETE = 'Dry run complete';
    @NamespaceAccessible
    public static final String STATUS_COMMITTING = 'Committing';
    @NamespaceAccessible
    public static final String STATUS_COMPLETE = 'Complete';
    @NamespaceAccessible
    public static final String STATUS_FAILED = 'Failed';
    @NamespaceAccessible
    public static final String STATUS_UNDOING = 'Undoing';
    @NamespaceAccessible
    public static final String STATUS_UNDONE = 'Undone';
    @NamespaceAccessible
    public static final String STATUS_UNDO_FAILED = 'Undo failed';

    /** The chunk size used when the setting is missing or nonsensical. */
    @NamespaceAccessible
    public static final Integer DEFAULT_CHUNK_SIZE = 200;

    /** The narrowest and widest chunk the platform is asked for. */
    private static final Integer MIN_CHUNK_SIZE = 1;
    private static final Integer MAX_CHUNK_SIZE = 2000;

    /** The length of Raw Values JSON, the longest row a file may have. */
    @TestVisible
    private static final Integer MAX_ROW_LENGTH = 32768;

    /** How long after a commit a batch may still be undone, when the org has not said (R-IB7). */
    @NamespaceAccessible
    public static final Integer UNDO_WINDOW_DAYS = 30;

    /** The longest undo window an org may set, so a mistyped number cannot stand. */
    private static final Integer MAX_UNDO_WINDOW_DAYS = 365;

    /**
     * Creates the batch record for one upload. The file has already been stored as a
     * Salesforce File by the component, and its identifier is kept so the original can be
     * downloaded again. The control totals (R-IB10) are how many rows the file should hold and
     * what its gift amounts should add up to; either may be null, meaning it is not checked.
     * The file values are what every row takes where it has none of its own (R-IB14); a value
     * that would make every row one person is refused, saying which. Match only marks a file
     * that updates records the org already has and creates none (R-IB15).
     */
    @NamespaceAccessible
    public static Import_Batch__c create(
        Id templateId,
        String fileId,
        String fileName,
        Integer expectedCount,
        Decimal expectedAmount,
        List<ImportMapping.Assignment> fileValues,
        Boolean matchOnly
    ) {
        if (expectedCount != null && expectedCount < 0) {
            throw new ImportException(Label.Core_Import_ErrorControlCountNegative);
        }
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        String fileValuesDocument = fileValuesDocument(template, fileValues);
        Import_Batch__c batch = new Import_Batch__c(
            Import_Template__c = template.Id,
            File_Id__c = String.isBlank(fileId) ? null : fileId.left(18),
            File_Name__c = String.isBlank(fileName) ? null : fileName.abbreviate(255),
            Status__c = STATUS_DRAFT,
            Is_Dry_Run__c = true,
            Row_Count__c = 0,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0,
            Chunk_Size__c = chunkSize(),
            Expected_Count__c = expectedCount,
            Expected_Amount__c = expectedAmount == null ? null : expectedAmount.setScale(2),
            File_Values_JSON__c = fileValuesDocument,
            Match_Only__c = matchOnly == true
        );
        Database.insert(batch, AccessLevel.USER_MODE);
        return batch;
    }

    /**
     * The file's values as the defaults half of a mapping document, or null when there are
     * none (R-IB14). Blank targets and values are dropped. A value for a person's name parts,
     * full name or email, or for the field people are matched on, is refused: every row would
     * then be one person.
     */
    private static String fileValuesDocument(
        Import_Template__c template,
        List<ImportMapping.Assignment> fileValues
    ) {
        if (fileValues == null || fileValues.isEmpty()) {
            return null;
        }
        String personField = ImportTemplateService.RULE_EXTERNAL_ID.equals(
                ImportTemplateService.normalizedRule(template.Matching_Rule__c)
            )
            ? ImportMatcher.matchField(
                  ImportTemplateService.personType(template),
                  template.Person_Match_Field__c
              )
            : null;
        ImportMapping document = new ImportMapping();
        for (ImportMapping.Assignment given : fileValues) {
            if (
                given == null ||
                ImportMapping.isIgnored(given.target) ||
                String.isBlank(given.value)
            ) {
                continue;
            }
            String target = given.target.trim();
            if (ImportMapping.namesAPerson(target, personField)) {
                throw new ImportException(
                    String.format(
                        Label.Core_Import_ErrorFileValueNotAllowed,
                        new List<String>{ target.left(80) }
                    )
                );
            }
            document.defaults.add(new ImportMapping.Assignment(target, given.value.trim()));
        }
        return document.defaults.isEmpty() ? null : document.serialize();
    }

    /**
     * Stages one page of the file's rows. The component parses the file in the browser and
     * sends the rows in pages, so a large file never arrives as one request and the staging
     * itself is bulk.
     *
     * @param rows each row's values keyed by the file's column names, in file order
     * @param firstRowNumber the file row number of the first row in this page, counting the
     *        header row as row 1
     * @return how many rows the batch now has
     */
    @NamespaceAccessible
    public static Integer stageRows(
        Id batchId,
        List<Map<String, Object>> rows,
        Integer firstRowNumber
    ) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        // Rows join a file only while it is being read in: staging into a batch that has run
        // would flip it back to Parsing, hiding a running job and an undoable commit.
        if (batch.Status__c != STATUS_DRAFT && batch.Status__c != STATUS_PARSING) {
            throw new ImportException(Label.Core_Import_ErrorStagingClosed);
        }
        if (rows == null || rows.isEmpty()) {
            return batch.Row_Count__c == null ? 0 : batch.Row_Count__c.intValue();
        }
        Integer start = firstRowNumber == null || firstRowNumber < 1 ? 1 : firstRowNumber;
        List<Import_Row__c> staged = new List<Import_Row__c>();
        for (Integer i = 0; i < rows.size(); i++) {
            String raw = JSON.serialize(rows[i]);
            // Cut short, the row would no longer be readable and would be rejected for the
            // wrong reason, so the page is refused with the row's number instead.
            if (raw.length() > MAX_ROW_LENGTH) {
                throw new ImportException(
                    String.format(
                        Label.Core_Import_ErrorRowTooLong,
                        new List<String>{ String.valueOf(start + i) }
                    )
                );
            }
            staged.add(
                new Import_Row__c(
                    Import_Batch__c = batch.Id,
                    Row_Number__c = start + i,
                    Raw_Values_JSON__c = raw,
                    Status__c = ImportRowProcessor.STATUS_PENDING
                )
            );
        }
        Database.insert(staged, AccessLevel.USER_MODE);
        Integer total =
            (batch.Row_Count__c == null ? 0 : batch.Row_Count__c.intValue()) + staged.size();
        batch.Row_Count__c = total;
        batch.Status__c = STATUS_PARSING;
        Database.update(batch, AccessLevel.USER_MODE);
        return total;
    }

    /**
     * Starts a dry run: every row is reset to pending, nothing is written, and the counts
     * that come back are what a commit would do.
     */
    @NamespaceAccessible
    public static Id startDryRun(Id batchId) {
        return start(batchId, true);
    }

    /**
     * Starts a commit. Refused unless a dry run of this batch has completed (R-IB1), because
     * the preview is the only thing that makes a commit safe to press.
     */
    @NamespaceAccessible
    public static Id startCommit(Id batchId) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        if (!STATUS_DRY_RUN_COMPLETE.equals(batch.Status__c)) {
            throw new ImportException(Label.Core_Import_ErrorDryRunFirst);
        }
        if (!controlTotalsAgree(batch)) {
            throw new ImportException(Label.Core_Import_ErrorControlTotalsDiffer);
        }
        return start(batchId, false);
    }

    /**
     * Whether the file agrees with the control totals it was given (R-IB10). A total that was
     * not given agrees. An expected amount that nothing read, because no module that loads
     * gifts is installed, cannot be checked and does not agree.
     */
    @NamespaceAccessible
    public static Boolean controlTotalsAgree(Import_Batch__c batch) {
        return countAgrees(batch) && amountAgrees(batch);
    }

    private static Boolean countAgrees(Import_Batch__c batch) {
        return batch.Expected_Count__c == null ||
            (batch.Row_Count__c != null &&
            batch.Expected_Count__c.intValue() == batch.Row_Count__c.intValue());
    }

    private static Boolean amountAgrees(Import_Batch__c batch) {
        return batch.Expected_Amount__c == null ||
            (batch.File_Amount__c != null &&
            batch.Expected_Amount__c.setScale(2) == batch.File_Amount__c.setScale(2));
    }

    /** The run log lines saying how the file compared with its control totals (R-IB10). */
    private static List<String> controlTotalLines(Import_Batch__c batch) {
        List<String> lines = new List<String>();
        if (batch.Expected_Count__c != null) {
            String found = String.valueOf(
                batch.Row_Count__c == null ? 0 : batch.Row_Count__c.intValue()
            );
            lines.add(
                countAgrees(batch)
                    ? String.format(
                          Label.Core_Import_LogControlCountAgrees,
                          new List<String>{ found }
                      )
                    : String.format(
                          Label.Core_Import_LogControlCountDiffers,
                          new List<String>{
                              found,
                              String.valueOf(batch.Expected_Count__c.intValue())
                          }
                      )
            );
        }
        if (batch.Expected_Amount__c != null) {
            if (batch.File_Amount__c == null) {
                lines.add(Label.Core_Import_LogControlAmountUnread);
            } else {
                String found = batch.File_Amount__c.setScale(2).format();
                lines.add(
                    amountAgrees(batch)
                        ? String.format(
                              Label.Core_Import_LogControlAmountAgrees,
                              new List<String>{ found }
                          )
                        : String.format(
                              Label.Core_Import_LogControlAmountDiffers,
                              new List<String>{
                                  found,
                                  batch.Expected_Amount__c.setScale(2).format()
                              }
                          )
                );
            }
        }
        return lines;
    }

    private static Id start(Id batchId, Boolean dryRun) {
        // Locked, so two starts at once cannot both find no job running (R-IB13).
        List<Import_Batch__c> locked = [
            SELECT Id
            FROM Import_Batch__c
            WHERE Id = :batchId
            WITH USER_MODE
            FOR UPDATE
        ];
        Import_Batch__c batch = locked.isEmpty() ? null : ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        if (isRunning(batch)) {
            // Two passes of one batch at once would each overwrite the other's rows (R-IB13).
            throw new ImportException(Label.Core_Import_ErrorRunInProgress);
        }
        if (dryRun && hasCommitted(batch)) {
            throw new ImportException(Label.Core_Import_ErrorDryRunAfterCommit);
        }
        // A dry run reads the template as it stands and records it; the commit runs under what
        // its dry run recorded, whatever has been edited since (R-IB1).
        Import_Template__c template = dryRun
            ? ImportTemplateSelector.selectById(batch.Import_Template__c)
            : templateFor(batch);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        ImportMapping mapping = ImportMapping.parse(
                template.Column_Mapping_JSON__c,
                template.Default_Values_JSON__c
            )
            .withFileValues(batch.File_Values_JSON__c);
        Boolean oneObject = ImportObjectSchema.loadsOneObject(template);
        // A one-object template is refused for its own reasons, before any row is read (R-IT12).
        String refused = oneObject ? ImportObjectSchema.refusal(template, mapping) : null;
        if (refused != null) {
            throw new ImportException(refused);
        }
        if (!oneObject && !mapping.identifiesSomebody()) {
            throw new ImportException(Label.Core_Import_ErrorMappingIdentifiesNobody);
        }
        if (batch.Row_Count__c == null || batch.Row_Count__c <= 0) {
            throw new ImportException(Label.Core_Import_ErrorNoRows);
        }
        if (
            !oneObject &&
            ImportTemplateService.isPersonAccountMode(template) &&
            OrgShapeDetector.detect().personAccountRecordTypeIds.isEmpty()
        ) {
            throw new ImportException(Label.Core_Import_ErrorPersonModeUnavailable);
        }
        // No reset of the staged rows: each chunk clears and stamps its own, so a pass costs the
        // same two writes here however long the file (R-IB13).
        batch.Pass_Number__c = nextPass(batch);
        batch.Status__c = dryRun ? STATUS_DRY_RUN : STATUS_COMMITTING;
        batch.Is_Dry_Run__c = dryRun;
        batch.Started_At__c = Datetime.now();
        batch.Completed_At__c = null;
        batch.Run_Log__c = null;
        batch.Rows_Created__c = 0;
        batch.Rows_Updated__c = 0;
        batch.Rows_Matched__c = 0;
        batch.Rows_Rejected__c = 0;
        if (!dryRun) {
            // Stamped now as well as at the finish, so a commit the platform aborts part way
            // can still be undone (R-IB7, R-IB13).
            batch.Committed_By__c = UserInfo.getUserId();
            batch.Undo_Deadline__c = Datetime.now().addDays(undoWindowDays());
        }
        // Enqueued before the write, so the job is recorded with the pass; both roll back
        // together if the write fails.
        batch.Job_Id__c = Database.executeBatch(
            new ImportProcessorBatch(batch.Id, dryRun),
            scopeSize(batch.Chunk_Size__c)
        );
        Database.update(passStamp(batch), AccessLevel.USER_MODE);
        // The pass number, job and template snapshot are the package's bookkeeping, read only
        // in every permission set, so they are written in system mode (ADR-0021).
        Import_Batch__c bookkeeping = new Import_Batch__c(
            Id = batch.Id,
            Pass_Number__c = batch.Pass_Number__c,
            Job_Id__c = batch.Job_Id__c
        );
        if (dryRun) {
            bookkeeping.Template_Snapshot_JSON__c = JSON.serialize(template);
        }
        Database.update(bookkeeping, AccessLevel.SYSTEM_MODE);
        return batch.Job_Id__c;
    }

    /**
     * The template a batch runs under (R-IB1): the copy its last dry run recorded when it has
     * one, otherwise the template as it stands (a batch previewed before the copy was kept).
     * Null when the template itself is gone, so a deleted template still stops the run.
     */
    @NamespaceAccessible
    public static Import_Template__c templateFor(Import_Batch__c batch) {
        Import_Template__c current = batch == null
            ? null
            : ImportTemplateSelector.selectById(batch.Import_Template__c);
        if (current == null) {
            return null;
        }
        String snapshot = ImportBatchSelector.selectTemplateSnapshot(batch.Id);
        return String.isBlank(snapshot)
            ? current
            : (Import_Template__c) JSON.deserialize(snapshot, Import_Template__c.class);
    }

    /** Only what starting a pass changes and the person starting it may edit, saved as them. */
    private static Import_Batch__c passStamp(Import_Batch__c batch) {
        Import_Batch__c stamp = new Import_Batch__c(
            Id = batch.Id,
            Status__c = batch.Status__c,
            Is_Dry_Run__c = batch.Is_Dry_Run__c,
            Started_At__c = batch.Started_At__c,
            Completed_At__c = null,
            Run_Log__c = null,
            Rows_Created__c = 0,
            Rows_Updated__c = 0,
            Rows_Matched__c = 0,
            Rows_Rejected__c = 0
        );
        if (batch.Is_Dry_Run__c != true) {
            stamp.Committed_By__c = batch.Committed_By__c;
            stamp.Undo_Deadline__c = batch.Undo_Deadline__c;
        }
        return stamp;
    }

    /** Set by a test to stand for the platform's answer about a batch's job. */
    @TestVisible
    private static Boolean jobRunningForTest;

    /**
     * Whether the batch's dry run or commit is really running: its status says so and its job
     * is queued or processing. A pass the platform aborted, or whose finish failed, keeps its
     * status with no job behind it, and is not running (R-IB13). Read in system mode: the job
     * may be another user's.
     */
    @NamespaceAccessible
    public static Boolean isRunning(Import_Batch__c batch) {
        if (
            batch == null ||
            !(STATUS_DRY_RUN.equals(batch.Status__c) || STATUS_COMMITTING.equals(batch.Status__c))
        ) {
            return false;
        }
        if (jobRunningForTest != null) {
            return jobRunningForTest;
        }
        if (String.isBlank(batch.Job_Id__c)) {
            return false;
        }
        Id jobId = batch.Job_Id__c;
        Set<String> running = RUNNING_JOB_STATUSES;
        return ![
                SELECT Id
                FROM AsyncApexJob
                WHERE Id = :jobId AND Status IN :running
                WITH SYSTEM_MODE
                LIMIT 1
            ]
            .isEmpty();
    }

    /** When the batch's job ended, or null when it has not or is no longer on record. */
    @TestVisible
    private static Datetime jobEndedForTest;

    @NamespaceAccessible
    public static Datetime jobEndedAt(Import_Batch__c batch) {
        if (jobEndedForTest != null) {
            return jobEndedForTest;
        }
        if (batch == null || String.isBlank(batch.Job_Id__c)) {
            return null;
        }
        Id jobId = batch.Job_Id__c;
        List<AsyncApexJob> jobs = [
            SELECT CompletedDate
            FROM AsyncApexJob
            WHERE Id = :jobId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return jobs.isEmpty() ? null : jobs[0].CompletedDate;
    }

    /** AsyncApexJob statuses that mean a job has not finished yet. */
    @NamespaceAccessible
    public static final Set<String> RUNNING_JOB_STATUSES = new Set<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /**
     * Whether a commit of this batch has started, whatever became of it since: committing,
     * committed, failed part way, or in any undo status. A dry run over such a batch would
     * mark it a dry run, so it could never be undone, clear its completion time, and a second
     * commit would move its undo window (R-IB1).
     */
    private static Boolean hasCommitted(Import_Batch__c batch) {
        return batch.Is_Dry_Run__c == false ||
            batch.Committed_By__c != null ||
            STATUS_COMMITTING.equals(batch.Status__c) ||
            STATUS_COMPLETE.equals(batch.Status__c) ||
            STATUS_UNDOING.equals(batch.Status__c) ||
            STATUS_UNDONE.equals(batch.Status__c) ||
            STATUS_UNDO_FAILED.equals(batch.Status__c);
    }

    /**
     * Starts a new pass of a batch without running it: the next Pass Number, one write however
     * many rows the batch has (R-IB13). A test that drives the processor itself calls this
     * where the platform would have called start.
     */
    @NamespaceAccessible
    public static void beginPass(Id batchId) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            throw new ImportException(Label.Core_Import_ErrorBatchGone);
        }
        Database.update(
            new Import_Batch__c(Id = batch.Id, Pass_Number__c = nextPass(batch)),
            AccessLevel.SYSTEM_MODE
        );
    }

    private static Decimal nextPass(Import_Batch__c batch) {
        return batch.Pass_Number__c == null ? 1 : batch.Pass_Number__c + 1;
    }

    /**
     * Closes a run: counts read back from the rows, the status the run ended in, and the run
     * log. Called from the batch's finish, where the running user may be anyone, so the write
     * is in system mode (ADR-0021) over fields the package owns. Records the total of the gift
     * amounts the entity processor read and checks the control totals against it (R-IB10). A
     * dry run also records the settings the entity processor ran under, replacing the last dry
     * run's, and the commit is held to them (R-IB11); a commit leaves them as its dry run
     * recorded them.
     */
    @NamespaceAccessible
    public static Import_Batch__c finish(
        Id batchId,
        Boolean dryRun,
        Boolean failed,
        List<String> logLines,
        Decimal fileAmount,
        String processorSettings
    ) {
        Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
        if (batch == null) {
            return null;
        }
        Map<String, Integer> counts = ImportBatchSelector.countRowsByStatus(batchId);
        batch.Rows_Created__c = count(counts, ImportRowProcessor.STATUS_CREATED);
        batch.Rows_Updated__c = count(counts, ImportRowProcessor.STATUS_UPDATED);
        batch.Rows_Matched__c = count(counts, ImportRowProcessor.STATUS_MATCHED);
        batch.Rows_Rejected__c = count(counts, ImportRowProcessor.STATUS_REJECTED);
        batch.Completed_At__c = Datetime.now();
        batch.File_Amount__c = fileAmount == null ? null : fileAmount.setScale(2);
        if (dryRun == true) {
            batch.Processor_Settings_JSON__c = processorSettings;
        }
        List<String> lines = logLines == null ? new List<String>() : new List<String>(logLines);
        lines.addAll(controlTotalLines(batch));
        batch.Run_Log__c = String.join(lines, '\n').abbreviate(32768);
        if (failed == true) {
            batch.Status__c = STATUS_FAILED;
        } else if (dryRun == true) {
            batch.Status__c = STATUS_DRY_RUN_COMPLETE;
        } else {
            batch.Status__c = STATUS_COMPLETE;
        }
        if (dryRun != true) {
            // A commit that failed part way still wrote the chunks that ran, so it is as
            // undoable as one that finished. The deadline is stamped here rather than
            // computed at undo, so changing the setting never moves it (R-IB7).
            batch.Committed_By__c = UserInfo.getUserId();
            batch.Undo_Deadline__c = Datetime.now().addDays(undoWindowDays());
        }
        Database.update(batch, AccessLevel.SYSTEM_MODE);
        if (failed != true && dryRun != true) {
            ImportTemplateService.recordImport(batch.Import_Template__c, Date.today());
        }
        JobNotifier.aboutRecord(
            UserInfo.getUserId(),
            dryRun == true ? Label.Core_JobNotice_ImportPreview : Label.Core_JobNotice_Import,
            failed == true,
            String.format(
                Label.Core_JobNotice_ImportBody,
                new List<Object>{
                    batch.Rows_Created__c.format(),
                    batch.Rows_Updated__c.format(),
                    batch.Rows_Matched__c.format(),
                    batch.Rows_Rejected__c.format()
                }
            ),
            batch.Id
        );
        return batch;
    }

    /**
     * The org's undo window in days. Nothing, zero or a negative number falls back to the
     * shipped thirty days, because an import that can never be undone is not a setting anybody
     * means to choose; anything over a year is held at a year.
     */
    @NamespaceAccessible
    public static Integer undoWindowDays() {
        Object configured = SettingsService.hasKey('Import_Undo_Retention_Days__c')
            ? SettingsService.getValue('Import_Undo_Retention_Days__c')
            : null;
        if (configured == null) {
            return UNDO_WINDOW_DAYS;
        }
        try {
            Integer days = Decimal.valueOf(String.valueOf(configured)).intValue();
            return days < 1 ? UNDO_WINDOW_DAYS : Math.min(days, MAX_UNDO_WINDOW_DAYS);
        } catch (Exception ignored) {
            return UNDO_WINDOW_DAYS;
        }
    }

    /** The org's chunk size, clamped to something the platform will accept. */
    @NamespaceAccessible
    public static Integer chunkSize() {
        Object configured = SettingsService.hasKey('Import_Chunk_Size__c')
            ? SettingsService.getValue('Import_Chunk_Size__c')
            : null;
        if (configured == null) {
            return DEFAULT_CHUNK_SIZE;
        }
        try {
            return scopeSize(Decimal.valueOf(String.valueOf(configured)));
        } catch (Exception ignored) {
            return DEFAULT_CHUNK_SIZE;
        }
    }

    private static Integer scopeSize(Decimal configured) {
        if (configured == null || configured < MIN_CHUNK_SIZE) {
            return DEFAULT_CHUNK_SIZE;
        }
        return (Integer) Math.min(configured.intValue(), MAX_CHUNK_SIZE);
    }

    private static Integer count(Map<String, Integer> counts, String status) {
        Integer found = counts.get(status);
        return found == null ? 0 : found;
    }
}
