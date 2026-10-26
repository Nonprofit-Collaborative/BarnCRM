/**
 * What the merge and split screen calls.
 *
 * Who may run these: anyone who can edit both households. There is no separate custom
 * permission. Merging and splitting are data cleanup, which Maria and David both do, and a
 * person trusted to edit two household records is trusted to combine them. The check is a
 * record level one, so sharing is honored and not merely object access. Nothing here is
 * gated on Manage_BarnCRM_Settings, which is about configuring the org rather than about
 * fixing a duplicate. Nor is Delete on Account needed: HouseholdMergeService checks Edit on
 * Account and edit access to both records, then runs the platform merge in system mode
 * (ADR-0134).
 */
public with sharing class HouseholdMergeController {
    /**
     * One household as the picker offers it.
     */
    public class HouseholdOption {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Decimal memberCount;
        @AuraEnabled
        public String location;
    }

    /**
     * Households whose name contains what the person typed. Households only, never
     * organizations, so a merge cannot be aimed at one by accident.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdOption> searchHouseholds(String term, Id excludeId) {
        try {
            List<HouseholdOption> result = new List<HouseholdOption>();
            if (String.isBlank(term) || term.trim().length() < 2) {
                return result;
            }
            for (Account household : HouseholdSelector.searchHouseholds(term, excludeId, 20)) {
                HouseholdOption option = new HouseholdOption();
                option.id = household.Id;
                option.name = household.Name;
                option.memberCount = household.Member_Count__c;
                option.location = place(household);
                result.add(option);
            }
            return result;
        } catch (Exception e) {
            throw asUserError(e, excludeId);
        }
    }

    /**
     * Whether this person may change this household at all, so that the screen can show a
     * read only notice rather than buttons that would fail.
     */
    @AuraEnabled(cacheable=true)
    public static Boolean canEdit(Id householdId) {
        if (householdId == null) {
            return false;
        }
        return HouseholdSelector.getEditableIds(new Set<Id>{ householdId }).contains(householdId);
    }

    /** Set by a test to make the preview fail as an unexpected platform error would. */
    @TestVisible
    private static Exception previewFailureForTest;

    @AuraEnabled(cacheable=true)
    public static HouseholdMergeService.MergePreview preview(Id survivorId, Id victimId) {
        try {
            if (previewFailureForTest != null) {
                throw previewFailureForTest;
            }
            return HouseholdMergeService.preview(survivorId, victimId);
        } catch (Exception e) {
            throw asUserError(e, survivorId);
        }
    }

    /**
     * Combines the two households and answers with the survivor, so that the screen can
     * send the person there, and with whether the survivor's name is now held as a custom
     * one so the screen can tell the person.
     */
    @AuraEnabled
    public static HouseholdMergeService.MergeResult mergeHouseholds(
        Id survivorId,
        Id victimId,
        Map<String, String> fieldChoices
    ) {
        try {
            return HouseholdMergeService.mergeHouseholds(
                survivorId,
                victimId,
                new HouseholdMergeService.MergeChoices(fieldChoices)
            );
        } catch (Exception e) {
            throw asUserError(e, survivorId);
        }
    }

    /**
     * Moves people out of this household, into the one named or into a new one, and
     * answers with the household they now belong to.
     */
    @AuraEnabled
    public static Id splitHousehold(Id householdId, List<Id> personIds, Id targetHouseholdId) {
        try {
            Set<Id> people = new Set<Id>();
            if (personIds != null) {
                people.addAll(personIds);
            }
            return HouseholdMergeService.split(householdId, people, targetHouseholdId);
        } catch (Exception e) {
            throw asUserError(e, householdId);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static String place(Account household) {
        List<String> parts = new List<String>();
        if (String.isNotBlank(household.BillingCity)) {
            parts.add(household.BillingCity);
        }
        if (String.isNotBlank(household.BillingState)) {
            parts.add(household.BillingState);
        }
        return String.join(parts, ', ');
    }

    /** What the screen is told, logged under the merge's own context. */
    private static AuraHandledException asUserError(Exception e, Id recordId) {
        return HouseholdException.forScreen(e, Label.Core_HouseholdMerge_ErrorContext, recordId);
    }
}
