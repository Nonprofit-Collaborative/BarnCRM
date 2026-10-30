/**
 * Core's C-10 sample data load, as the stages SampleDataStageBatch runs one per transaction:
 *
 * - stage 0 inserts every household and organization Account with Sample_Data__c true;
 * - stages 1 to chunkCount insert up to SampleDataLoader.CONTACT_CHUNK_SIZE contacts each and
 *   join each chunk to its households through HouseholdService, so that inserting several
 *   hundred contacts (each running through the household naming and greeting triggers) never
 *   risks the CPU limit of one transaction;
 * - the last stage loads the connections and affiliations (SampleDataConnections).
 *
 * finish() then starts the first module sample set, because by then every household, person
 * and organization a module's records point at exists.
 *
 * Only the household key to Id map is kept between stages. The payload itself is re-read from
 * the static resource in each stage, so a several hundred kilobyte JSON body is never
 * serialized into the batch state. The stage bodies are static and take a parsed
 * SampleDataSet, so tests call them directly and assert chunk boundaries.
 */
public with sharing class SampleDataLoadStages implements SampleDataStages {
    private Map<String, Id> householdIdsByKey = new Map<String, Id>();

    public String name() {
        return 'SampleDataLoadStages';
    }

    /** The accounts stage, one stage per contact chunk, and the connections stage. */
    public Integer stageCount() {
        return SampleDataSet.parse(SampleDataLoader.getSampleDataJson()).chunkCount() + 2;
    }

    public void runStage(Integer stage) {
        SampleDataSet data = SampleDataSet.parse(SampleDataLoader.getSampleDataJson());
        if (stage == 0) {
            householdIdsByKey = loadHouseholdsAndOrganizations(data);
        } else if (stage <= data.chunkCount()) {
            data.householdIdsByKey = householdIdsByKey;
            loadContactChunk(data, stage - 1);
        } else {
            SampleDataConnections.loadConnections(data);
        }
    }

    /** Every person now exists, so the module sample sets that point at them can load. */
    public void finish() {
        SampleDataModules.startFirst();
    }

    /**
     * Stage one: inserts the household and organization Accounts and records the
     * household key to Id map on the data set for the contact stage. Returns that map.
     */
    public static Map<String, Id> loadHouseholdsAndOrganizations(SampleDataSet data) {
        Id householdRecordTypeId = recordTypeId(Account.SObjectType, 'Household');
        // Organizations use the record type the org chose (ADR-0141): null means none.
        Id organizationRecordTypeId = AccountKinds.organizationRecordTypeId();

        List<Account> householdAccounts = new List<Account>();
        List<String> householdKeys = new List<String>();
        for (Map<String, Object> household : data.households) {
            householdAccounts.add(buildHouseholdAccount(household, householdRecordTypeId));
            householdKeys.add((String) household.get('key'));
        }

        List<Account> organizationAccounts = new List<Account>();
        for (Map<String, Object> organization : data.organizations) {
            organizationAccounts.add(
                buildOrganizationAccount(organization, organizationRecordTypeId)
            );
        }

        // No user is given the Household record type (ADR-0141), so households are
        // created by HouseholdWriter, which checks the loading user's access first.
        HouseholdWriter.createHouseholdsForUser(householdAccounts, null, sampleSaveOptions());
        if (!organizationAccounts.isEmpty()) {
            Database.insert(organizationAccounts, sampleSaveOptions(), AccessLevel.USER_MODE);
        }

        Map<String, Id> keysToIds = new Map<String, Id>();
        for (Integer i = 0; i < householdAccounts.size(); i++) {
            keysToIds.put(householdKeys[i], householdAccounts[i].Id);
        }
        data.householdIdsByKey = keysToIds;
        return keysToIds;
    }

    /**
     * Stage two: inserts the contacts of one zero-based chunk and joins each of them to
     * their household, then returns how many were inserted. data.householdIdsByKey must
     * already hold the stage one map.
     *
     * How a person is joined to a household is the membership mode's business, so the
     * chunk is joined through HouseholdService rather than by this class writing the join
     * itself. In contact mode that join is the contact's own household field, which costs
     * nothing to set as the record is built, so it is set here and the service is told
     * about people who are already where they belong. In junction mode the contact is
     * inserted with no household of its own and the service writes the membership row.
     */
    public static Integer loadContactChunk(SampleDataSet data, Integer chunkIndex) {
        List<Map<String, Object>> chunk = data.membersInChunk(chunkIndex);
        if (chunk.isEmpty()) {
            return 0;
        }

        Boolean junctionMembership = HouseholdService.isJunctionMode();
        List<Contact> contactsToInsert = new List<Contact>();
        List<Id> householdIds = new List<Id>();
        for (Map<String, Object> member : chunk) {
            Id householdId = data.householdIdsByKey.get((String) member.get('householdKey'));
            householdIds.add(householdId);
            contactsToInsert.add(buildContact(member, junctionMembership ? null : householdId));
        }
        // The sample people already have the household they belong to, so the automatic
        // creation that would otherwise give each of them one of their own is suspended for
        // this insert and the loader joins them itself (R-H2, ADR-0037).
        HouseholdService.suspendAutomaticCreation();
        try {
            Database.insert(contactsToInsert, sampleSaveOptions(), AccessLevel.USER_MODE);
        } finally {
            HouseholdService.resumeAutomaticCreation();
        }
        if (junctionMembership) {
            HouseholdService.addMembers(peopleByHousehold(contactsToInsert, householdIds));
        } else {
            // A household made by adding its first person has that person as its Primary
            // Contact. These households were made empty in stage one, so each gets the first
            // of its people in the file, as the product path would have given it.
            HouseholdService.seedMissingPrimaryContacts(
                firstPersonByHousehold(contactsToInsert, householdIds)
            );
        }
        // Sample data always arrives settled: member count, primary, name and both greetings.
        // The triggers that settle a household do not run while Household Upkeep is off (or
        // an administrator has switched one of them off), which would leave every household
        // named "Household". So the chunk's households are settled here whatever the switch
        // says; when the triggers did run this finds nothing to change and saves nothing.
        Set<Id> chunkHouseholds = new Set<Id>(householdIds);
        chunkHouseholds.remove(null);
        HouseholdService.afterMembershipChange(chunkHouseholds, false);
        // A household the generator named by hand keeps its name (R-H8): make sure its blank
        // greetings are filled from its people, whether or not Household Upkeep is on.
        HouseholdService.greetCustomNamedHouseholds(chunkHouseholds);
        return contactsToInsert.size();
    }

    /**
     * All or nothing, as an ordinary insert is, and saved past a duplicate rule that only
     * alerts. Sample people share streets, phone patterns and surnames with each other and
     * may resemble people already in the org, and an org's standard duplicate rules (on by
     * default in most editions) would otherwise refuse the load part way through. A rule the
     * org set to block still blocks: that is the administrator's decision, not an alert.
     */
    private static Database.DMLOptions sampleSaveOptions() {
        Database.DMLOptions options = new Database.DMLOptions();
        options.OptAllOrNone = true;
        options.DuplicateRuleHeader.AllowSave = true;
        return options;
    }

    /**
     * The inserted people of this chunk grouped by the household each of them belongs to,
     * in the shape HouseholdService.addMembers takes.
     */
    private static Map<Id, Set<Id>> peopleByHousehold(List<Contact> people, List<Id> householdIds) {
        Map<Id, Set<Id>> result = new Map<Id, Set<Id>>();
        for (Integer i = 0; i < people.size(); i++) {
            Id householdId = householdIds[i];
            if (householdId == null || people[i].Id == null) {
                continue;
            }
            if (!result.containsKey(householdId)) {
                result.put(householdId, new Set<Id>());
            }
            result.get(householdId).add(people[i].Id);
        }
        return result;
    }

    /** The first inserted person of this chunk in each household, in file order. */
    private static Map<Id, Id> firstPersonByHousehold(List<Contact> people, List<Id> householdIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (Integer i = 0; i < people.size(); i++) {
            Id householdId = householdIds[i];
            if (householdId != null && people[i].Id != null && !result.containsKey(householdId)) {
                result.put(householdId, people[i].Id);
            }
        }
        return result;
    }

    private static Account buildHouseholdAccount(Map<String, Object> household, Id recordTypeId) {
        Account acct = new Account();
        acct.RecordTypeId = recordTypeId;
        acct.Sample_Data__c = true;
        // The generator's key, kept on the record so the connection stage and a module
        // sample set (Giving) can find this household again in a later transaction.
        acct.Sample_Data_Key__c = (String) household.get('key');

        Object addressValue = household.get('address');
        if (addressValue instanceof Map<String, Object>) {
            Map<String, Object> address = (Map<String, Object>) addressValue;
            acct.BillingStreet = (String) address.get('street');
            acct.BillingCity = (String) address.get('city');
            acct.BillingState = (String) address.get('state');
            acct.BillingPostalCode = (String) address.get('postalCode');
        }

        Object anniversary = household.get('anniversary');
        if (anniversary != null) {
            acct.Anniversary__c = Date.valueOf((String) anniversary);
        }

        if (household.get('customName') == true) {
            // The household naming trigger never recomputes a Custom_Name__c household
            // (canonical model rule R-H8), so the generator's chosen wording is final.
            acct.Custom_Name__c = true;
            acct.Name = (String) household.get('name');
        } else {
            // Placeholder; each contact stage settles Name, the formal greeting and the
            // informal greeting once members are attached (R-H4), Household Upkeep on or off.
            acct.Name = 'Household';
        }
        return acct;
    }

    private static Account buildOrganizationAccount(
        Map<String, Object> organization,
        Id recordTypeId
    ) {
        Account acct = new Account();
        acct.RecordTypeId = recordTypeId;
        acct.Sample_Data__c = true;
        acct.Sample_Data_Key__c = (String) organization.get('key');
        acct.Name = (String) organization.get('name');
        acct.Website = (String) organization.get('website');
        acct.Phone = (String) organization.get('phone');
        return acct;
    }

    private static Contact buildContact(Map<String, Object> member, Id householdId) {
        // No record type is set: the package ships none for Contact, so each person gets the
        // running user's default, which is whatever the org has chosen.
        Contact con = new Contact();
        con.Sample_Data__c = true;
        con.Sample_Data_Key__c = (String) member.get('key');
        // Null in junction mode: the household is named by the membership row instead, and
        // a contact carrying both would be in the household twice over.
        con.AccountId = householdId;
        con.FirstName = (String) member.get('firstName');
        con.LastName = (String) member.get('lastName');
        con.Salutation = (String) member.get('salutation');
        con.Household_Role__c = (String) member.get('householdRole');
        con.Email = (String) member.get('email');
        con.Phone = (String) member.get('phone');
        con.MailingStreet = (String) member.get('mailingStreet');
        con.MailingCity = (String) member.get('mailingCity');
        con.MailingState = (String) member.get('mailingState');
        con.MailingPostalCode = (String) member.get('mailingPostalCode');

        Object birthdate = member.get('birthdate');
        if (birthdate != null) {
            con.Birthdate = Date.valueOf((String) birthdate);
        }
        Object preferredName = member.get('preferredName');
        if (preferredName != null) {
            con.Preferred_Name__c = (String) preferredName;
        }
        if (member.get('deceased') == true) {
            con.Deceased__c = true;
        }
        return con;
    }

    private static Id recordTypeId(Schema.SObjectType sobjectType, String developerName) {
        // DEFERRED skips loading child relationships this method never uses. NOPMD:
        // EagerlyLoadedDescribeSObjectResult flags any getDescribe() call regardless of
        // the DEFERRED option, which is the rule's own recommended fix.
        Schema.DescribeSObjectResult describeResult = sobjectType.getDescribe( // NOPMD
            Schema.SObjectDescribeOptions.DEFERRED
        );
        Map<String, Schema.RecordTypeInfo> infosByDeveloperName = describeResult.getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infosByDeveloperName.get(developerName);
        if (info == null) {
            throw new SampleDataException(
                String.format(
                    Label.Core_SampleData_RecordTypeMissing,
                    new List<Object>{ developerName }
                )
            );
        }
        return info.getRecordTypeId();
    }
}
