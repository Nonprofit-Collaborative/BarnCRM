/**
 * The entry points the import wizard and the results screen call (C-14).
 *
 * Everything that changes anything checks the Manage BarnCRM Settings custom permission
 * first. The read that only shows a batch's progress does not, so a colleague watching a long
 * import does not need the administrator's permission to see how it is going.
 *
 * Every failure is logged once here and re-raised with its own message intact, so the screen
 * can say what went wrong instead of "an internal server error occurred".
 */
public with sharing class ImportController {
    /**
     * Injected by the tests so the permitted path can be asserted in an org where the
     * Manage_Nonprofit_Settings custom permission is not assigned to the running user. Null
     * in production, where the real check runs.
     */
    @TestVisible
    private static Boolean permissionOverride;

    /** One template as the wizard shows it. */
    public class TemplateView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public String matchingRule;
        @AuraEnabled
        public String personMode;
        @AuraEnabled
        public String mapping;
        @AuraEnabled
        public Boolean isPackageDefault;
        @AuraEnabled
        public String lastImportDate;
        @AuraEnabled
        public Boolean isRecurring;
        @AuraEnabled
        public String sourceName;
        /** How this template's gifts are matched to scheduled payments (R-IT7). */
        @AuraEnabled
        public String donationMatching;
        @AuraEnabled
        public Integer matchDateWindowDays;
        @AuraEnabled
        public Decimal matchAmountTolerance;
    }

    /** One import as the wizard and the results screen show it. */
    public class BatchView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String fileName;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean isDryRun;
        @AuraEnabled
        public Boolean isFinished;
        @AuraEnabled
        public Integer rowCount;
        @AuraEnabled
        public Integer created;
        @AuraEnabled
        public Integer updated;
        @AuraEnabled
        public Integer matched;
        @AuraEnabled
        public Integer rejected;
        @AuraEnabled
        public String runLog;
        /** The end of the window in which this import can be undone (R-IB7). */
        @AuraEnabled
        public Datetime undoDeadline;
        /** True when nothing about the batch itself stands in the way of an undo. */
        @AuraEnabled
        public Boolean canUndo;
        /** False when the file does not match the control totals it was given (R-IB10). */
        @AuraEnabled
        public Boolean controlTotalsAgree;
    }

    /**
     * What the wizard sends with a new batch besides its mapping: the control totals
     * (R-IB10). Held as one document so a later option does not change the method.
     */
    public class BatchOptions {
        public Integer expectedCount;
        public Decimal expectedAmount;
        /** True when the wizard showed the donation matching choices, which are then saved. */
        public Boolean saveDonationMatching;
        public String donationMatching;
        public Integer matchDateWindowDays;
        public Decimal matchAmountTolerance;
    }

    /** One staged row as the exceptions table shows it. */
    public class RowView {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public String errorMessage;
        @AuraEnabled
        public String values;
    }

    /** True when the running user may upload and commit an import. */
    @AuraEnabled(cacheable=true)
    public static Boolean canImport() {
        return hasManagePermission();
    }

    /**
     * The columns an installed entity processor loads (R-IR6), for the column picker. Empty
     * where none is installed, and the wizard then offers the gift columns as kept with the
     * row and not loaded.
     */
    @AuraEnabled
    public static List<ImportMapping.Target> getEntityTargets() {
        try {
            enforcePermission();
            ImportEntityProcessor processor = ImportEntityProcessors.find();
            List<ImportMapping.Target> targets = processor == null ? null : processor.targets();
            return targets == null ? new List<ImportMapping.Target>() : targets;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getEntityTargets');
        }
    }

    /** The templates the wizard offers, materializing the shipped ones on first use. */
    @AuraEnabled
    public static List<TemplateView> getTemplates() {
        try {
            enforcePermission();
            List<TemplateView> result = new List<TemplateView>();
            for (Import_Template__c template : ImportTemplateService.listActive()) {
                TemplateView view = new TemplateView();
                view.id = template.Id;
                view.name = template.Name;
                view.description = template.Description__c;
                view.matchingRule = template.Matching_Rule__c;
                view.personMode = template.Person_Mode__c;
                view.mapping = template.Column_Mapping_JSON__c;
                view.isPackageDefault = template.Is_Package_Default__c;
                view.lastImportDate = template.Last_Import_Date__c == null
                    ? null
                    : String.valueOf(template.Last_Import_Date__c);
                view.isRecurring = template.Is_Recurring__c;
                view.sourceName = template.Source_Name__c;
                view.donationMatching = template.Donation_Matching__c;
                view.matchDateWindowDays = template.Match_Date_Window_Days__c == null
                    ? null
                    : template.Match_Date_Window_Days__c.intValue();
                view.matchAmountTolerance = template.Match_Amount_Tolerance__c;
                result.add(view);
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getTemplates');
        }
    }

    /** Marks a template as the mapping for a file that arrives regularly, or not (R-IT6). */
    @AuraEnabled
    public static void saveRecurring(String templateId, Boolean isRecurring, String sourceName) {
        try {
            enforcePermission();
            ImportTemplateService.saveRecurring(templateId, isRecurring, sourceName);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.saveRecurring');
        }
    }

    /**
     * The mapping BarnCRM suggests for a file's header row, as a mapping document. The
     * template's own mapping wins for any column it already names, Do not load included, so a
     * template used every month keeps the corrections its administrator made to it.
     */
    @AuraEnabled
    public static String suggestMapping(String templateId, List<String> headers) {
        try {
            enforcePermission();
            ImportMapping suggested = ImportColumnLibrary.suggestMapping(headers);
            Import_Template__c template = ImportTemplateSelector.selectById(templateId);
            if (template != null) {
                ImportMapping saved = ImportMapping.parse(template.Column_Mapping_JSON__c);
                Map<String, String> known = saved.targetsBySourceKey();
                Set<String> ignored = saved.ignoredSourceKeys();
                for (ImportMapping.Column column : suggested.columns) {
                    String source = ImportMapping.key(column.source);
                    String fromTemplate = known.get(source);
                    if (String.isNotBlank(fromTemplate)) {
                        column.target = fromTemplate;
                    } else if (ignored.contains(source)) {
                        column.target = ImportMapping.TARGET_IGNORE;
                    }
                }
            }
            return suggested.serialize();
        } catch (Exception e) {
            throw auraError(e, 'ImportController.suggestMapping');
        }
    }

    /**
     * Saves the mapping the administrator settled on back to the template, then creates the
     * batch for this upload. One call, because the two always happen together and a batch
     * created against a mapping that failed to save would import the wrong thing.
     */
    @AuraEnabled
    public static BatchView createBatch(
        String templateId,
        String fileId,
        String fileName,
        String mappingDocument,
        String matchingRule,
        String optionsJson
    ) {
        try {
            enforcePermission();
            BatchOptions options = parseOptions(optionsJson);
            ImportTemplateService.saveMapping(templateId, mappingDocument, matchingRule);
            if (options.saveDonationMatching == true) {
                ImportTemplateService.saveDonationMatching(
                    templateId,
                    options.donationMatching,
                    options.matchDateWindowDays,
                    options.matchAmountTolerance
                );
            }
            return toView(
                ImportBatchService.create(
                    templateId,
                    fileId,
                    fileName,
                    options.expectedCount,
                    options.expectedAmount
                )
            );
        } catch (Exception e) {
            throw auraError(e, 'ImportController.createBatch');
        }
    }

    /**
     * Keeps the uploaded file as a Salesforce File so the original can be downloaded again
     * (canonical model Section 16, File Reference), and returns its document identifier.
     *
     * The component sends the file only when it is small enough to pass through a request
     * without risking the heap. A larger file still imports: the batch keeps its name and the
     * run log says the original was not kept, which is the honest answer rather than a
     * failure the administrator cannot act on.
     */
    @AuraEnabled
    public static String saveFile(String fileName, String base64Content) {
        try {
            enforcePermission();
            if (String.isBlank(base64Content)) {
                return null;
            }
            ContentVersion version = new ContentVersion(
                Title = String.isBlank(fileName) ? 'import' : fileName.abbreviate(255),
                PathOnClient = String.isBlank(fileName) ? 'import.csv' : fileName.abbreviate(255),
                VersionData = EncodingUtil.base64Decode(base64Content)
            );
            Database.insert(version, AccessLevel.USER_MODE);
            List<ContentVersion> saved = [
                SELECT ContentDocumentId
                FROM ContentVersion
                WHERE Id = :version.Id
                WITH USER_MODE
                LIMIT 1
            ];
            return saved.isEmpty() ? null : String.valueOf(saved[0].ContentDocumentId);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.saveFile');
        }
    }

    /** Stages one page of the file's rows. Returns how many rows the batch now has. */
    @AuraEnabled
    public static Integer stageRows(String batchId, String rowsJson, Integer firstRowNumber) {
        try {
            enforcePermission();
            List<Object> parsed = (List<Object>) JSON.deserializeUntyped(rowsJson);
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Object row : parsed) {
                rows.add((Map<String, Object>) row);
            }
            return ImportBatchService.stageRows(batchId, rows, firstRowNumber);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.stageRows');
        }
    }

    /** Starts the dry run. Nothing is written by it. */
    @AuraEnabled
    public static BatchView startDryRun(String batchId) {
        try {
            enforcePermission();
            ImportBatchService.startDryRun(batchId);
            return getBatch(batchId);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.startDryRun');
        }
    }

    /** Commits the import. Refused unless the dry run of this batch has completed. */
    @AuraEnabled
    public static BatchView startCommit(String batchId) {
        try {
            enforcePermission();
            ImportBatchService.startCommit(batchId);
            return getBatch(batchId);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.startCommit');
        }
    }

    /**
     * What undoing an import would remove and put back, and why it cannot be undone when it
     * cannot. Nothing is deleted by it (R-IB8).
     */
    @AuraEnabled
    public static ImportUndoService.Preview previewUndo(String batchId) {
        try {
            enforcePermission();
            return ImportUndoService.preview(batchId);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.previewUndo');
        }
    }

    /**
     * Starts the undo. Refused unless the total the person confirmed is still the total a
     * fresh count gives, so an undo only deletes a set somebody has seen the size of.
     */
    @AuraEnabled
    public static BatchView startUndo(String batchId, Integer confirmedTotal) {
        try {
            enforcePermission();
            ImportUndoService.start(batchId, confirmedTotal);
            return getBatch(batchId);
        } catch (Exception e) {
            throw auraError(e, 'ImportController.startUndo');
        }
    }

    /** Where a batch has got to. Polled by the screen while a run is going. */
    @AuraEnabled
    public static BatchView getBatch(String batchId) {
        try {
            return toView(ImportBatchSelector.selectById(batchId));
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getBatch');
        }
    }

    /** The most recent imports, for the history list on the results screen. */
    @AuraEnabled
    public static List<BatchView> getRecentBatches(Integer howMany) {
        try {
            List<BatchView> result = new List<BatchView>();
            for (Import_Batch__c batch : ImportBatchSelector.selectRecent(howMany)) {
                result.add(toView(batch));
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getRecentBatches');
        }
    }

    /**
     * One page of a batch's rows, optionally only those in one status. The exceptions file is
     * built from this with status Rejected.
     */
    @AuraEnabled
    public static List<RowView> getRows(String batchId, String status, Integer offsetRows) {
        try {
            List<Import_Row__c> rows = String.isBlank(status)
                ? ImportRowSelector.selectByBatch(batchId, offsetRows)
                : ImportRowSelector.selectByBatchAndStatus(batchId, status, offsetRows);
            List<RowView> result = new List<RowView>();
            for (Import_Row__c row : rows) {
                RowView view = new RowView();
                view.id = row.Id;
                view.rowNumber = row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
                view.status = row.Status__c;
                view.errorMessage = row.Error_Message__c;
                view.values = row.Raw_Values_JSON__c;
                result.add(view);
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getRows');
        }
    }

    private static BatchView toView(Import_Batch__c batch) {
        if (batch == null) {
            return null;
        }
        BatchView view = new BatchView();
        view.id = batch.Id;
        view.name = batch.Name;
        view.fileName = batch.File_Name__c;
        // An undo whose job was aborted shows as Undo failed, which it is (R-IB8).
        view.status = ImportUndoService.effectiveStatus(batch);
        view.isDryRun = batch.Is_Dry_Run__c;
        view.isFinished =
            ImportBatchService.STATUS_DRY_RUN_COMPLETE.equals(view.status) ||
            ImportBatchService.STATUS_COMPLETE.equals(view.status) ||
            ImportBatchService.STATUS_FAILED.equals(view.status) ||
            ImportBatchService.STATUS_UNDONE.equals(view.status) ||
            ImportBatchService.STATUS_UNDO_FAILED.equals(view.status);
        view.rowCount = intOf(batch.Row_Count__c);
        view.created = intOf(batch.Rows_Created__c);
        view.updated = intOf(batch.Rows_Updated__c);
        view.matched = intOf(batch.Rows_Matched__c);
        view.rejected = intOf(batch.Rows_Rejected__c);
        view.runLog = batch.Run_Log__c;
        view.undoDeadline = batch.Undo_Deadline__c;
        view.canUndo = String.isBlank(ImportUndoService.refusal(batch));
        view.controlTotalsAgree = ImportBatchService.controlTotalsAgree(batch);
        return view;
    }

    /** The wizard's options, or none; a document that cannot be read is refused, not guessed. */
    @TestVisible
    private static BatchOptions parseOptions(String optionsJson) {
        if (String.isBlank(optionsJson)) {
            return new BatchOptions();
        }
        try {
            BatchOptions options = (BatchOptions) JSON.deserialize(optionsJson, BatchOptions.class);
            return options == null ? new BatchOptions() : options;
        } catch (Exception unreadable) {
            throw new ImportException(Label.Core_Import_ErrorOptionsUnreadable);
        }
    }

    private static Integer intOf(Decimal value) {
        return value == null ? 0 : value.intValue();
    }

    private static void enforcePermission() {
        if (!hasManagePermission()) {
            throw new ImportException(Label.Core_Import_ErrorNoPermission);
        }
    }

    private static Boolean hasManagePermission() {
        if (permissionOverride != null) {
            return permissionOverride;
        }
        return FeatureManagement.checkPermission('Manage_Nonprofit_Settings');
    }

    /**
     * Logs once and wraps the message for the component. setMessage keeps the readable text
     * on the exception, which AuraHandledException otherwise replaces with a generic message.
     */
    private static AuraHandledException auraError(Exception e, String context) {
        ErrorLogger.log(e, context);
        AuraHandledException wrapped = new AuraHandledException(e.getMessage());
        wrapped.setMessage(e.getMessage());
        return wrapped;
    }
}
