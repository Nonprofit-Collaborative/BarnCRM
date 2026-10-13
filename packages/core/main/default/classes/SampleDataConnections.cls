/**
 * The last stage of Core's C-10 sample data load (SampleDataLoadStages): the connections
 * between the people the contact stages inserted, and the affiliations joining them to the
 * sample organizations.
 *
 * People are found by the key the generator gave them, read back from `Sample_Data_Key__c`,
 * rather than carried from one job to the next. Sixty relationships and eighty affiliations
 * fit in one job comfortably, so this stage has no chunking of its own.
 *
 * The reciprocal side of a relationship is written by the relationship automation, exactly
 * as it would be for a person entering one by hand. The mirrors it creates are then stamped
 * as sample data, inside a bypass of both relationship automations, so that the remove
 * action takes them away with the side the loader inserted.
 */
public with sharing class SampleDataConnections {
    /**
     * Inserts the payload's relationships and affiliations and returns how many rows the
     * loader itself created, mirrors included. Static and taking a parsed set, so a test
     * runs it without the batch.
     */
    public static Integer loadConnections(SampleDataSet data) {
        SampleDataSelector selector = new SampleDataSelector();
        Map<String, Id> peopleByKey = selector.getSampleContactIdsByKey();
        Map<String, Id> accountsByKey = selector.getSampleAccountIdsByKey();

        Integer created = insertRelationships(data, peopleByKey, selector);
        created += insertAffiliations(data, peopleByKey, accountsByKey);
        return created;
    }

    private static Integer insertRelationships(
        SampleDataSet data,
        Map<String, Id> peopleByKey,
        SampleDataSelector selector
    ) {
        List<Relationship__c> relationships = new List<Relationship__c>();
        for (Map<String, Object> row : data.relationships) {
            Id person = peopleByKey.get((String) row.get('person'));
            Id relatedPerson = peopleByKey.get((String) row.get('relatedPerson'));
            if (person == null || relatedPerson == null || person == relatedPerson) {
                continue;
            }
            relationships.add(
                new Relationship__c(
                    Sample_Data__c = true,
                    Contact__c = person,
                    Related_Contact__c = relatedPerson,
                    Type__c = (String) row.get('type'),
                    Status__c = (String) row.get('status'),
                    Start_Date__c = dateOf(row.get('startDate')),
                    End_Date__c = dateOf(row.get('endDate')),
                    Description__c = (String) row.get('description')
                )
            );
        }
        if (relationships.isEmpty()) {
            return 0;
        }
        Database.insert(relationships, AccessLevel.USER_MODE);
        return relationships.size() + stampMirrors(relationships, selector);
    }

    /**
     * Marks the other side of each relationship as sample data too. The automation built it,
     * so it carries no flag of its own, and without this the remove action would leave half
     * of every connection behind.
     */
    private static Integer stampMirrors(
        List<Relationship__c> inserted,
        SampleDataSelector selector
    ) {
        List<Id> mirrorIds = selector.getMirrorRelationshipIds(
            new Map<Id, Relationship__c>(inserted).keySet()
        );
        if (mirrorIds.isEmpty()) {
            return 0;
        }
        List<Relationship__c> mirrors = new List<Relationship__c>();
        for (Id mirrorId : mirrorIds) {
            mirrors.add(new Relationship__c(Id = mirrorId, Sample_Data__c = true));
        }
        // The mirror is already complete and already paired: running the maintenance and
        // validation automations over it again would only ask for the other side of the
        // other side, which is the record this update is stamping.
        AutomationControl.bypass(RelationshipService.AUTOMATION_NAME);
        AutomationControl.bypass(RelationshipService.VALIDATION_AUTOMATION_NAME);
        try {
            Database.update(mirrors, AccessLevel.USER_MODE);
        } finally {
            AutomationControl.clearBypass(RelationshipService.AUTOMATION_NAME);
            AutomationControl.clearBypass(RelationshipService.VALIDATION_AUTOMATION_NAME);
        }
        return mirrors.size();
    }

    private static Integer insertAffiliations(
        SampleDataSet data,
        Map<String, Id> peopleByKey,
        Map<String, Id> accountsByKey
    ) {
        List<Affiliation__c> affiliations = new List<Affiliation__c>();
        for (Map<String, Object> row : data.affiliations) {
            Id person = peopleByKey.get((String) row.get('person'));
            Id organization = accountsByKey.get((String) row.get('organization'));
            if (person == null || organization == null) {
                continue;
            }
            affiliations.add(
                new Affiliation__c(
                    Sample_Data__c = true,
                    Contact__c = person,
                    Organization__c = organization,
                    Role__c = (String) row.get('role'),
                    Status__c = (String) row.get('status'),
                    Is_Primary__c = row.get('isPrimary') == true,
                    Start_Date__c = dateOf(row.get('startDate')),
                    End_Date__c = dateOf(row.get('endDate'))
                )
            );
        }
        if (affiliations.isEmpty()) {
            return 0;
        }
        Database.insert(affiliations, AccessLevel.USER_MODE);
        return affiliations.size();
    }

    private static Date dateOf(Object value) {
        return value == null ? null : Date.valueOf((String) value);
    }
}
