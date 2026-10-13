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
     * Manage_BarnCRM_Settings custom permission is not assigned to the running user. Null
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
        public String paymentMatching;
        @AuraEnabled
        public Integer matchDateWindowDays;
        @AuraEnabled
        public Decimal matchAmountTolerance;
        /** How this template matches (R-IT2, R-IT8, R-IT9). */
        @AuraEnabled
        public String personMatchField;
        @AuraEnabled
        public String organizationRule;
        @AuraEnabled
        public String organizationMatchField;
        @AuraEnabled
        public String severalMatches;
        /** Whether the org's duplicate rules are asked too (R-IT16). */
        @AuraEnabled
        public Boolean useDuplicateRules;
        /** For a template that loads one object (R-IT12, R-IT13). */
        @AuraEnabled
        public String targetObject;
        @AuraEnabled
        public String targetObjectLabel;
        @AuraEnabled
        public String loadOperation;
        /** The operations this object allows: Update only for people (R-IT14). */
        @AuraEnabled
        public List<String> loadOperations;
        @AuraEnabled
        public String loadMatchField;
        @AuraEnabled
        public String lookupNotFound;
    }

    /** One field a column of a one-object template can be mapped to (R-IT12). */
    public class FieldChoice {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean isLookup = false;
        /** For a lookup, the fields it can name its parent by, the record ID first (R-IT13). */
        @AuraEnabled
        public List<ImportMapping.Target> lookupFields = new List<ImportMapping.Target>();
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
        /** True when the wizard showed the payment matching choices, which are then saved. */
        public Boolean savePaymentMatching;
        public String paymentMatching;
        public Integer matchDateWindowDays;
        public Decimal matchAmountTolerance;
        /** How people and organizations are matched, saved on the template when sent (R-IT2). */
        public ImportTemplateService.MatchingChoices matching;
        /** The values every row of this file takes where it has none (R-IB14). */
        public List<ImportMapping.Assignment> fileValues;
        /** True when the file only matches and creates nobody (R-IB15). */
        public Boolean matchOnly;
        /** A one-object template's load choices, saved on it when sent (R-IT12). */
        public ImportTemplateService.LoadChoices load;
    }

    /** A field a row can be matched on, as the wizard lists it (R-IT8). */
    public class MatchFieldView {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
    }

    /** The fields each object offers for matching under External ID (R-IT8). */
    public class MatchFieldsView {
        /** Contact fields, for people stored as contacts. */
        @AuraEnabled
        public List<MatchFieldView> contact = new List<MatchFieldView>();
        /** Account fields, for organizations and for people stored as person accounts. */
        @AuraEnabled
        public List<MatchFieldView> account = new List<MatchFieldView>();
        /** The fields a person's column can be mapped to besides the fixed list (R-IT11). */
        @AuraEnabled
        public List<ImportMapping.Target> personFields = new List<ImportMapping.Target>();
        /** The fields an organization's column can be mapped to besides the fixed list. */
        @AuraEnabled
        public List<ImportMapping.Target> organizationFields = new List<ImportMapping.Target>();
        /**
         * Whether contacts, and accounts, have an active duplicate rule the user can see; null
         * when the user cannot read the rules (R-IT16).
         */
        @AuraEnabled
        public Boolean contactRules;
        @AuraEnabled
        public Boolean accountRules;
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

    /**
     * One page of rows read through a pagination cursor. The screen hands the cursor and
     * nextIndex back to read the next page, until hasMore is false.
     */
    public class RowPage {
        @AuraEnabled
        public Database.PaginationCursor cursor;
        @AuraEnabled
        public List<RowView> rows = new List<RowView>();
        @AuraEnabled
        public Integer nextIndex = 0;
        /** How many rows the cursor holds, at most ImportRowSelector.MAX_CURSOR_ROWS. */
        @AuraEnabled
        public Integer total = 0;
        @AuraEnabled
        public Boolean hasMore = false;
    }

    /** The most rows one page may hold (the platform's limit for a pagination cursor page). */
    @TestVisible
    private static final Integer MAX_PAGE_ROWS = 2000;

    /** How many rows the changed values are shown for, in the wizard and after a dry run. */
    @TestVisible
    private static final Integer CHANGED_SAMPLE_ROWS = 5;

    /** One cell before and after its column's changes (R-IT15). */
    public class ChangedValue {
        @AuraEnabled
        public Integer rowNumber;
        @AuraEnabled
        public String column;
        @AuraEnabled
        public String before;
        @AuraEnabled
        public String after;
    }

    /** What a column's changes would do to the sample rows, and what stops them saving. */
    public class ChangesPreview {
        @AuraEnabled
        public List<String> problems = new List<String>();
        @AuraEnabled
        public List<ChangedValue> samples = new List<ChangedValue>();
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
                view.paymentMatching = template.Payment_Matching__c;
                view.matchDateWindowDays = template.Match_Date_Window_Days__c == null
                    ? null
                    : template.Match_Date_Window_Days__c.intValue();
                view.matchAmountTolerance = template.Match_Amount_Tolerance__c;
                view.personMatchField = template.Person_Match_Field__c;
                view.organizationRule = ImportTemplateService.normalizedOrganizationRule(
                    template.Organization_Matching_Rule__c
                );
                view.organizationMatchField = template.Organization_Match_Field__c;
                view.severalMatches = ImportTemplateService.normalizedSeveralMatches(
                    template.Several_Matches__c
                );
                view.useDuplicateRules = template.Use_Duplicate_Rules__c == true;
                describeLoad(template, view);
                result.add(view);
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getTemplates');
        }
    }

    /**
     * The fields a row can be matched on under External ID, for people and organizations
     * (R-IT8): those marked External ID or Unique, holding text or an email, that the user
     * may read. With them, the fields of people and organizations a column can be mapped to
     * besides the fixed list (R-IT11).
     */
    @AuraEnabled
    public static MatchFieldsView getMatchFields() {
        try {
            enforcePermission();
            MatchFieldsView view = new MatchFieldsView();
            view.contact = fieldViews(Contact.SObjectType);
            view.account = fieldViews(Account.SObjectType);
            view.personFields = ImportFieldCatalog.personFields();
            view.organizationFields = ImportFieldCatalog.organizationFields();
            view.contactRules = ImportDuplicateRuleMatcher.hasActiveRule(Contact.SObjectType);
            view.accountRules = ImportDuplicateRuleMatcher.hasActiveRule(Account.SObjectType);
            return view;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getMatchFields');
        }
    }

    private static List<MatchFieldView> fieldViews(Schema.SObjectType type) {
        List<MatchFieldView> result = new List<MatchFieldView>();
        for (Schema.DescribeFieldResult describe : ImportMatcher.matchableFields(type)) {
            MatchFieldView field = new MatchFieldView();
            field.value = describe.getName();
            field.label = describe.getLabel();
            result.add(field);
        }
        return result;
    }

    /** The objects a template may load (R-IT14), by label. */
    @AuraEnabled
    public static List<ImportMapping.Target> getLoadableObjects() {
        try {
            enforcePermission();
            return ImportObjectSchema.loadableObjects();
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getLoadableObjects');
        }
    }

    /** Creates a template that loads one object, and returns it as the wizard shows it. */
    @AuraEnabled
    public static TemplateView createObjectTemplate(String name, String objectName) {
        try {
            enforcePermission();
            Import_Template__c template = ImportTemplateSelector.selectById(
                ImportTemplateService.createObjectTemplate(name, objectName).Id
            );
            TemplateView view = new TemplateView();
            view.id = template.Id;
            view.name = template.Name;
            view.description = template.Description__c;
            view.matchingRule = template.Matching_Rule__c;
            view.personMode = template.Person_Mode__c;
            view.mapping = template.Column_Mapping_JSON__c;
            view.isPackageDefault = false;
            view.isRecurring = false;
            view.organizationRule = ImportTemplateService.ORGANIZATION_RULE_NAME;
            view.severalMatches = ImportTemplateService.SEVERAL_REJECT;
            describeLoad(template, view);
            return view;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.createObjectTemplate');
        }
    }

    /**
     * The fields a column of this one-object template can be mapped to (R-IT12): the record ID
     * first, then the fields the user may write, and for each lookup the fields it can name its
     * parent by (R-IT13).
     */
    @AuraEnabled
    public static List<FieldChoice> getObjectFields(String templateId) {
        try {
            enforcePermission();
            Schema.SObjectType type = ImportObjectSchema.typeOf(
                ImportTemplateSelector.selectById(templateId)
            );
            List<FieldChoice> result = new List<FieldChoice>();
            if (type == null) {
                return result;
            }
            for (ImportMapping.Target target : ImportObjectSchema.writableFields(type)) {
                FieldChoice choice = new FieldChoice();
                choice.value = ImportMapping.ENTITY_RECORD + '.' + target.value;
                choice.label = target.label;
                Schema.SObjectField token = ImportObjectSchema.fieldNamed(type, target.value);
                if (
                    token != null &&
                    token.getDescribe().getType() == Schema.DisplayType.REFERENCE
                ) {
                    choice.isLookup = true;
                    choice.lookupFields = ImportObjectSchema.parentFields(type, target.value);
                }
                result.add(choice);
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getObjectFields');
        }
    }

    /** The external ID fields an upsert of this template's object can match on (R-IT12). */
    @AuraEnabled
    public static List<ImportMapping.Target> getKeyFields(String templateId) {
        try {
            enforcePermission();
            return ImportObjectSchema.keyFields(
                ImportObjectSchema.typeOf(ImportTemplateSelector.selectById(templateId))
            );
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getKeyFields');
        }
    }

    /** Fills in what a one-object template loads, and how. */
    private static void describeLoad(Import_Template__c template, TemplateView view) {
        Schema.SObjectType type = ImportObjectSchema.typeOf(template);
        if (!ImportObjectSchema.loadsOneObject(template) || type == null) {
            return;
        }
        Schema.DescribeSObjectResult described = type.getDescribe(SObjectDescribeOptions.DEFERRED);
        view.targetObject = described.getName();
        view.targetObjectLabel = described.getLabel();
        view.loadOperation = ImportObjectSchema.updatesOnly(type)
            ? ImportObjectSchema.OPERATION_UPDATE
            : ImportObjectSchema.operationOf(template);
        view.loadOperations = ImportObjectSchema.operationsFor(type);
        view.loadMatchField = template.Load_Match_Field__c;
        view.lookupNotFound = ImportObjectSchema.leavesLookupEmpty(template)
            ? ImportObjectSchema.LOOKUP_LEAVE_EMPTY
            : ImportObjectSchema.LOOKUP_REJECT;
    }

    /** The parent field a saved column names its parent by, for the column with this source. */
    private static String lookupFieldOf(ImportMapping saved, String sourceKey) {
        for (ImportMapping.Column column : saved.columns) {
            if (column != null && ImportMapping.key(column.source) == sourceKey) {
                return column.lookupField;
            }
        }
        return null;
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
            Import_Template__c template = ImportTemplateSelector.selectById(templateId);
            // A one-object template suggests from its object's fields (R-IT12).
            ImportMapping suggested = ImportObjectSchema.loadsOneObject(template)
                ? ImportObjectSchema.suggestMapping(ImportObjectSchema.typeOf(template), headers)
                : ImportColumnLibrary.suggestMapping(headers);
            if (template != null) {
                ImportMapping saved = ImportMapping.parse(template.Column_Mapping_JSON__c);
                Map<String, String> known = saved.targetsBySourceKey();
                Set<String> ignored = saved.ignoredSourceKeys();
                for (ImportMapping.Column column : suggested.columns) {
                    String source = ImportMapping.key(column.source);
                    String fromTemplate = known.get(source);
                    if (String.isNotBlank(fromTemplate)) {
                        column.target = fromTemplate;
                        column.lookupField = lookupFieldOf(saved, source);
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
            if (options.savePaymentMatching == true) {
                ImportTemplateService.savePaymentMatching(
                    templateId,
                    options.paymentMatching,
                    options.matchDateWindowDays,
                    options.matchAmountTolerance
                );
            }
            if (options.load != null) {
                ImportTemplateService.saveLoad(templateId, options.load);
            }
            if (options.matching != null) {
                // The wizard's rule for people is the one passed above; the rest is saved here.
                options.matching.personRule = matchingRule;
                ImportTemplateService.saveMatching(templateId, options.matching);
            }
            return toView(
                ImportBatchService.create(
                    templateId,
                    fileId,
                    fileName,
                    options.expectedCount,
                    options.expectedAmount,
                    options.fileValues,
                    options.matchOnly == true
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
     * One page of a batch's rows in file order, optionally only those in one status. The
     * rejected-rows table reads the first page; the exceptions file reads every page with
     * status Rejected. Pass no cursor to open one; then pass back the cursor and nextIndex
     * this returned, until hasMore is false.
     *
     * @param pageSize rows per page, held between 1 and MAX_PAGE_ROWS
     */
    @AuraEnabled
    public static RowPage getRowPage(
        String batchId,
        String status,
        Database.PaginationCursor cursor,
        Integer startIndex,
        Integer pageSize
    ) {
        try {
            RowPage page = new RowPage();
            if (String.isBlank(batchId)) {
                return page;
            }
            page.cursor = cursor == null
                ? ImportRowSelector.openCursor(Id.valueOf(batchId), status)
                : cursor;
            page.total = page.cursor.getNumRecords();
            Integer start = startIndex == null || startIndex < 0 ? 0 : startIndex;
            Integer size = pageSize == null ||
                pageSize < 1
                ? ImportRowSelector.PAGE_SIZE
                : Math.min(pageSize, MAX_PAGE_ROWS);
            size = Math.min(size, page.total - start);
            page.nextIndex = Math.min(start, page.total);
            if (size > 0) {
                Database.CursorFetchResult fetched = page.cursor.fetchPage(start, size);
                for (SObject record : fetched.getRecords()) {
                    page.rows.add(toRowView((Import_Row__c) record));
                }
                page.nextIndex = fetched.getNextIndex();
            }
            // The cursor's own isDone is per page, so the whole read is judged by position.
            page.hasMore = page.nextIndex < page.total;
            return page;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getRowPage');
        }
    }

    private static RowView toRowView(Import_Row__c row) {
        RowView view = new RowView();
        view.id = row.Id;
        view.rowNumber = row.Row_Number__c == null ? null : row.Row_Number__c.intValue();
        view.status = row.Status__c;
        view.errorMessage = row.Error_Message__c;
        view.values = row.Raw_Values_JSON__c;
        return view;
    }

    /**
     * What a column's changes do to the first rows of the file, and what is wrong with them
     * (R-IT15). Nothing is saved: the wizard shows this while the admin edits the steps.
     *
     * @param source the column the steps belong to
     * @param transformsJson the steps, as the mapping document holds them
     * @param sampleRowsJson the first rows of the file, each a map of column name to value
     */
    @AuraEnabled
    public static ChangesPreview previewChanges(
        String source,
        String transformsJson,
        String sampleRowsJson
    ) {
        try {
            enforcePermission();
            ChangesPreview preview = new ChangesPreview();
            List<DataTransform.Step> steps = DataTransform.parse(transformsJson);
            preview.problems = DataTransform.problems(steps);
            List<Object> rows = String.isBlank(sampleRowsJson)
                ? new List<Object>()
                : (List<Object>) JSON.deserializeUntyped(sampleRowsJson);
            for (Integer i = 0; i < rows.size() && i < CHANGED_SAMPLE_ROWS; i++) {
                Map<String, String> values = new Map<String, String>();
                Map<String, Object> row = (Map<String, Object>) rows[i];
                for (String column : row.keySet()) {
                    Object value = row.get(column);
                    values.put(
                        ImportMapping.key(column),
                        value == null ? null : String.valueOf(value).trim()
                    );
                }
                ChangedValue sample = new ChangedValue();
                sample.rowNumber = i + 2;
                sample.column = source;
                sample.before = values.get(ImportMapping.key(source));
                sample.after = DataTransform.apply(steps, sample.before, values);
                preview.samples.add(sample);
            }
            return preview;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.previewChanges');
        }
    }

    /**
     * Each changed value of the batch's first rows, before and after (R-IT15), for the results
     * screen of a dry run. Empty when the mapping changes nothing.
     */
    @AuraEnabled
    public static List<ChangedValue> getChangedValues(String batchId) {
        try {
            List<ChangedValue> result = new List<ChangedValue>();
            Import_Batch__c batch = ImportBatchSelector.selectById(batchId);
            Import_Template__c template = batch == null
                ? null
                : ImportTemplateSelector.selectById(batch.Import_Template__c);
            if (template == null) {
                return result;
            }
            ImportMapping mapping = ImportMapping.parse(
                template.Column_Mapping_JSON__c,
                template.Default_Values_JSON__c
            );
            if (mapping.transformsBySourceKey().isEmpty()) {
                return result;
            }
            List<Import_Row__c> rows = ImportRowSelector.selectFirstPage(batchId);
            for (Integer i = 0; i < rows.size() && i < CHANGED_SAMPLE_ROWS; i++) {
                for (List<String> cell : ImportRowProcessor.changedValues(rows[i], mapping)) {
                    ChangedValue changed = new ChangedValue();
                    changed.rowNumber = rows[i].Row_Number__c == null
                        ? null
                        : rows[i].Row_Number__c.intValue();
                    changed.column = cell[0];
                    changed.before = cell[1];
                    changed.after = cell[2];
                    result.add(changed);
                }
            }
            return result;
        } catch (Exception e) {
            throw auraError(e, 'ImportController.getChangedValues');
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
        return FeatureManagement.checkPermission('Manage_BarnCRM_Settings');
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
