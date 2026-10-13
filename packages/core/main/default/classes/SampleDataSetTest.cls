/**
 * Tests SampleDataSet.parse: the shape it accepts, the chunk arithmetic the contact
 * stage depends on, and every malformed payload that must raise SampleDataException with
 * the Core_SampleData_ErrorInvalidData label rather than a null dereference deeper in.
 */
// runs-as: deploying user (pure logic: parses a sample data payload, no DML or SOQL)
@IsTest
private class SampleDataSetTest {
    private static Map<String, Object> validMember() {
        Map<String, Object> member = new Map<String, Object>();
        member.put('firstName', 'Maria');
        member.put('lastName', 'Garcia');
        member.put('householdRole', 'Head');
        return member;
    }

    private static Map<String, Object> validHousehold() {
        Map<String, Object> household = new Map<String, Object>();
        household.put('key', 'H001');
        household.put('customName', false);
        household.put('members', new List<Object>{ validMember() });
        return household;
    }

    private static Map<String, Object> validOrganization() {
        Map<String, Object> organization = new Map<String, Object>();
        organization.put('key', 'O001');
        organization.put('name', 'Cedar Valley Community Foundation');
        return organization;
    }

    private static Map<String, Object> validRoot() {
        Map<String, Object> root = new Map<String, Object>();
        root.put('households', new List<Object>{ validHousehold() });
        root.put('organizations', new List<Object>{ validOrganization() });
        return root;
    }

    /**
     * Asserts that parsing the given payload throws SampleDataException with the packaged
     * label, and returns whether it did, so each calling test method also carries its own
     * assertion on the outcome rather than trusting a shared helper silently.
     */
    private static Boolean assertRejects(Object root, String because) {
        Boolean threw = false;
        try {
            SampleDataSet.parse(root instanceof String ? (String) root : JSON.serialize(root));
        } catch (SampleDataException e) {
            threw = true;
            System.assertEquals(
                Label.Core_SampleData_ErrorInvalidData,
                e.getMessage(),
                'invalid data should use the packaged label: ' + because
            );
        }
        System.assertEquals(true, threw, because);
        return threw;
    }

    @IsTest
    static void testConnectionsAreOptional() {
        SampleDataSet data = SampleDataSet.parse(JSON.serialize(validRoot()));

        System.assertEquals(
            0,
            data.relationships.size(),
            'a payload with no connections parses as none rather than failing'
        );
        System.assertEquals(0, data.affiliations.size(), 'the same for affiliations');
    }

    @IsTest
    static void testParsesConnectionsWhenTheyArePresent() {
        Map<String, Object> relationship = new Map<String, Object>();
        relationship.put('person', 'H001-1');
        relationship.put('relatedPerson', 'H002-1');
        relationship.put('type', 'Sibling');
        Map<String, Object> affiliation = new Map<String, Object>();
        affiliation.put('person', 'H001-1');
        affiliation.put('organization', 'O001');
        Map<String, Object> root = validRoot();
        root.put('relationships', new List<Object>{ relationship });
        root.put('affiliations', new List<Object>{ affiliation });

        SampleDataSet data = SampleDataSet.parse(JSON.serialize(root));

        System.assertEquals(1, data.relationships.size(), 'the one connection is read');
        System.assertEquals(
            'Sibling',
            (String) data.relationships[0].get('type'),
            'the connection keeps the type the file gave it'
        );
        System.assertEquals(
            'O001',
            (String) data.affiliations[0].get('organization'),
            'the affiliation keeps the organization key the file gave it'
        );
    }

    @IsTest
    static void testRejectsAConnectionMissingItsOtherSide() {
        Map<String, Object> relationship = new Map<String, Object>();
        relationship.put('person', 'H001-1');
        relationship.put('type', 'Sibling');
        Map<String, Object> root = validRoot();
        root.put('relationships', new List<Object>{ relationship });

        Assert.isTrue(
            assertRejects(root, 'a connection with only one person named is invalid data'),
            'the one-sided connection must be rejected'
        );
    }

    @IsTest
    static void testRejectsAnAffiliationMissingItsOrganization() {
        Map<String, Object> affiliation = new Map<String, Object>();
        affiliation.put('person', 'H001-1');
        Map<String, Object> root = validRoot();
        root.put('affiliations', new List<Object>{ affiliation });

        Assert.isTrue(
            assertRejects(root, 'an affiliation with no organization named is invalid data'),
            'the affiliation missing its organization must be rejected'
        );
    }

    @IsTest
    static void testParsesAValidPayload() {
        SampleDataSet data = SampleDataSet.parse(JSON.serialize(validRoot()));
        System.assertEquals(1, data.households.size(), 'one household');
        System.assertEquals(1, data.organizations.size(), 'one organization');
        System.assertEquals(1, data.members.size(), 'one flattened member');
        System.assertEquals(
            'H001',
            (String) data.members[0].get('householdKey'),
            'each member should carry its household key'
        );
    }

