/**
 * What the Data Quality section of Org Optimizer reads and does (C-28, admin guide data-hygiene.md, canonical model
 * R-SQ6, ADR-0079 `0079-data-hygiene-checks-are-find-queries-built-at-request-time.md`).
 *
 * Both methods require the Find and Export Records custom permission (R-SQ5): the console is a
 * way into Find and grants nothing of its own. Counts run in user mode (DataHygieneService).
 * "Open in Find" saves the check's query as the person's own unshared Saved Query through
 * FindController.saveQuery, so it is compiled, checked and stored exactly as Find stores one.
 */
public with sharing class DataHygieneController {
    private static final String FIND_TAB = 'Find';
    private static final String SAVED_QUERY_STATE = 'savedQueryId';

    /**
     * Where "Open in Find" goes. The tab name and the state key carry the package namespace, so
     * they come from here (NamespaceUtil), never from the component.
     */
    public class OpenInFind {
        @AuraEnabled
        public String savedQueryId;
        @AuraEnabled
        public String savedQueryName;
        @AuraEnabled
        public String findTabApiName;
        @AuraEnabled
        public String stateKey;
    }

    /** Every check with its count, or the reason it has none. */
    @AuraEnabled
    public static List<DataHygieneService.CheckResult> getChecks() {
        try {
            requirePermission();
            return DataHygieneService.runAll();
        } catch (Exception caught) {
            throw asUserError(caught, 'Data Quality checks');
        }
    }

    /**
     * Saves the check's query as the person's own saved query, named for the check, replacing
     * the query of their existing one of that name, and says where the Find tab is.
     */
    @AuraEnabled
    public static OpenInFind openInFind(String checkKey) {
        try {
            requirePermission();
            String document = DataHygieneService.queryDocument(checkKey);
            String name = DataHygieneService.savedQueryName(checkKey);
            Id existing = ownSavedQueryNamed(name);
            FindController.saveQuery(existing, name, document, false);
            OpenInFind target = new OpenInFind();
            // The query just updated, or, when there was none, the one just created: read
            // back by owner and name, not picked from Find's list, which is cut at 500 and
            // can hold two of a name.
            target.savedQueryId = existing != null ? existing : ownSavedQueryNamed(name);
            target.savedQueryName = name;
            target.findTabApiName = NamespaceUtil.qualify(FIND_TAB);
            target.stateKey = NamespaceUtil.stateKey(SAVED_QUERY_STATE);
            return target;
        } catch (AuraHandledException alreadyForThePerson) {
            throw alreadyForThePerson;
        } catch (Exception caught) {
            throw asUserError(caught, 'Open a Data Quality check in Find');
        }
    }

    private static Id ownSavedQueryNamed(String name) {
        Id me = UserInfo.getUserId();
        List<Saved_Query__c> found = [
            SELECT Id
            FROM Saved_Query__c
            WHERE OwnerId = :me AND Name = :name
            WITH USER_MODE
            ORDER BY CreatedDate
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0].Id;
    }

    private static void requirePermission() {
        if (!FeatureManagement.checkPermission(FindController.PERMISSION)) {
            throw new DataHygieneService.DataHygieneException(
                System.Label.Core_DataHygiene_ErrorNoPermission
            );
        }
    }

    /** Anything the person can act on is shown as it is; anything else is logged and summarized. */
    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof DataHygieneService.DataHygieneException,
            context,
            System.Label.Core_DataHygiene_CheckFailed
        );
    }
}
