/**
 * The donor segment starter templates (feature G-28, canonical model R-DS2).
 *
 * The templates are one JSON document in the documented format, so they read the same in any
 * edition of BarnCRM and can be copied out as they are. Names in it carry no namespace prefix;
 * building a template into a Find query document (R-SQ1) qualifies each custom name for the org,
 * adds `Email` after `Name` for people, and joins one more condition to the template's logic:
 * people who have died are left out, and an account is counted only when it is an organization
 * (households are accounts too).
 */
public with sharing class DonorSegmentTemplates {
    public static final String PEOPLE = 'Contact';
    public static final String ORGANIZATIONS = 'Account';
    public static final Integer ROW_LIMIT = 200;

    /** The R-DS2 document. The amounts and days are starting points, changed in Find. */
    @TestVisible
    private static final String TEMPLATES_JSON =
        '{"version":1,"templates":[' +
        '{"key":"lapsed","objects":["Contact","Account"],' +
        '"fields":["Name","Last_Gift_Date__c","Giving_Last_Year__c","Giving_This_Year__c","Total_Giving__c"],' +
        '"orderBy":{"field":"Giving_Last_Year__c","direction":"DESC"},' +
        '"filter":{"version":1,"logic":"1 AND (2 OR 3)","conditions":[' +
        '{"id":1,"field":"Giving_Last_Year__c","operator":"greater than","value":0},' +
        '{"id":2,"field":"Giving_This_Year__c","operator":"equals","value":0},' +
        '{"id":3,"field":"Giving_This_Year__c","operator":"is null"}]}},' +
        '{"key":"new","objects":["Contact","Account"],' +
        '"fields":["Name","First_Gift_Date__c","Gift_Count__c","Total_Giving__c"],' +
        '"orderBy":{"field":"First_Gift_Date__c","direction":"DESC"},' +
        '"filter":{"version":1,"conditions":[' +
        '{"id":1,"field":"First_Gift_Date__c","operator":"last n days","value":365}]}},' +
        '{"key":"upgraders","objects":["Contact","Account"],' +
        '"fields":["Name","Giving_Last_Year__c","Giving_This_Year__c","Change_From_Last_Year__c"],' +
        '"orderBy":{"field":"Change_From_Last_Year__c","direction":"DESC"},' +
        '"filter":{"version":1,"conditions":[' +
        '{"id":1,"field":"Giving_Last_Year__c","operator":"greater than","value":0},' +
        '{"id":2,"field":"Change_From_Last_Year__c","operator":"greater than","value":0}]}},' +
        '{"key":"levelMovers","objects":["Contact","Account"],' +
        '"fields":["Name","Previous_Donor_Level__r.Name","Donor_Level__r.Name","Donor_Level_Changed_Date__c"],' +
        '"orderBy":{"field":"Donor_Level_Changed_Date__c","direction":"DESC"},' +
        '"filter":{"version":1,"conditions":[' +
        '{"id":1,"field":"Donor_Level_Changed_Date__c","operator":"last n days","value":90},' +
        '{"id":2,"field":"Previous_Donor_Level__c","operator":"is not null"}]}},' +
        '{"key":"majorProspects","objects":["Contact","Account"],' +
        '"fields":["Name","Largest_Gift__c","Total_Giving__c","Last_Gift_Date__c"],' +
        '"orderBy":{"field":"Total_Giving__c","direction":"DESC"},' +
        '"filter":{"version":1,"logic":"(1 OR 2) AND 3","conditions":[' +
        '{"id":1,"field":"Largest_Gift__c","operator":"greater or equal","value":1000},' +
        '{"id":2,"field":"Total_Giving__c","operator":"greater or equal","value":5000},' +
        '{"id":3,"field":"Last_Gift_Date__c","operator":"last n days","value":730}]}}' +
        ']}';

    /** One template as the page offers it. */
    public class Template {
        @AuraEnabled
        public String key;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        @AuraEnabled
        public Boolean forPeople;
        @AuraEnabled
        public Boolean forOrganizations;
    }

    /** Every template, in the document's order, with its label and description. */
    public static List<Template> all() {
        List<Template> templates = new List<Template>();
        for (Object entry : (List<Object>) parsed().get('templates')) {
            Map<String, Object> raw = (Map<String, Object>) entry;
            List<Object> objects = (List<Object>) raw.get('objects');
            Template template = new Template();
            template.key = (String) raw.get('key');
            List<String> words = wordsFor(template.key);
            template.label = words[0];
            template.description = words[1];
            template.forPeople = objects.contains(PEOPLE);
            template.forOrganizations = objects.contains(ORGANIZATIONS);
            templates.add(template);
        }
        return templates;
    }

    /**
     * The Find query document (R-SQ1) for one template on people (`Contact`) or organizations
     * (`Account`), with every custom name qualified for this org. Refuses a template that does
     * not exist or does not apply to that object.
     */
    public static String document(String key, String objectName) {
        Map<String, Object> template = templateFor(key);
        if (
            template == null ||
            !((List<Object>) template.get('objects')).contains(objectName) ||
            (objectName != PEOPLE &&
            objectName != ORGANIZATIONS)
        ) {
            throw new DonorSegmentService.SegmentException(
                System.Label.Giving_Segments_ErrorTemplate
            );
        }
        Boolean people = objectName == PEOPLE;
        List<String> fields = new List<String>();
        for (Object field : (List<Object>) template.get('fields')) {
            fields.add(qualifyPath((String) field));
            if (people && (String) field == 'Name') {
                fields.add('Email');
            }
        }
        Map<String, Object> filter = (Map<String, Object>) template.get('filter');
        for (Object entry : (List<Object>) filter.get('conditions')) {
            Map<String, Object> condition = (Map<String, Object>) entry;
            condition.put('field', qualifyPath((String) condition.get('field')));
        }
        DonorSegmentService.andCondition(
            filter,
            people
                ? DonorSegmentService.condition(qualifyPath('Deceased__c'), 'equals', false)
                : DonorSegmentService.condition(qualifyPath('Is_Organization__c'), 'equals', true)
        );
        Map<String, Object> orderBy = (Map<String, Object>) template.get('orderBy');
        orderBy.put('field', qualifyPath((String) orderBy.get('field')));
        return JSON.serialize(
            new Map<String, Object>{
                'version' => 1,
                'object' => objectName,
                'fields' => fields,
                'filter' => filter,
                'orderBy' => new List<Object>{ orderBy },
                'limit' => ROW_LIMIT
            }
        );
    }

    /** A field path with each custom field or relationship name qualified for this org. */
    public static String qualifyPath(String path) {
        List<String> parts = new List<String>();
        for (String part : path.split('\\.')) {
            String lower = part.toLowerCase();
            parts.add(
                lower.endsWith('__c') || lower.endsWith('__r') ? NamespaceUtil.qualify(part) : part
            );
        }
        return String.join(parts, '.');
    }

    private static Map<String, Object> parsed() {
        // Read afresh on each call: document() changes the maps it is handed.
        return (Map<String, Object>) JSON.deserializeUntyped(TEMPLATES_JSON);
    }

    private static Map<String, Object> templateFor(String key) {
        for (Object entry : (List<Object>) parsed().get('templates')) {
            Map<String, Object> raw = (Map<String, Object>) entry;
            if ((String) raw.get('key') == key) {
                return raw;
            }
        }
        return null;
    }

    /** The label and description of a template, from custom labels so they can be translated. */
    private static List<String> wordsFor(String key) {
        switch on key {
            when 'lapsed' {
                return new List<String>{
                    System.Label.Giving_Segments_LapsedName,
                    System.Label.Giving_Segments_LapsedDescription
                };
            }
            when 'new' {
                return new List<String>{
                    System.Label.Giving_Segments_NewName,
                    System.Label.Giving_Segments_NewDescription
                };
            }
            when 'upgraders' {
                return new List<String>{
                    System.Label.Giving_Segments_UpgradersName,
                    System.Label.Giving_Segments_UpgradersDescription
                };
            }
            when 'levelMovers' {
                return new List<String>{
                    System.Label.Giving_Segments_LevelMoversName,
                    System.Label.Giving_Segments_LevelMoversDescription
                };
            }
            when else {
                return new List<String>{
                    System.Label.Giving_Segments_MajorProspectsName,
                    System.Label.Giving_Segments_MajorProspectsDescription
                };
            }
        }
    }
}
