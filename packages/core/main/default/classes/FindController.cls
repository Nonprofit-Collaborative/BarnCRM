/**
 * What the Find tab reads and writes (C-34, plan Section 4.9, canonical model Section 29D).
 *
 * Every method requires the Find and Export Records custom permission (R-SQ5), which opens the
 * tool and grants no record access. Queries are compiled from the query document by
 * QueryCompiler and run in user mode; no SOQL text is accepted. Saved queries are read and
 * written as the user, and only the owner may change, share or delete one; the one system-mode
 * write, the share row, is SavedQuerySharingWriter's (ADR-0076, saved queries).
 */
public with sharing class FindController {
    /** Raised for anything the person can fix; the message is shown as it is. */
    public class FindException extends Exception {
    }

    public static final String PERMISSION = 'Find_And_Export_Records';
    public static final Integer DEFAULT_EXPORT_LIMIT = 50000;
    public static final Integer MAX_EXPORT_LIMIT = 500000;
    private static final Integer MAX_SAVED_QUERIES = 500;
    private static final Set<String> SYSTEM_SUFFIXES = new Set<String>{
        '__mdt',
        '__e',
        '__share',
        '__history',
        '__feed',
        '__changeevent',
        '__x',
        '__b'
    };

    /** One choice in a list. */
    public class Option {
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String value;
    }

    /** One saved query, as the list shows it. */
    public class SavedQueryView {
        @AuraEnabled
        public String recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String queryJson;
        @AuraEnabled
        public Boolean shared;
        @AuraEnabled
        public Boolean mine;
        @AuraEnabled
        public String ownerName;
    }

    /** The page: the export limit and the saved queries, the person's own first. */
    public class FindPage {
        @AuraEnabled
        public Integer exportLimit;
        @AuraEnabled
        public Integer maxRows;
        @AuraEnabled
        public Integer exportPageSize;
        @AuraEnabled
        public List<SavedQueryView> savedQueries;
        /** Whether the person may also bulk update the results (C-35, R-BU6). */
        @AuraEnabled
        public Boolean canBulkUpdate;
        /** Whether the person may also bulk delete the results (C-37, R-BD6). */
        @AuraEnabled
        public Boolean canBulkDelete;
    }

    /** The rows a query returned and the SOQL it ran, for display only. */
    public class QueryResult {
        @AuraEnabled
        public String soql;
        @AuraEnabled
        public List<SObject> rows;
        @AuraEnabled
        public String lastId;
        @AuraEnabled
        public Boolean done;
    }

    @AuraEnabled
    public static FindPage getPage() {
        try {
            requirePermission();
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Find page');
        }
    }

    /** Every object the person can query, by label. Custom settings and system objects are left out. */
    @AuraEnabled(cacheable=true)
    public static List<Option> listObjects() {
        try {
            requirePermission();
            Map<String, Option> byLabel = new Map<String, Option>();
            for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
                Schema.DescribeSObjectResult objectDescribe = type.getDescribe(
                    SObjectDescribeOptions.DEFERRED
                );
                if (!isOffered(objectDescribe)) {
                    continue;
                }
                Option option = new Option();
                option.label = objectDescribe.getLabel();
                option.value = objectDescribe.getName();
                byLabel.put(option.label.toLowerCase() + '\u0000' + option.value, option);
            }
            List<String> keys = new List<String>(byLabel.keySet());
            keys.sort();
            List<Option> options = new List<Option>();
            for (String key : keys) {
                options.add(byLabel.get(key));
            }
            return options;
        } catch (Exception caught) {
            throw asUserError(caught, 'Find object list');
        }
    }

    /** The SOQL a document compiles to, for display, or the refusal that says what to fix. */
    @AuraEnabled
    public static String previewQuery(String queryJson) {
        try {
            requirePermission();
            return QueryCompiler.compile(queryJson).display;
        } catch (Exception caught) {
            throw asUserError(caught, 'Find preview');
        }
    }

    /** The kinds of related record of an object, for related records (C-36, R-SQ8). */
    @AuraEnabled(cacheable=true)
    public static List<FindRelatedRecords.ChildOption> listChildRelationships(
        String objectApiName
    ) {
        try {
            requirePermission();
            return FindRelatedRecords.childOptions(objectApiName);
        } catch (Exception caught) {
            throw asUserError(caught, 'Find related records');
        }
    }

    /** Runs a document with the person's own access. */
    @AuraEnabled
    public static QueryResult runQuery(String queryJson) {
        try {
            requirePermission();
            QueryCompiler.Compiled compiled = QueryCompiler.compile(queryJson);
            QueryResult result = new QueryResult();
            result.soql = compiled.display;
            result.rows = QueryCompiler.run(compiled);
            result.done = true;
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Run a Find query');
        }
    }

    /** The document's summary, counted or totalled as the person (C-36, R-SQ9). */
    @AuraEnabled
    public static FindSummary.SummaryResult summarize(String queryJson) {
        try {
            requirePermission();
            return FindSummary.summarize(queryJson);
        } catch (Exception caught) {
            throw asUserError(caught, 'Summarize a Find query');
        }
    }

    /**
     * Saves values edited in the results grid (C-36, R-SQ10). Needs the bulk update permission
     * as well as Find's (R-BU6).
     */
    @AuraEnabled
    public static FindInlineEditService.SaveSummary saveEdits(
        String objectApiName,
        String editsJson
    ) {
        try {
            requirePermission();
            if (!BulkUpdateController.hasPermission()) {
                throw new FindException(System.Label.Core_BulkUpdate_ErrorNoPermission);
            }
            return FindInlineEditService.save(objectApiName, editsJson);
        } catch (Exception caught) {
            throw asUserError(caught, 'Save edits in Find');
        }
    }

    /** One export page in Id order, after the last Id the browser has read (R-SQ3). */
    @AuraEnabled
    public static QueryResult exportPage(String queryJson, String afterId) {
        try {
            requirePermission();
            Id after = String.isBlank(afterId) ? null : Id.valueOf(afterId);
            QueryCompiler.Compiled compiled = QueryCompiler.compileExportPage(queryJson, after);
            QueryResult result = new QueryResult();
            result.soql = compiled.display;
            result.rows = QueryCompiler.run(compiled);
            result.done = result.rows.size() < QueryCompiler.EXPORT_PAGE_SIZE;
            result.lastId = result.rows.isEmpty()
                ? afterId
                : String.valueOf(result.rows[result.rows.size() - 1].Id);
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Export a Find query');
        }
    }

    /**
     * Saves a query under a name: a new one when recordId is empty, otherwise the person's own.
     * The document is compiled first, so a query that would not run is never saved.
     */
    @AuraEnabled
    public static FindPage saveQuery(
        String recordId,
        String name,
        String queryJson,
        Boolean shared
    ) {
        try {
            requirePermission();
            if (String.isBlank(name) || name.trim().length() > 80) {
                throw new FindException(System.Label.Core_Find_ErrorName);
            }
            QueryCompiler.Compiled compiled = QueryCompiler.compile(queryJson);
            Saved_Query__c query = new Saved_Query__c(
                Name = name.trim(),
                Object_Name__c = compiled.objectName,
                Query_JSON__c = queryJson,
                Shared__c = shared == true
            );
            if (String.isBlank(recordId)) {
                Database.insert(query, AccessLevel.USER_MODE);
            } else {
                query.Id = requireOwn(recordId).Id;
                Database.update(query, AccessLevel.USER_MODE);
            }
            SavedQuerySharingWriter.setShared(new Map<Id, Boolean>{ query.Id => shared == true });
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Save a Find query');
        }
    }

    /** Deletes one of the person's own saved queries; its share goes with it. */
    @AuraEnabled
    public static FindPage deleteQuery(String recordId) {
        try {
            requirePermission();
            Database.delete(requireOwn(recordId), AccessLevel.USER_MODE);
            return currentPage();
        } catch (Exception caught) {
            throw asUserError(caught, 'Delete a Find query');
        }
    }

    /** The export limit from BarnCRM Settings, held between 1 and MAX_EXPORT_LIMIT. */
    public static Integer exportLimit() {
        Object configured = SettingsService.hasKey('Find_Export_Row_Limit__c')
            ? SettingsService.getValue('Find_Export_Row_Limit__c')
            : null;
        if (configured == null) {
            return DEFAULT_EXPORT_LIMIT;
        }
        try {
            Integer rows = Decimal.valueOf(String.valueOf(configured)).intValue();
            return rows < 1 ? DEFAULT_EXPORT_LIMIT : Math.min(rows, MAX_EXPORT_LIMIT);
        } catch (Exception ignored) {
            return DEFAULT_EXPORT_LIMIT;
        }
    }

    private static FindPage currentPage() {
        FindPage page = new FindPage();
        page.exportLimit = exportLimit();
        page.maxRows = QueryCompiler.MAX_ROWS;
        page.exportPageSize = QueryCompiler.EXPORT_PAGE_SIZE;
        page.canBulkUpdate = BulkUpdateController.hasPermission();
        page.canBulkDelete = BulkDeleteController.hasPermission();
        List<SavedQueryView> mine = new List<SavedQueryView>();
        List<SavedQueryView> others = new List<SavedQueryView>();
        Id me = UserInfo.getUserId();
        for (Saved_Query__c query : [
            SELECT Id, Name, Object_Name__c, Query_JSON__c, Shared__c, OwnerId, Owner.Name
            FROM Saved_Query__c
            WITH USER_MODE
            ORDER BY Name
            LIMIT :MAX_SAVED_QUERIES
        ]) {
            SavedQueryView view = new SavedQueryView();
            view.recordId = query.Id;
            view.name = query.Name;
            view.objectName = query.Object_Name__c;
            view.queryJson = query.Query_JSON__c;
            view.shared = query.Shared__c;
            view.mine = query.OwnerId == me;
            view.ownerName = query.Owner?.Name;
            (view.mine ? mine : others).add(view);
        }
        page.savedQueries = new List<SavedQueryView>(mine);
        page.savedQueries.addAll(others);
        return page;
    }

    private static Saved_Query__c requireOwn(String recordId) {
        List<Saved_Query__c> found = String.isBlank(recordId)
            ? new List<Saved_Query__c>()
            : [
                  SELECT Id, OwnerId
                  FROM Saved_Query__c
                  WHERE Id = :recordId
                  WITH USER_MODE
                  LIMIT 1
              ];
        if (found.isEmpty()) {
            throw new FindException(System.Label.Core_Find_ErrorNotFound);
        }
        if (found[0].OwnerId != UserInfo.getUserId()) {
            throw new FindException(System.Label.Core_Find_ErrorNotYours);
        }
        return found[0];
    }

    private static Boolean isOffered(Schema.DescribeSObjectResult objectDescribe) {
        if (
            !objectDescribe.isAccessible() ||
            !objectDescribe.isQueryable() ||
            objectDescribe.isCustomSetting() ||
            objectDescribe.isDeprecatedAndHidden()
        ) {
            return false;
        }
        String name = objectDescribe.getName().toLowerCase();
        for (String suffix : SYSTEM_SUFFIXES) {
            if (name.endsWith(suffix)) {
                return false;
            }
        }
        return true;
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(PERMISSION)) {
            throw new FindException(System.Label.Core_Find_ErrorNoPermission);
        }
    }

    /** Anything the person can fix is shown as it is; anything else is logged and summarized. */
    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (
            !(caught instanceof FindException) &&
            !(caught instanceof QueryCompiler.QueryCompilerException) &&
            !(caught instanceof QueryFieldCatalog.QueryFieldCatalogException) &&
            !(caught instanceof BulkUpdateFields.BulkUpdateException)
        ) {
            ErrorLogger.log(caught, context);
            message = System.Label.Core_Find_UnexpectedError;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }
}
