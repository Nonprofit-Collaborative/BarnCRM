/**
 * The Field Access Manager: Access Explorer's Change Field Access view (C-65, ADR-0156,
 * canonical model Section 29ZP, admin guide field-access-manager.md).
 *
 * Thin: every method checks Manage BarnCRM Settings and Manage Profiles and Permission Sets
 * (R-FA2), calls `FieldAccessService`, and returns plain JSON shapes (plan Section 9.9).
 */
public with sharing class FieldAccessController {
    private static final Integer CHANGES_LISTED = 20;
    private static final Integer FAILURES_SHOWN = 20;

    /** Whether the person may change field access, and the limits the page shows. */
    public class Status {
        @AuraEnabled
        public Boolean canChange = false;
        @AuraEnabled
        public String reason;
        @AuraEnabled
        public Integer maxSets = FieldAccessService.MAX_SETS;
        @AuraEnabled
        public Integer maxItems = FieldAccessService.MAX_ITEMS;
        @AuraEnabled
        public Integer maxRows = FieldAccessService.rowLimit();
    }

    public class SetChoice {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String detail;
    }

    /** One field the change may touch, with how many of the chosen sets give it now. */
    public class FieldOption {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public Boolean readOnly = false;
        @AuraEnabled
        public Integer readCount = 0;
        @AuraEnabled
        public Integer editCount = 0;
    }

    public class SetAccess {
        @AuraEnabled
        public String setId;
        @AuraEnabled
        public String setLabel;
        @AuraEnabled
        public Boolean read = false;
        @AuraEnabled
        public Boolean edit = false;
    }

    public class FieldList {
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public Integer setCount = 0;
        @AuraEnabled
        public List<SetAccess> objectAccess = new List<SetAccess>();
        @AuraEnabled
        public List<FieldOption> fields = new List<FieldOption>();
    }

    /** One permission row a change writes. */
    public class PreviewRow {
        @AuraEnabled
        public String setId;
        @AuraEnabled
        public String setLabel;
        @AuraEnabled
        public String objectName;
        @AuraEnabled
        public String objectLabel;
        @AuraEnabled
        public String fieldName;
        @AuraEnabled
        public String fieldLabel;
        @AuraEnabled
        public Boolean nowRead;
        @AuraEnabled
        public Boolean nowEdit;
        @AuraEnabled
        public Boolean afterRead;
        @AuraEnabled
        public Boolean afterEdit;
        @AuraEnabled
        public String reason;
    }

    public class Preview {
        @AuraEnabled
        public List<PreviewRow> rows = new List<PreviewRow>();
        @AuraEnabled
        public Integer changed = 0;
        @AuraEnabled
        public Integer unchanged = 0;
        @AuraEnabled
        public Integer setCount = 0;
        @AuraEnabled
        public Integer maxRows = FieldAccessService.rowLimit();
        @AuraEnabled
        public Boolean tooMany = false;
    }

    /** What an apply or undo did. */
    public class Outcome {
        @AuraEnabled
        public Integer changed = 0;
        @AuraEnabled
        public Integer refused = 0;
        @AuraEnabled
        public Integer kept = 0;
        @AuraEnabled
        public List<String> failures = new List<String>();
    }

    /** One change on the Recent Changes list. */
    public class ChangeJob {
        @AuraEnabled
        public String id;
        @AuraEnabled
        public Datetime createdAt;
        @AuraEnabled
        public String byName;
        @AuraEnabled
        public Integer changed = 0;
        @AuraEnabled
        public Integer refused = 0;
        @AuraEnabled
        public String status;
        @AuraEnabled
        public Boolean canUndo = false;
        @AuraEnabled
        public Datetime undoDeadline;
    }

    @AuraEnabled
    public static Status getStatus() {
        try {
            Status result = new Status();
            result.reason = FieldAccessService.refusal();
            result.canChange = result.reason == null;
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access status');
        }
    }

    /**
     * Permission sets the organization made whose label contains the term.
     * @param term at least two characters
     * @return up to 20, by label
     */
    @AuraEnabled
    public static List<SetChoice> searchSets(String term) {
        try {
            FieldAccessService.enforce();
            List<SetChoice> choices = new List<SetChoice>();
            for (PermissionSet permissionSet : FieldAccessService.searchSets(term)) {
                SetChoice choice = new SetChoice();
                choice.id = permissionSet.Id;
                choice.label = permissionSet.Label;
                choice.detail = permissionSet.Description;
                choices.add(choice);
            }
            return choices;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access permission set search');
        }
    }

    /**
     * One kind of record's changeable fields, by label, and the chosen sets' access to it.
     * @param objectName the object's API name
     * @param setIds the chosen permission sets
     */
    @AuraEnabled
    public static FieldList getFields(String objectName, List<String> setIds) {
        try {
            FieldAccessService.enforce();
            Schema.DescribeSObjectResult described = FieldAccessService.requireObject(objectName);
            Map<Id, PermissionSet> sets = FieldAccessService.requireSets(setIds);
            FieldList result = new FieldList();
            result.objectName = described.getName();
            result.objectLabel = described.getLabel();
            result.setCount = sets.size();
            Map<String, ObjectPermissions> objectNow = FieldAccessService.objectRows(
                sets.keySet(),
                new Set<String>{ result.objectName }
            );
            for (PermissionSet permissionSet : sets.values()) {
                FieldAccessService.Access access = FieldAccessService.accessOf(
                    objectNow.get(FieldAccessService.key(permissionSet.Id, result.objectName))
                );
                SetAccess row = new SetAccess();
                row.setId = permissionSet.Id;
                row.setLabel = permissionSet.Label;
                row.read = access.read;
                row.edit = access.edit;
                result.objectAccess.add(row);
            }
            Map<String, FieldPermissions> fieldNow = FieldAccessService.fieldRows(
                sets.keySet(),
                new Set<String>(),
                new Set<String>{ result.objectName }
            );
            Map<String, FieldOption> byName = new Map<String, FieldOption>();
            for (
                Schema.DescribeFieldResult field : FieldAccessService.permissionableFields(
                        described
                    )
                    .values()
            ) {
                FieldOption option = new FieldOption();
                option.name = field.getName();
                option.label = field.getLabel();
                option.readOnly = FieldAccessService.isReadOnly(field);
                byName.put(option.name.toLowerCase(), option);
            }
            for (FieldPermissions row : fieldNow.values()) {
                FieldOption option = byName.get(row.Field.substringAfter('.').toLowerCase());
                if (option != null && row.PermissionsRead) {
                    option.readCount++;
                    option.editCount += row.PermissionsEdit ? 1 : 0;
                }
            }
            Map<String, FieldOption> byLabel = new Map<String, FieldOption>();
            for (FieldOption option : byName.values()) {
                byLabel.put(option.label.toLowerCase() + '\u0000' + option.name, option);
            }
            List<String> keys = new List<String>(byLabel.keySet());
            keys.sort();
            for (String sortKey : keys) {
                result.fields.add(byLabel.get(sortKey));
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access fields');
        }
    }

    /**
     * Every permission row the change document would write (R-FA5). Writes nothing.
     * @param changeJson the change document (R-FA3)
     */
    @AuraEnabled
    public static Preview preview(String changeJson) {
        try {
            FieldAccessService.enforce();
            FieldAccessService.Plan plan = FieldAccessService.plan(changeJson);
            Preview result = new Preview();
            result.changed = plan.changes.size();
            result.unchanged = plan.unchanged;
            result.setCount = plan.setCount;
            result.tooMany = result.changed > FieldAccessService.rowLimit();
            for (FieldAccessService.Change change : plan.changes) {
                if (result.rows.size() == FieldAccessService.rowLimit()) {
                    break;
                }
                PreviewRow row = new PreviewRow();
                row.setId = change.setId;
                row.setLabel = change.setLabel;
                row.objectName = change.objectName;
                row.objectLabel = change.objectLabel;
                row.fieldName = change.fieldName;
                row.fieldLabel = change.fieldLabel;
                row.nowRead = change.now.read;
                row.nowEdit = change.now.edit;
                row.afterRead = change.after.read;
                row.afterEdit = change.after.edit;
                row.reason = change.reason;
                result.rows.add(row);
            }
            return result;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access preview');
        }
    }

    /**
     * Applies the change when it still writes the confirmed number of rows (R-FA5, R-FA6).
     * @param changeJson the change document the preview showed
     * @param confirmedCount the number of rows the preview showed
     */
    @AuraEnabled
    public static Outcome apply(String changeJson, Integer confirmedCount) {
        try {
            FieldAccessService.enforce();
            return outcomeOf(FieldAccessService.apply(changeJson, confirmedCount));
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access apply');
        }
    }

    /** Puts a change back (R-FA7). */
    @AuraEnabled
    public static Outcome undo(String jobId) {
        try {
            FieldAccessService.enforce();
            Id parsed;
            try {
                parsed = Id.valueOf(jobId);
            } catch (Exception notAnId) {
                throw new FieldAccessService.FieldAccessException(
                    System.Label.Core_FieldAccess_UndoNotFound
                );
            }
            return outcomeOf(FieldAccessService.undo(parsed));
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access undo');
        }
    }

    /** The newest field access changes, everyone's. */
    @AuraEnabled
    public static List<ChangeJob> listChanges() {
        try {
            FieldAccessService.enforce();
            List<ChangeJob> jobs = new List<ChangeJob>();
            for (
                Import_Batch__c job : DataJobs.read(
                    'Id, CreatedDate, Operation__c, Status__c, Committed_By__r.Name, Rows_Updated__c,' +
                    ' Rows_Rejected__c, Undo_Deadline__c',
                    FieldAccessService.OPERATION_ACCESS,
                    null,
                    CHANGES_LISTED,
                    true
                )
            ) {
                ChangeJob row = new ChangeJob();
                row.id = job.Id;
                row.createdAt = job.CreatedDate;
                row.byName = job.Committed_By__r?.Name;
                row.changed = job.Rows_Updated__c == null ? 0 : job.Rows_Updated__c.intValue();
                row.refused = job.Rows_Rejected__c == null ? 0 : job.Rows_Rejected__c.intValue();
                row.status = job.Status__c;
                row.undoDeadline = job.Undo_Deadline__c;
                row.canUndo = FieldAccessService.undoRefusal(job) == null;
                jobs.add(row);
            }
            return jobs;
        } catch (Exception caught) {
            throw asUserError(caught, 'Field access recent changes');
        }
    }

    private static Outcome outcomeOf(FieldAccessService.Result done) {
        Outcome result = new Outcome();
        result.changed = done.changed;
        result.refused = done.refused;
        result.kept = done.kept;
        for (String failure : done.failures) {
            if (result.failures.size() == FAILURES_SHOWN) {
                break;
            }
            result.failures.add(failure);
        }
        return result;
    }

    private static AuraHandledException asUserError(Exception caught, String context) {
        return UserErrors.wrap(
            caught,
            caught instanceof FieldAccessService.FieldAccessException,
            context,
            System.Label.Core_FieldAccess_UnexpectedError
        );
    }
}
