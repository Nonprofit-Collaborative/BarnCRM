/**
 * Starter templates for common nonprofit totals (Rollup Builder ease of use U2, ADR-0136). A
 * template is a list of rollups an administrator may add. Nothing is ever added by default: she
 * opens Starter Templates, ticks the rollups she wants (none are ticked), and confirms. Each
 * chosen rollup is saved switched off, through the Builder's own checks (`checkedRecord`: R-R10,
 * R-R8), so she switches each on once its field shows what she expects.
 *
 * The Nonprofit Starter adds what Giving does not ship: a person's average gift, first and last
 * gift amounts, smallest gift and number of gifts this fiscal year, and an appeal's average gift
 * and number of donors, all from received gifts (the shipped giving totals' conditions). The
 * fields they fill are not shipped, so an item whose field is missing cannot be added yet; Open
 * in Builder opens it prefilled, where Create a Field (U8) writes the field.
 *
 * Objects are named as text and resolved through describe, so an org without Giving sees the
 * template as not available rather than failing.
 */
public with sharing class RollupTemplates {
    @TestVisible
    private static final String NONPROFIT_STARTER = 'nonprofitStarter';
    private static final String GIFT = 'Gift__c';
    private static final String APPEAL = 'Appeal__c';
    private static final String PERSON = 'Contact';
    /** Received gifts with an amount, as the shipped giving totals count them. */
    private static final String RECEIVED =
        '{"version":1,"conditions":[{"id":1,"field":"Status__c","operator":"in",' +
        '"value":["Received","Refunded","Written off"]},' +
        '{"id":2,"field":"Amount__c","operator":"greater than","value":0}]}';

    /** One template, as the Starter Templates panel lists it. */
    public class Template {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String description { get; set; }
        @AuraEnabled
        public List<Item> items { get; set; }
    }

    /** One rollup a template offers. */
    public class Item {
        @AuraEnabled
        public String key { get; set; }
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public String sentence { get; set; }
        @AuraEnabled
        public String status { get; set; }
        /** True when it can be added now: its objects and field exist and nothing fills it. */
        @AuraEnabled
        public Boolean available { get; set; }
        /** True when only its field is missing: Open in Builder writes it. */
        @AuraEnabled
        public Boolean needsField { get; set; }
        /** True when its objects exist, so the Builder can open it prefilled. */
        @AuraEnabled
        public Boolean canOpen { get; set; }
        @AuraEnabled
        public String fieldLabel { get; set; }
        /** The Create a Field type (`RollupFieldGenerator.KINDS`). */
        @AuraEnabled
        public String fieldKind { get; set; }
        @AuraEnabled
        public RollupBuilderController.Draft draft { get; set; }
    }

    /** What adding one chosen rollup did. */
    public class Outcome {
        @AuraEnabled
        public String name { get; set; }
        @AuraEnabled
        public Boolean added { get; set; }
        @AuraEnabled
        public String message { get; set; }
    }

    /** A rollup a template offers, before it is checked against this org. */
    @TestVisible
    private class Spec {
        public String key;
        public String name;
        public String fieldKind;
        public RollupBuilderController.Draft draft;
    }

    /** Every template, each rollup with whether it can be added in this org and why not. */
    @AuraEnabled
    public static List<Template> getTemplates() {
        try {
            requirePermission();
            Map<String, String> filledBy = filledBy();
            Template starter = new Template();
            starter.key = NONPROFIT_STARTER;
            starter.name = Label.Core_RollupEase_TplStarter;
            starter.description = Label.Core_RollupEase_TplStarterHelp;
            starter.items = new List<Item>();
            for (Spec spec : nonprofitStarter()) {
                starter.items.add(itemOf(spec, filledBy));
            }
            return new List<Template>{ starter };
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    /**
     * Adds the chosen rollups of one template, each switched off, through the Builder's checks.
     * A rollup that cannot be added is reported with the reason and the others are still added.
     *
     * @param templateKey the template
     * @param itemKeys the rollups the administrator ticked; none is added unless ticked
     */
    @AuraEnabled
    public static List<Outcome> addRollups(String templateKey, List<String> itemKeys) {
        try {
            requirePermission();
            List<Outcome> outcomes = new List<Outcome>();
            if (templateKey != NONPROFIT_STARTER || itemKeys == null || itemKeys.isEmpty()) {
                return outcomes;
            }
            Set<String> chosen = new Set<String>(itemKeys);
            Map<String, String> filledBy = filledBy();
            for (Spec spec : nonprofitStarter()) {
                if (chosen.contains(spec.key)) {
                    outcomes.add(add(spec, filledBy));
                }
            }
            return outcomes;
        } catch (Exception caught) {
            throw asUserError(caught);
        }
    }

    @TestVisible
    private static Outcome add(Spec spec, Map<String, String> filledBy) {
        Outcome outcome = new Outcome();
        outcome.name = spec.name;
        outcome.added = false;
        Item item = itemOf(spec, filledBy);
        if (!item.available) {
            outcome.message = item.status;
            return outcome;
        }
        try {
            Rollup_Definition__c definition = RollupBuilderController.checkedRecord(spec.draft);
            RollupWriter.saveAsUser(definition);
            outcome.added = true;
            outcome.message = Label.Core_RollupEase_TplAdded;
        } catch (RollupService.RollupServiceException refused) {
            outcome.message = refused.getMessage();
        } catch (DmlException refused) {
            outcome.message = refused.getDmlMessage(0);
        }
        return outcome;
    }

    /** Whether one rollup can be added here, and the words that say so. */
    private static Item itemOf(Spec spec, Map<String, String> filledBy) {
        RollupBuilderController.Draft draft = spec.draft;
        Item item = new Item();
        item.key = spec.key;
        item.name = spec.name;
        item.fieldLabel = spec.name;
        item.fieldKind = spec.fieldKind;
        item.draft = draft;
        item.available = false;
        item.needsField = false;
        Schema.SObjectType targetType = SettingsService.typeByName(draft.targetObject);
        Schema.SObjectType sourceType = SettingsService.typeByName(draft.sourceObject);
        item.canOpen = targetType != null && sourceType != null;
        item.sentence = RollupSentence.of(recordOf(draft));
        if (!item.canOpen) {
            item.status = String.format(
                Label.Core_RollupEase_TplNeedsObject,
                new List<String>{ targetType == null ? draft.targetObject : draft.sourceObject }
            );
            return item;
        }
        String key = (draft.targetObject + '.' + draft.targetField).toLowerCase();
        if (filledBy.containsKey(key)) {
            item.status = String.format(
                Label.Core_RollupEase_TplFilled,
                new List<String>{ filledBy.get(key) }
            );
            return item;
        }
        Boolean fieldExists = targetType.getDescribe(SObjectDescribeOptions.DEFERRED)
            .fields.getMap()
            .containsKey(draft.targetField.toLowerCase());
        if (!fieldExists) {
            item.needsField = true;
            item.status = String.format(
                Label.Core_RollupEase_TplNeedsField,
                new List<String>{
                    spec.name,
                    targetType.getDescribe(SObjectDescribeOptions.DEFERRED).getLabel()
                }
            );
            return item;
        }
        item.available = true;
        item.status = Label.Core_RollupEase_TplReady;
        return item;
    }

    /** The rollup a draft describes, enough for its sentence. */
    private static Rollup_Definition__c recordOf(RollupBuilderController.Draft draft) {
        return new Rollup_Definition__c(
            Name = draft.name,
            Target_Object__c = draft.targetObject,
            Target_Field__c = draft.targetField,
            Source_Object__c = draft.sourceObject,
            Relationship_Path__c = draft.relationshipPath,
            Aggregate__c = draft.aggregate,
            Source_Field__c = draft.sourceField,
            Order_By_Field__c = draft.orderByField,
            Filter_JSON__c = draft.filterJson,
            Fiscal_Year_Aware__c = draft.fiscalYearAware == true,
            Fiscal_Year_Offset__c = draft.fiscalYearOffset,
            Fiscal_Date_Field__c = draft.fiscalDateField
        );
    }

    /** Every field some rollup already fills, by `object.field` in lower case, with its name. */
    @TestVisible
    private static Map<String, String> filledBy() {
        Map<String, String> filled = new Map<String, String>();
        for (Rollup_Definition__c definition : RollupSelector.selectAllAsUser()) {
            if (definition.Target_Object__c != null && definition.Target_Field__c != null) {
                filled.put(
                    (definition.Target_Object__c + '.' + definition.Target_Field__c).toLowerCase(),
                    definition.Name
                );
            }
        }
        return filled;
    }

    /** The Nonprofit Starter: what Giving does not ship, from received gifts. */
    @TestVisible
    private static List<Spec> nonprofitStarter() {
        List<Spec> specs = new List<Spec>();
        specs.add(
            giftSpec('averageGift', Label.Core_RollupEase_TplAverageGift, 'CURRENCY', PERSON, 'AVG')
        );
        Spec firstAmount = giftSpec(
            'firstGiftAmount',
            Label.Core_RollupEase_TplFirstGiftAmount,
            'CURRENCY',
            PERSON,
            'FIRST'
        );
        firstAmount.draft.orderByField = 'Gift_Date__c';
        specs.add(firstAmount);
        Spec lastAmount = giftSpec(
            'lastGiftAmount',
            Label.Core_RollupEase_TplLastGiftAmount,
            'CURRENCY',
            PERSON,
            'LAST'
        );
        lastAmount.draft.orderByField = 'Gift_Date__c';
        specs.add(lastAmount);
        specs.add(
            giftSpec(
                'smallestGift',
                Label.Core_RollupEase_TplSmallestGift,
                'CURRENCY',
                PERSON,
                'MIN'
            )
        );
        Spec thisYear = giftSpec(
            'giftsThisYear',
            Label.Core_RollupEase_TplGiftsThisYear,
            'NUMBER',
            PERSON,
            'COUNT'
        );
        thisYear.draft.sourceField = null;
        thisYear.draft.fiscalYearAware = true;
        thisYear.draft.fiscalYearOffset = 0;
        thisYear.draft.fiscalDateField = 'Gift_Date__c';
        specs.add(thisYear);
        specs.add(
            giftSpec(
                'appealAverageGift',
                Label.Core_RollupEase_TplAppealAverageGift,
                'CURRENCY',
                APPEAL,
                'AVG'
            )
        );
        Spec donors = giftSpec(
            'appealDonors',
            Label.Core_RollupEase_TplAppealDonors,
            'NUMBER',
            APPEAL,
            'COUNT_DISTINCT'
        );
        donors.draft.sourceField = 'Donor_Contact__c';
        specs.add(donors);
        return specs;
    }

    /** A rollup of received gifts' amounts into a new field of a person or an appeal. */
    @TestVisible
    private static Spec giftSpec(
        String key,
        String name,
        String fieldKind,
        String targetObject,
        String aggregate
    ) {
        RollupBuilderController.Draft draft = new RollupBuilderController.Draft();
        draft.name = name;
        draft.targetObject = targetObject;
        draft.targetField = RollupFieldGenerator.nameFor(name) + '__c';
        draft.sourceObject = GIFT;
        draft.relationshipPath = targetObject == APPEAL ? 'Appeal__c' : 'Donor_Contact__c';
        draft.aggregate = aggregate;
        draft.sourceField = 'Amount__c';
        draft.filterJson = RECEIVED;
        draft.fiscalYearAware = false;
        draft.includeDeleted = false;
        draft.mode = RollupService.MODE_BOTH;
        draft.active = false;
        Spec built = new Spec();
        built.key = key;
        built.name = name;
        built.fieldKind = fieldKind;
        built.draft = draft;
        return built;
    }

    private static void requirePermission() {
        if (!BarnCRMPermissions.canManageSettings()) {
            throw new RollupService.RollupServiceException(Label.Core_Rollups_ErrorNoPermission);
        }
    }

    private static AuraHandledException asUserError(Exception caught) {
        return UserErrors.wrap(
            caught,
            caught instanceof RollupService.RollupServiceException,
            'RollupTemplates',
            Label.Core_Rollups_UnexpectedError
        );
    }
}
