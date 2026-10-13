/**
 * Runs an import a chunk at a time in Batch Apex, with the chunk size the org set (R-IB2).
 *
 * The chunk is the unit of failure as well as the unit of work. Each chunk runs inside its
 * own try, so a chunk that hits a limit or an unexpected exception is recorded on its own
 * rows and in the run log, and the next chunk still runs. That is what R-IB5 asks for: a
 * partial failure leaves nothing half committed and unexplained, because every row says what
 * happened to it and the batch says how many did not make it.
 *
 * Stateful, because the run log and the fact that something failed have to survive from one
 * chunk to the next. The counts are not carried here: they are read back from the rows when
 * the run finishes, so a resumed or retried run still reports the truth.
 */
public with sharing class ImportProcessorBatch implements Database.Batchable<SObject>, Database.Stateful {
    /** How many lines of the run log are kept. A chunk failure is worth more than a note. */
    private static final Integer MAX_LOG_LINES = 200;

    private final Id batchId;
    private final Boolean dryRun;
    private Boolean failed = false;
    private List<String> log = new List<String>();
    private Set<String> notes = new Set<String>();
    private Integer chunksRun = 0;
    /** The gift amounts the entity processor read, added up over the chunks (R-IB10). */
    private Decimal fileAmount;
    /** The entity processor's own state, handed from chunk to chunk (R-IR6). */
    private String processorState;
    /** The settings the entity processor ran a dry run under, for the commit (R-IB11). */
    private String processorSettings;
    /** The pass this run is (R-IB13), stamped on a chunk's rows even when the chunk dies. */
    private Decimal pass;

    public ImportProcessorBatch(Id batchId, Boolean dryRun) {
        this.batchId = batchId;
        this.dryRun = dryRun == true;
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        Id owner = batchId;
        // System mode, stated because API 67.0 would otherwise read in user mode: the staged
        // rows are the package's own bookkeeping, written in system mode for the reason
        // ADR-0021 gives, and this read only feeds that processing. The records a row makes
        // are still written in user mode, and the class keeps the run's sharing.
        return Database.getQueryLocator(
            [
                SELECT
                    Id,
                    Import_Batch__c,
                    Row_Number__c,
                    Raw_Values_JSON__c,
                    Status__c,
                    Error_Message__c,
                    Household__c,
                    Contact_1__c,
                    Person_1_Account__c,
                    Contact_2__c,
                    Person_2_Account__c,
                    Organization__c,
                    Gift_Id__c,
                    Soft_Credit_Id__c
                FROM Import_Row__c
                WHERE Import_Batch__c = :owner
                WITH SYSTEM_MODE
                ORDER BY Row_Number__c ASC
            ]
        );
    }

    /** Makes a chunk die after its rows were processed, so a test can see the rollback. */
    @TestVisible
    private static Boolean failAfterProcessForTest = false;

    public void execute(Database.BatchableContext context, List<Import_Row__c> scope) {
        chunksRun++;
        // A chunk that dies part way must leave none of its writes behind (R-IB5): without the
        // rollback, the records it made before the failure would stay while its rows say
        // rejected, and a second load would make them again.
        Savepoint beforeChunk = Database.setSavepoint();
        try {
            Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
            // The template as the dry run started with it, not as edited since (R-IB1).
            Import_Template__c template = ImportBatchService.templateFor(batch);
            pass = batch == null ? null : batch.Pass_Number__c;
            if (batch == null || template == null) {
                throw new ImportException(Label.Core_Import_ErrorTemplateGone);
            }
            // The file's own values come before the template's defaults (R-IB14).
            ImportMapping mapping = ImportMapping.parse(
                    template.Column_Mapping_JSON__c,
                    template.Default_Values_JSON__c
                )
                .withFileValues(batch.File_Values_JSON__c);
            ImportEntityProcessors.carriedState = processorState;
            ImportRowProcessor.Outcome outcome = ImportRowProcessor.process(
                batch,
                template,
                mapping,
                scope,
                dryRun
            );
            if (failAfterProcessForTest) {
                throw new ImportException('Failed for the test.');
            }
            // Kept only from a chunk that finished: a chunk that died saved nothing.
            processorState = ImportEntityProcessors.carriedState;
            notes.addAll(outcome.notes);
            if (outcome.fileAmount != null) {
                fileAmount = (fileAmount == null ? 0 : fileAmount) + outcome.fileAmount;
            }
            if (String.isNotBlank(outcome.processorSettings)) {
                processorSettings = outcome.processorSettings;
            }
        } catch (Exception e) {
            // The chunk is lost, not the run. Every row in it is marked with the reason so
            // that nothing disappears without an explanation an administrator can read.
            failed = true;
            Database.rollback(beforeChunk);
            rejectChunk(scope, e.getMessage());
            addLog(
                String.format(
                    Label.Core_Import_LogChunkFailed,
                    new List<String>{ String.valueOf(chunksRun), e.getMessage() }
                )
            );
            ErrorLogger.log(e, 'ImportProcessorBatch.execute');
        }
    }

    public void finish(Database.BatchableContext context) {
        try {
            List<String> lines = new List<String>();
            lines.add(
                dryRun ? Label.Core_Import_LogDryRunHeader : Label.Core_Import_LogCommitHeader
            );
            lines.addAll(new List<String>(notes));
            lines.addAll(log);
            ImportBatchService.finish(
                batchId,
                dryRun,
                failed,
                lines,
                fileAmount,
                processorSettings
            );
        } catch (Exception e) {
            ErrorLogger.log(e, 'ImportProcessorBatch.finish');
        }
    }

    /**
     * Marks every row of a chunk that died as rejected, with the reason. In system mode for
     * the reason ADR-0021 gives: the staged rows are the package's own record of the run and
     * must be written even where the running user cannot edit them.
     */
    private void rejectChunk(List<Import_Row__c> scope, String reason) {
        List<Import_Row__c> rows = new List<Import_Row__c>();
        for (Import_Row__c row : scope) {
            Import_Row__c rejected = new Import_Row__c(Id = row.Id);
            ImportRowProcessor.startPass(rejected, pass);
            rejected.Status__c = ImportRowProcessor.STATUS_REJECTED;
            rejected.Error_Message__c = String.isBlank(reason)
                ? Label.Core_Import_ErrorSaveFailed
                : reason.abbreviate(4000);
            rows.add(rejected);
        }
        if (!rows.isEmpty()) {
            Database.update(rows, false, AccessLevel.SYSTEM_MODE);
        }
    }

    private void addLog(String line) {
        if (log.size() < MAX_LOG_LINES) {
            log.add(line);
        }
    }
}
