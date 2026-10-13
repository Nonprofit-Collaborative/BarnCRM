/**
 * What the Donor Levels page in the settings console calls (feature G-14).
 *
 * The page is deliberately thin. The rungs themselves are ordinary records, created and edited
 * through the platform's own record pages, so this class does not carry a second create and edit
 * surface for them (ADR-0028). What it does carry is the three things a list of records cannot
 * answer: is the feature on and what is it measuring, how many donors are actually on each rung,
 * and when was everybody last placed.
 */
public with sharing class DonorLevelController {
    private static final String CONTEXT = 'Donor Levels page';

    public class LadderModel {
        @AuraEnabled
        public Boolean enabled;
        @AuraEnabled
        public Boolean canRecalculate;
        @AuraEnabled
        public String sourceFieldLabel;
        @AuraEnabled
        public Datetime lastRecalculated;
        @AuraEnabled
        public List<RungModel> rungs;
    }

    public class RungModel {
        @AuraEnabled
        public Id recordId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Decimal minimumAmount;
        @AuraEnabled
        public Decimal maximumAmount;
        @AuraEnabled
        public Boolean active;
        @AuraEnabled
        public Integer donorCount;
    }

    /** The ladder as the page shows it: every rung, lowest first, with its donor count. */
    @AuraEnabled(cacheable=true)
    public static LadderModel getLadder() {
        try {
            LadderModel model = new LadderModel();
            model.enabled = DonorLevelService.isEnabled();
            model.canRecalculate = BarnCRMPermissions.canManageSettings();
            model.sourceFieldLabel = sourceLabel();
            model.lastRecalculated = Giving_Settings__c.getOrgDefaults()
                .Donor_Levels_Last_Recalculated__c;
            Map<Id, Integer> counts = DonorLevelSelector.countDonorsByLevel();
            model.rungs = new List<RungModel>();
            for (Donor_Level__c level : DonorLevelSelector.selectAllLevels()) {
                RungModel rung = new RungModel();
                rung.recordId = level.Id;
                rung.name = level.Name;
                rung.description = level.Description__c;
                rung.minimumAmount = level.Minimum_Amount__c;
                rung.maximumAmount = level.Maximum_Amount__c;
                rung.active = level.Active__c;
                rung.donorCount = counts.containsKey(level.Id) ? counts.get(level.Id) : 0;
                model.rungs.add(rung);
            }
            return model;
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * Places every donor on the ladder now, which is what an administrator needs after editing it
     * (R-DL8). Refused for a user who may not change settings, because a recalculation writes to
     * every donor record in the org.
     */
    @AuraEnabled
    public static Id recalculate() {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw refuse(Label.Giving_DonorLevels_NotPermitted);
        }
        if (!DonorLevelService.isEnabled()) {
            throw refuse(Label.Giving_DonorLevels_TurnOnFirst);
        }
        try {
            return Database.executeBatch(new DonorLevelBatch(), DonorLevelSchedulable.CHUNK_SIZE);
        } catch (Exception failure) {
            throw report(failure);
        }
    }

    /**
     * The chosen total in words. The console stores the field name, and Maria should read
     * "Total giving", so the label comes from the field itself rather than from a second list.
     */
    private static String sourceLabel() {
        String source = DonorLevelService.sourceField();
        Map<String, Schema.SObjectField> fields = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .fields.getMap();
        for (Schema.SObjectField token : fields.values()) {
            Schema.DescribeFieldResult field = token.getDescribe();
            if (field.getLocalName() == source) {
                return field.getLabel();
            }
        }
        return source;
    }

    private static AuraHandledException refuse(String message) {
        AuraHandledException refusal = new AuraHandledException(message);
        refusal.setMessage(message);
        return refusal;
    }

    private static AuraHandledException report(Exception failure) {
        ErrorLogger.log(failure, CONTEXT);
        return refuse(Label.Giving_DonorLevels_ActionFailed);
    }
}
