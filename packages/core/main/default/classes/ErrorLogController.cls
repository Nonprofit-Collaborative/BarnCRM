/**
 * What the Error Log tile on the BarnCRM home page reads and writes.
 *
 * Reads run in user mode through the selector, so a person sees only the entries their access
 * allows. Marking an entry acknowledged is the one write, and it is the only field this class
 * changes.
 */
public with sharing class ErrorLogController {
    private static final Integer DEFAULT_ROWS = 5;

    /** The tile counts this many and then says "more". A test lowers it. */
    @TestVisible
    private static Integer newCountCap = 999;

    /**
     * One entry as the tile shows it.
     */
    public class ErrorLogView {
        @AuraEnabled
        public String recordId { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String message { get; set; }
        @AuraEnabled
        public String context { get; set; }
        @AuraEnabled
        public String severity { get; set; }
        @AuraEnabled
        public String status { get; set; }
        @AuraEnabled
        public Datetime occurredAt { get; set; }
    }

    /**
     * The tile: how many are waiting, and the most recent few.
     */
    public class ErrorLogTileView {
        @AuraEnabled
        public Integer newCount { get; set; }
        /** True when there are more new entries than `newCount`, the most the tile counts. */
        @AuraEnabled
        public Boolean newCountCapped { get; set; }
        @AuraEnabled
        public Boolean canUpdate { get; set; }
        @AuraEnabled
        public List<ErrorLogView> recent { get; set; }
    }

    @AuraEnabled(cacheable=true)
    public static ErrorLogTileView getTile(Integer rowCount) {
        try {
            return currentTile(rowCount);
        } catch (Exception caught) {
            throw asUserError(caught, 'Error Log tile');
        }
    }

    @AuraEnabled
    public static ErrorLogTileView acknowledge(String errorLogId) {
        try {
            Error_Log__c entry = validatedEntry(errorLogId);
            if (entry.Status__c != ErrorLogger.STATUS_ACKNOWLEDGED) {
                entry.Status__c = ErrorLogger.STATUS_ACKNOWLEDGED;
                Database.update(entry, AccessLevel.USER_MODE);
            }
            return currentTile(DEFAULT_ROWS);
        } catch (Exception caught) {
            throw asUserError(caught, 'Mark an error acknowledged');
        }
    }

    private static Error_Log__c validatedEntry(String errorLogId) {
        Id entryId = asRecordId(errorLogId);
        if (entryId == null || entryId.getSObjectType() != Error_Log__c.SObjectType) {
            throw new ErrorLogControllerException(Label.Core_ErrorLog_EntryNotFound);
        }
        List<Error_Log__c> found = ErrorLogSelector.selectByIds(new Set<Id>{ entryId });
        if (found.isEmpty()) {
            throw new ErrorLogControllerException(Label.Core_ErrorLog_EntryNotFound);
        }
        return found[0];
    }

    private static Id asRecordId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return Id.valueOf(value);
        } catch (Exception notAnId) {
            return null;
        }
    }

    private static ErrorLogTileView currentTile(Integer rowCount) {
        ErrorLogTileView tile = new ErrorLogTileView();
        // One capped count for every Error Log tile (ADMIN-8): a flooded log costs at most
        // newCountCap + 1 query rows.
        Integer found = ErrorLogCountSelector.countNewUpTo(newCountCap);
        tile.newCountCapped = found > newCountCap;
        tile.newCount = Math.min(found, newCountCap);
        tile.canUpdate = Schema.SObjectType.Error_Log__c.isUpdateable();
        tile.recent = new List<ErrorLogView>();
        for (Error_Log__c entry : ErrorLogSelector.selectRecent(rowCount)) {
            ErrorLogView view = new ErrorLogView();
            view.recordId = entry.Id;
            view.name = entry.Name;
            view.message = entry.Message__c;
            view.context = entry.Context__c;
            view.severity = entry.Severity__c;
            view.status = entry.Status__c;
            view.occurredAt = entry.Timestamp__c;
            tile.recent.add(view);
        }
        return tile;
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        String message = caught.getMessage();
        if (!(caught instanceof ErrorLogControllerException)) {
            ErrorLogger.log(caught, context);
            message = Label.Core_ErrorLog_ActionFailed;
        }
        AuraHandledException reported = new AuraHandledException(message);
        reported.setMessage(message);
        return reported;
    }

    public class ErrorLogControllerException extends Exception {
    }
}
