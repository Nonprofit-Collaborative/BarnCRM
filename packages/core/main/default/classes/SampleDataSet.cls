/**
 * The parsed and validated C-10 sample data payload: households, organizations, and the
 * flattened member list the contact stage inserts in chunks.
 *
 * parse() is the only way to build one, and it rejects a payload that is missing the
 * keys or names the loader needs with SampleDataException rather than letting a null
 * reach the insert and surface as "Attempt to de-reference a null object". The static
 * resource is generated, so this guards the hand-edited or truncated copy.
 *
 * householdIdsByKey is empty until the household stage has run; the contact stage
 * receives it from the queueable that carries it forward.
 */
public with sharing class SampleDataSet {
    /** One entry per household in the payload, in file order. */
    public final List<Map<String, Object>> households;

    /** One entry per organization in the payload, in file order. */
    public final List<Map<String, Object>> organizations;

    /**
     * Every household member in file order, each stamped with its household's key under
     * 'householdKey' so a chunk can resolve its Account without the household record.
     */
    public final List<Map<String, Object>> members;

    /**
     * The connections between people in different households (C-15), in file order. Empty
     * when the payload has none, which is what a payload written before connections shipped,
     * and every test payload that does not care about them, looks like.
     */
    public final List<Map<String, Object>> relationships;

    /** The affiliations joining people to organizations (C-16), in file order. */
    public final List<Map<String, Object>> affiliations;

    /** Household key to inserted Account Id, filled in by the household stage. */
    public Map<String, Id> householdIdsByKey = new Map<String, Id>();

    private SampleDataSet(
        List<Map<String, Object>> households,
        List<Map<String, Object>> organizations,
        List<Map<String, Object>> members,
        List<Map<String, Object>> relationships,
        List<Map<String, Object>> affiliations
    ) {
        this.households = households;
        this.organizations = organizations;
        this.members = members;
        this.relationships = relationships;
        this.affiliations = affiliations;
    }

    /**
     * Parses the sample data JSON body. Throws SampleDataException with
     * Core_SampleData_ErrorInvalidData when a required list or name is missing or null.
     */
    public static SampleDataSet parse(String jsonBody) {
        Map<String, Object> root = parseRoot(jsonBody);
        List<Map<String, Object>> households = asMapList(root.get('households'));
        List<Map<String, Object>> organizations = asMapList(root.get('organizations'));
        validateOrganizations(organizations);
        List<Map<String, Object>> relationships = optionalMapList(root.get('relationships'));
        List<Map<String, Object>> affiliations = optionalMapList(root.get('affiliations'));
        validateConnections(relationships, affiliations);
        return new SampleDataSet(
            households,
            organizations,
            flattenMembers(households),
            relationships,
            affiliations
        );
    }

    /** The JSON body as a map, or invalid data when it is blank, unparseable, or not an object. */
    private static Map<String, Object> parseRoot(String jsonBody) {
        if (String.isBlank(jsonBody)) {
            throw invalidData();
        }
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(jsonBody);
        } catch (Exception e) {
            throw invalidData();
        }
        if (!(parsed instanceof Map<String, Object>)) {
            throw invalidData();
        }
        return (Map<String, Object>) parsed;
    }

    /**
     * Validates every household and returns its members in file order, each stamped with
     * its household's key.
     */
    private static List<Map<String, Object>> flattenMembers(List<Map<String, Object>> households) {
        List<Map<String, Object>> members = new List<Map<String, Object>>();
        Set<String> seenKeys = new Set<String>();
        for (Map<String, Object> household : households) {
            String key = asString(household.get('key'));
            if (String.isBlank(key) || seenKeys.contains(key)) {
                throw invalidData();
            }
            seenKeys.add(key);
            if (
                household.get('customName') == true &&
                String.isBlank(asString(household.get('name')))
            ) {
                throw invalidData();
            }
            for (Map<String, Object> member : asMapList(household.get('members'))) {
                if (String.isBlank(asString(member.get('lastName')))) {
                    throw invalidData();
                }
                member.put('householdKey', key);
                members.add(member);
            }
        }
        return members;
    }

    /**
     * A relationship needs both people and a type, and an affiliation needs a person and an
     * organization: without them the loader would insert a row that points at nothing, which
     * the remove action would then have to delete and the panels would show as blank.
     */
    private static void validateConnections(
        List<Map<String, Object>> relationships,
        List<Map<String, Object>> affiliations
    ) {
        for (Map<String, Object> relationship : relationships) {
            if (
                String.isBlank(asString(relationship.get('person'))) ||
                String.isBlank(asString(relationship.get('relatedPerson'))) ||
                String.isBlank(asString(relationship.get('type')))
            ) {
                throw invalidData();
            }
        }
        for (Map<String, Object> affiliation : affiliations) {
            if (
                String.isBlank(asString(affiliation.get('person'))) ||
                String.isBlank(asString(affiliation.get('organization')))
            ) {
                throw invalidData();
            }
        }
    }

    /** Every organization needs a name; the loader has nothing else to insert one by. */
    private static void validateOrganizations(List<Map<String, Object>> organizations) {
        for (Map<String, Object> organization : organizations) {
            if (String.isBlank(asString(organization.get('name')))) {
                throw invalidData();
            }
        }
    }

    /** How many contact chunks the member list needs, at SampleDataLoader.CONTACT_CHUNK_SIZE each. */
    public Integer chunkCount() {
        if (members.isEmpty()) {
            return 0;
        }
        Integer size = SampleDataLoader.CONTACT_CHUNK_SIZE;
        return (members.size() + size - 1) / size;
    }

    /** The members belonging to one zero-based chunk; an empty list past the last chunk. */
    public List<Map<String, Object>> membersInChunk(Integer chunkIndex) {
        List<Map<String, Object>> chunk = new List<Map<String, Object>>();
        if (chunkIndex == null || chunkIndex < 0) {
            return chunk;
        }
        Integer size = SampleDataLoader.CONTACT_CHUNK_SIZE;
        Integer start = chunkIndex * size;
        Integer stop = Math.min(start + size, members.size());
        for (Integer i = start; i < stop; i++) {
            chunk.add(members[i]);
        }
        return chunk;
    }

    /**
     * A required JSON array as a list of maps. A missing, null, or wrongly typed value,
     * or an element that is not an object, is invalid data.
     */
    private static List<Map<String, Object>> asMapList(Object value) {
        if (!(value instanceof List<Object>)) {
            throw invalidData();
        }
        List<Map<String, Object>> result = new List<Map<String, Object>>();
        for (Object entry : (List<Object>) value) {
            if (!(entry instanceof Map<String, Object>)) {
                throw invalidData();
            }
            result.add((Map<String, Object>) entry);
        }
        return result;
    }

    /**
     * An optional JSON array as a list of maps: absent or null reads as none at all, so a
     * payload written before this list existed still loads, while a value of the wrong shape
     * is still invalid data rather than a silent skip.
     */
    private static List<Map<String, Object>> optionalMapList(Object value) {
        return value == null ? new List<Map<String, Object>>() : asMapList(value);
    }

    private static String asString(Object value) {
        return value instanceof String ? (String) value : null;
    }

    private static SampleDataException invalidData() {
        return new SampleDataException(BarnHelp.text('Core', 'Core_SampleData_ErrorInvalidData'));
    }
}