    @IsTest
    static void testChunkArithmetic() {
        Map<String, Object> household = validHousehold();
        List<Object> members = new List<Object>();
        for (Integer i = 0; i < 250; i++) {
            members.add(validMember());
        }
        household.put('members', members);
        Map<String, Object> root = validRoot();
        root.put('households', new List<Object>{ household });

        SampleDataSet data = SampleDataSet.parse(JSON.serialize(root));
        System.assertEquals(250, data.members.size());
        System.assertEquals(3, data.chunkCount(), '250 members chunk at 100 into three jobs');
        System.assertEquals(100, data.membersInChunk(0).size());
        System.assertEquals(100, data.membersInChunk(1).size());
        System.assertEquals(
            50,
            data.membersInChunk(2).size(),
            'the last chunk holds the remainder'
        );
        System.assertEquals(0, data.membersInChunk(3).size(), 'nothing past the last chunk');
        System.assertEquals(0, data.membersInChunk(-1).size(), 'a negative chunk holds nothing');
    }

    @IsTest
    static void testEmptyPayloadNeedsNoChunks() {
        Map<String, Object> root = new Map<String, Object>();
        root.put('households', new List<Object>());
        root.put('organizations', new List<Object>());
        SampleDataSet data = SampleDataSet.parse(JSON.serialize(root));
        System.assertEquals(0, data.chunkCount(), 'no members means no contact chunks');
    }

    @IsTest
    static void testRejectsBlankAndUnparseableBodies() {
        Integer rejectedCount = 0;
        rejectedCount += assertRejects('', 'a blank body is not sample data') ? 1 : 0;
        rejectedCount += assertRejects('not json at all', 'an unparseable body is not sample data')
            ? 1
            : 0;
        rejectedCount += assertRejects('[1,2,3]', 'a JSON array is not the expected object')
            ? 1
            : 0;
        Assert.areEqual(3, rejectedCount, 'all three malformed bodies must be rejected');
    }

    @IsTest
    static void testRejectsMissingOrNullHouseholds() {
        Map<String, Object> missing = validRoot();
        missing.remove('households');
        Boolean missingRejected = assertRejects(
            missing,
            'a payload with no households key is invalid'
        );

        Map<String, Object> nulled = validRoot();
        nulled.put('households', null);
        Boolean nulledRejected = assertRejects(nulled, 'a payload with null households is invalid');

        Assert.isTrue(
            missingRejected && nulledRejected,
            'both a missing and a null households key must be rejected'
        );
    }

    @IsTest
    static void testRejectsMissingOrNullOrganizations() {
        Map<String, Object> missing = validRoot();
        missing.remove('organizations');
        Boolean missingRejected = assertRejects(
            missing,
            'a payload with no organizations key is invalid'
        );

        Map<String, Object> nulled = validRoot();
        nulled.put('organizations', null);
        Boolean nulledRejected = assertRejects(
            nulled,
            'a payload with null organizations is invalid'
        );

        Assert.isTrue(
            missingRejected && nulledRejected,
            'both a missing and a null organizations key must be rejected'
        );
    }

    @IsTest
    static void testRejectsMissingOrNullMembers() {
        Map<String, Object> household = validHousehold();
        household.remove('members');
        Map<String, Object> missing = validRoot();
        missing.put('households', new List<Object>{ household });
        Boolean missingRejected = assertRejects(
            missing,
            'a household with no members key is invalid'
        );

        Map<String, Object> nullMembers = validHousehold();
        nullMembers.put('members', null);
        Map<String, Object> nulled = validRoot();
        nulled.put('households', new List<Object>{ nullMembers });
        Boolean nulledRejected = assertRejects(nulled, 'a household with null members is invalid');

        Assert.isTrue(
            missingRejected && nulledRejected,
            'both a missing and a null members key must be rejected'
        );
    }

    @IsTest
    static void testRejectsMissingRequiredNames() {
        Map<String, Object> noLastName = validHousehold();
        noLastName.put(
            'members',
            new List<Object>{ new Map<String, Object>{ 'firstName' => 'Maria' } }
        );
        Map<String, Object> memberRoot = validRoot();
        memberRoot.put('households', new List<Object>{ noLastName });
        Boolean noLastNameRejected = assertRejects(
            memberRoot,
            'a member with no last name is invalid'
        );

        Map<String, Object> noOrgName = validOrganization();
        noOrgName.put('name', null);
        Map<String, Object> orgRoot = validRoot();
        orgRoot.put('organizations', new List<Object>{ noOrgName });
        Boolean noOrgNameRejected = assertRejects(
            orgRoot,
            'an organization with no name is invalid'
        );

        Map<String, Object> customNoName = validHousehold();
        customNoName.put('customName', true);
        customNoName.put('name', null);
        Map<String, Object> customRoot = validRoot();
        customRoot.put('households', new List<Object>{ customNoName });
        Boolean customNoNameRejected = assertRejects(
            customRoot,
            'a custom-named household with no name is invalid'
        );

        Assert.isTrue(
            noLastNameRejected && noOrgNameRejected && customNoNameRejected,
            'every missing-name case above must be rejected'
        );
    }

    @IsTest
    static void testRejectsMissingAndDuplicateHouseholdKeys() {
        Map<String, Object> noKey = validHousehold();
        noKey.put('key', null);
        Map<String, Object> keyless = validRoot();
        keyless.put('households', new List<Object>{ noKey });
        Boolean keylessRejected = assertRejects(
            keyless,
            'a household with no key cannot be matched to its members'
        );

        Map<String, Object> duplicates = validRoot();
        duplicates.put('households', new List<Object>{ validHousehold(), validHousehold() });
        Boolean duplicatesRejected = assertRejects(
            duplicates,
            'two households cannot share one key'
        );

        Assert.isTrue(
            keylessRejected && duplicatesRejected,
            'both the keyless and the duplicate-key households must be rejected'
        );
    }
}
