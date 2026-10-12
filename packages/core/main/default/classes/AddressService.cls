/**
 * Addresses (C-17, canonical model Section 29).
 *
 * Two directions, and a single in-transaction flag keeps them from calling each other
 * round in a circle:
 *
 * 1. syncDefaultToStandardFields: the address marked default is copied into the standard
 *    address fields on its owner, and on every current household member, so mail merges,
 *    reports, and other apps keep reading the address they have always read (R-AD3).
 * 2. captureFromStandardFields: an address typed into the standard fields, or changed
 *    there, becomes or updates an address record, so the records stay the truth (R-AD5).
 *
 * No Person Account field is referenced statically anywhere in this class. Where people
 * are person accounts their mailing fields are written dynamically, by name, only in an
 * org that has them (plan Section 4.2, ADR-0009), and only on an account that actually
 * holds a person: in such an org those fields exist on every account, but only a person
 * account will accept a value in one, so the record type decides the write and not the
 * org shape. See personAccountIdsAmong.
 */
public with sharing class AddressService {
    @TestVisible
    private static Boolean isPropagating = false;

    @TestVisible
    private static final String BEHAVIOR_UPDATE_HOUSEHOLD = 'Update household';
    @TestVisible
    private static final String BEHAVIOR_PERSONAL_ADDRESS = 'Create personal address';

    private static final String TYPE_HOME = 'Home';
    private static final String TYPE_WORK = 'Work';
    private static final String TYPE_SEASONAL = 'Seasonal';

    private static final String RECORD_TYPE_HOUSEHOLD = 'Household';
    private static final String RECORD_TYPE_ORGANIZATION = 'Organization';

    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STREET = 'PersonMailingStreet';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_CITY = 'PersonMailingCity';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_STATE = 'PersonMailingState';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_POSTAL_CODE = 'PersonMailingPostalCode';
    // detection-only: Person Account orgs
    private static final String PERSON_MAILING_COUNTRY = 'PersonMailingCountry';

    private static Map<String, Schema.SObjectField> accountFields;

    /**
     * Test seam. Household membership is read only through HouseholdService, which hides
     * whether the org uses contact mode or the membership junction. Junction mode, and
     * households whose people are person accounts, are reproduced here by handing this
     * class the membership HouseholdService would return, because the junction object and
     * person accounts cannot both be created in one org shape. Never set outside a test.
     */
    @TestVisible
    private static Map<Id, Set<Id>> membersByHouseholdOverride;

    // ---------------------------------------------------------------- direction one

    /**
     * Copies each default address into the standard address fields of its owner. An
     * address owned by an account writes the account's billing address and the mailing
     * address of every current household member; an address owned by one person writes
     * that person's mailing address only.
     */
    public static void syncDefaultToStandardFields(List<Address__c> addresses) {
        if (addresses == null || addresses.isEmpty() || isPropagating) {
            return;
        }
        List<Address__c> defaults = defaultsOnly(addresses);
        if (defaults.isEmpty()) {
            return;
        }
        isPropagating = true;
        try {
            clearOtherDefaults(defaults);
            applyToStandardFields(defaults);
        } finally {
            isPropagating = false;
        }
    }

    /**
     * After a default address is deleted, promotes the most recently created remaining
     * address for that owner. Deleting a default is allowed: refusing it would leave a
     * household stuck with an address it no longer uses.
     */
    public static void promoteDefaultAfterDelete(List<Address__c> deletedAddresses) {
        if (deletedAddresses == null || deletedAddresses.isEmpty() || isPropagating) {
            return;
        }
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> deletedIds = new Set<Id>();
        for (Address__c address : deletedAddresses) {
            deletedIds.add(address.Id);
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                ownerIds.add(ownerIdOf(address));
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        Map<Id, Address__c> newestByOwner = new Map<Id, Address__c>();
        for (Address__c address : AddressSelector.selectByOwnerIds(ownerIds)) {
            Id ownerId = ownerIdOf(address);
            if (deletedIds.contains(address.Id) || ownerId == null) {
                continue;
            }
            Address__c held = newestByOwner.get(ownerId);
            if (held == null || address.CreatedDate > held.CreatedDate) {
                newestByOwner.put(ownerId, address);
            }
        }
        if (newestByOwner.isEmpty()) {
            return;
        }
        List<Address__c> promoted = new List<Address__c>();
        for (Address__c address : newestByOwner.values()) {
            address.Is_Default__c = true;
            promoted.add(new Address__c(Id = address.Id, Is_Default__c = true));
        }
        // The flag is raised before the promotion is saved, so the address trigger this
        // update fires does not propagate a second time: the propagation below is the one
        // that runs, and the standard fields are written once for the whole batch.
        isPropagating = true;
        try {
            Database.update(promoted, AccessLevel.USER_MODE);
            applyToStandardFields(new List<Address__c>(newestByOwner.values()));
        } finally {
            isPropagating = false;
        }
    }

    // ---------------------------------------------------------------- direction two

    /**
     * Turns an address typed into the standard fields into an address record.
     *
     * A household or organization account created with a billing address gets a default
     * address record of type Home (Work for an organization), so nothing staff typed or
     * an import loaded is lost. A person whose mailing address changes either moves their
     * whole household or gains an address of their own, depending on the org's
     * Contact_Address_Change_Behavior__c setting.
     */
    public static void captureFromStandardFields(List<Account> accounts, List<Contact> contacts) {
        Boolean nothingToDo =
            (accounts == null || accounts.isEmpty()) && (contacts == null || contacts.isEmpty());
        if (nothingToDo || isPropagating) {
            return;
        }
        isPropagating = true;
        try {
            List<Address__c> toInsert = new List<Address__c>();
            List<Address__c> toUpdate = new List<Address__c>();
            captureAccounts(accounts, toInsert);
            captureContacts(contacts, toInsert, toUpdate);
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, AccessLevel.USER_MODE);
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
            }
            List<Address__c> touched = new List<Address__c>();
            touched.addAll(toUpdate);
            touched.addAll(toInsert);
            if (touched.isEmpty()) {
                return;
            }
            clearOtherDefaults(touched);
            applyToStandardFields(touched);
        } finally {
            isPropagating = false;
        }
    }

    // ---------------------------------------------------------------- seasonal helper

    /**
     * Whether a seasonal address covers today. A range may wrap the end of the year, so
     * November 1 to March 31 is one range and not two (R-AD4). The v0.4 seasonal swap job
     * (C-18) is the only planned caller; it needs no change to this object.
     */
    public static Boolean isSeasonalActiveToday(Address__c address) {
        return isSeasonalActiveOn(address, Date.today());
    }

    /** The same test against any day, so the swap job and its tests can name a date. */
    public static Boolean isSeasonalActiveOn(Address__c address, Date day) {
        if (address == null || day == null || address.Type__c != TYPE_SEASONAL) {
            return false;
        }
        if (
            address.Seasonal_Start_Month__c == null ||
            address.Seasonal_Start_Day__c == null ||
            address.Seasonal_End_Month__c == null ||
            address.Seasonal_End_Day__c == null
        ) {
            return false;
        }
        Integer today = (day.month() * 100) + day.day();
        Integer start =
            (address.Seasonal_Start_Month__c.intValue() * 100) +
            address.Seasonal_Start_Day__c.intValue();
        Integer finish =
            (address.Seasonal_End_Month__c.intValue() * 100) +
            address.Seasonal_End_Day__c.intValue();
        if (start <= finish) {
            return today >= start && today <= finish;
        }
        return today >= start || today <= finish;
    }

    // ---------------------------------------------------------------- internals

    private static List<Address__c> defaultsOnly(List<Address__c> addresses) {
        List<Address__c> defaults = new List<Address__c>();
        for (Address__c address : addresses) {
            if (address.Is_Default__c == true && ownerIdOf(address) != null) {
                defaults.add(address);
            }
        }
        return defaults;
    }

    private static Id ownerIdOf(Address__c address) {
        if (address.Account__c != null) {
            return address.Account__c;
        }
        if (address.Contact__c != null) {
            return address.Contact__c;
        }
        return address.Person_Account__c;
    }

    /** At most one address per owner is the default (R-AD2). */
    private static void clearOtherDefaults(List<Address__c> defaults) {
        Set<Id> ownerIds = new Set<Id>();
        Set<Id> keepIds = new Set<Id>();
        for (Address__c address : defaults) {
            if (address.Is_Default__c != true) {
                continue;
            }
            Id ownerId = ownerIdOf(address);
            if (ownerId != null) {
                ownerIds.add(ownerId);
                keepIds.add(address.Id);
            }
        }
        if (ownerIds.isEmpty()) {
            return;
        }
        List<Address__c> stale = new List<Address__c>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(ownerIds, keepIds)) {
            stale.add(new Address__c(Id = address.Id, Is_Default__c = false));
        }
        if (!stale.isEmpty()) {
            Database.update(stale, AccessLevel.USER_MODE);
        }
    }

    /**
     * Writes the standard address fields. Only ever called with the propagation flag
     * already raised, so nothing it writes comes back round as another capture.
     */
    private static void applyToStandardFields(List<Address__c> defaults) {
        Map<Id, Address__c> byOwner = new Map<Id, Address__c>();
        for (Address__c address : defaults) {
            Id ownerId = ownerIdOf(address);
            if (address.Is_Default__c == true && ownerId != null) {
                byOwner.put(ownerId, address);
            }
        }
        if (byOwner.isEmpty()) {
            return;
        }

        // Mutual exclusion (product-plan Section 11.2 item 9): an owner that is itself an
        // Account, household or person account alike, is left out here when it already
        // carries a native Nonprofit Cloud household group, so its billing or person
        // mailing fields are never overwritten and its address is never propagated to
        // household members from this default. A Contact owner cannot carry a native group,
        // so only Account and person-account owners are asked. One predicate query for the
        // whole batch.
        Set<Id> accountOwnerIds = new Set<Id>();
        for (Id ownerId : byOwner.keySet()) {
            Address__c owned = byOwner.get(ownerId);
            if (owned.Account__c != null || owned.Person_Account__c != null) {
                accountOwnerIds.add(ownerId);
            }
        }
        for (Id nativeHousehold : HouseholdSelector.nativeHouseholdAccountsAmong(accountOwnerIds)) {
            byOwner.remove(nativeHousehold);
        }
        if (byOwner.isEmpty()) {
            return;
        }

        Map<Id, Account> accountUpdates = new Map<Id, Account>();
        Map<Id, Contact> contactUpdates = new Map<Id, Contact>();
        Map<Id, Address__c> addressByHousehold = new Map<Id, Address__c>();
        Map<Id, Address__c> addressByPersonOwner = new Map<Id, Address__c>();

        for (Id ownerId : byOwner.keySet()) {
            Address__c address = byOwner.get(ownerId);
            if (address.Account__c != null) {
                accountUpdates.put(ownerId, billingCopy(ownerId, address));
                addressByHousehold.put(ownerId, address);
            } else if (address.Contact__c != null) {
                contactUpdates.put(ownerId, mailingCopy(ownerId, address));
            } else if (address.Person_Account__c != null) {
                addressByPersonOwner.put(ownerId, address);
            }
        }

        // Every account this save might write person mailing fields on, asked about once,
        // before anything is built: an account that does not hold a person must be left
        // out rather than written and refused. See personAccountIdsAmong.
        Map<Id, Set<Id>> membersByHousehold = membersOf(addressByHousehold.keySet());
        Set<Id> candidates = new Set<Id>(addressByPersonOwner.keySet());
        candidates.addAll(memberAccountIds(membersByHousehold));
        Set<Id> personAccountIds = personAccountIdsAmong(candidates);

        for (Id ownerId : addressByPersonOwner.keySet()) {
            if (!personAccountIds.contains(ownerId)) {
                continue;
            }
            Account personAccount = personMailingCopy(
                ownerId,
                addressByPersonOwner.get(ownerId),
                accountUpdates.get(ownerId)
            );
            if (personAccount != null) {
                accountUpdates.put(ownerId, personAccount);
            }
        }

        propagateToHouseholdMembers(
            addressByHousehold,
            membersByHousehold,
            personAccountIds,
            accountUpdates,
            contactUpdates
        );

        if (!contactUpdates.isEmpty()) {
            Database.update(contactUpdates.values(), AccessLevel.USER_MODE);
        }
        if (!accountUpdates.isEmpty()) {
            Database.update(accountUpdates.values(), AccessLevel.USER_MODE);
        }
    }

    /**
     * The people in each of these households, as HouseholdService reports them, so that
     * contact mode and the membership junction look the same from here.
     */
    private static Map<Id, Set<Id>> membersOf(Set<Id> householdIds) {
        if (householdIds == null || householdIds.isEmpty()) {
            return new Map<Id, Set<Id>>();
        }
        Map<Id, Set<Id>> members = membersByHouseholdOverride != null
            ? membersByHouseholdOverride
            : HouseholdService.getMemberPersonIds(householdIds);
        return members == null ? new Map<Id, Set<Id>>() : members;
    }

    /** The members that are account records rather than contacts, households excluded. */
    private static Set<Id> memberAccountIds(Map<Id, Set<Id>> membersByHousehold) {
        Set<Id> accountIds = new Set<Id>();
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (
                    memberId != null &&
                    memberId != householdId &&
                    memberId.getSObjectType() != contactType
                ) {
                    accountIds.add(memberId);
                }
            }
        }
        return accountIds;
    }

    /**
     * Which of these accounts actually hold a person.
     *
     * In an org that stores people as accounts, the person mailing fields exist on every
     * account record, so asking the object whether it has them says only what the org is
     * shaped like. Only an account whose record type is a person type will accept a value
     * in them: writing one on a household or an organization fails the whole save, and the
     * address the user was trying to save is refused with it. So the question that decides
     * the write is asked of the record, not of the org, and it is asked the same way
     * captureAccounts already asks it, through the record types OrgShapeDetector found.
     *
     * The record types are read in system mode (ADR-0021): a household member the saving
     * user cannot see would otherwise come back as nothing at all, read as an organization,
     * and be skipped, so the address would silently reach some of a household and not the
     * rest. The answer decides which fields a write may name and never reaches a screen.
     */
    private static Set<Id> personAccountIdsAmong(Set<Id> accountIds) {
        Set<Id> found = new Set<Id>();
        if (accountIds == null || accountIds.isEmpty() || !personAccountFieldsAvailable()) {
            return found;
        }
        Set<Id> personRecordTypeIds = OrgShapeDetector.detect().personAccountRecordTypeIds;
        if (personRecordTypeIds == null || personRecordTypeIds.isEmpty()) {
            return found;
        }
        for (Account account : HouseholdSelector.getAccountRecordTypes(accountIds)) {
            if (personRecordTypeIds.contains(account.RecordTypeId)) {
                found.add(account.Id);
            }
        }
        return found;
    }

    private static void propagateToHouseholdMembers(
        Map<Id, Address__c> addressByHousehold,
        Map<Id, Set<Id>> membersByHousehold,
        Set<Id> personAccountIds,
        Map<Id, Account> accountUpdates,
        Map<Id, Contact> contactUpdates
    ) {
        if (addressByHousehold.isEmpty() || membersByHousehold.isEmpty()) {
            return;
        }
        Schema.SObjectType contactType = Contact.SObjectType;
        for (Id householdId : membersByHousehold.keySet()) {
            Address__c address = addressByHousehold.get(householdId);
            Set<Id> memberIds = membersByHousehold.get(householdId);
            if (address == null || memberIds == null) {
                continue;
            }
            for (Id memberId : memberIds) {
                if (memberId == null || memberId == householdId) {
                    continue;
                }
                if (memberId.getSObjectType() == contactType) {
                    contactUpdates.put(memberId, mailingCopy(memberId, address));
                } else if (personAccountIds.contains(memberId)) {
                    Account personAccount = personMailingCopy(
                        memberId,
                        address,
                        accountUpdates.get(memberId)
                    );
                    if (personAccount != null) {
                        accountUpdates.put(memberId, personAccount);
                    }
                }
            }
        }
    }

    private static Account billingCopy(Id accountId, Address__c address) {
        return new Account(
            Id = accountId,
            BillingStreet = address.Street__c,
            BillingCity = address.City__c,
            BillingState = address.State__c,
            BillingPostalCode = address.Postal_Code__c,
            BillingCountry = address.Country__c
        );
    }

    private static Contact mailingCopy(Id contactId, Address__c address) {
        return new Contact(
            Id = contactId,
            MailingStreet = address.Street__c,
            MailingCity = address.City__c,
            MailingState = address.State__c,
            MailingPostalCode = address.Postal_Code__c,
            MailingCountry = address.Country__c
        );
    }

    /**
     * Writes the mailing fields a person account carries. The field names are held as
     * strings and written with put, so this class compiles and runs in an org where those
     * fields do not exist.
     */
    private static Account personMailingCopy(Id accountId, Address__c address, Account existing) {
        if (!personAccountFieldsAvailable()) {
            return null;
        }
        Account record = existing == null ? new Account(Id = accountId) : existing;
        record.put(PERSON_MAILING_STREET, address.Street__c);
        record.put(PERSON_MAILING_CITY, address.City__c);
        record.put(PERSON_MAILING_STATE, address.State__c);
        record.put(PERSON_MAILING_POSTAL_CODE, address.Postal_Code__c);
        record.put(PERSON_MAILING_COUNTRY, address.Country__c);
        return record;
    }

    private static Boolean personAccountFieldsAvailable() {
        if (!OrgShapeDetector.detect().hasPersonAccounts) {
            return false;
        }
        if (accountFields == null) {
            accountFields = Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
                .fields
                .getMap();
        }
        return accountFields.containsKey(PERSON_MAILING_STREET.toLowerCase());
    }

    private static void captureAccounts(List<Account> accounts, List<Address__c> toInsert) {
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        Map<Id, Schema.RecordTypeInfo> recordTypes = Account.SObjectType.getDescribe(
                SObjectDescribeOptions.DEFERRED
            )
            .getRecordTypeInfosById();
        Set<Id> personAccountRecordTypeIds = OrgShapeDetector.detect().personAccountRecordTypeIds;
        for (Account account : accounts) {
            if (
                personAccountRecordTypeIds != null &&
                personAccountRecordTypeIds.contains(account.RecordTypeId)
            ) {
                continue;
            }
            String developerName = account.RecordTypeId == null ||
                recordTypes.get(account.RecordTypeId) == null
                ? null
                : recordTypes.get(account.RecordTypeId).getDeveloperName();
            if (
                developerName != RECORD_TYPE_HOUSEHOLD &&
                developerName != RECORD_TYPE_ORGANIZATION
            ) {
                continue;
            }
            if (
                !hasAnyValue(
                    account.BillingStreet,
                    account.BillingCity,
                    account.BillingState,
                    account.BillingPostalCode,
                    account.BillingCountry
                )
            ) {
                continue;
            }
            toInsert.add(
                new Address__c(
                    Account__c = account.Id,
                    Type__c = developerName == RECORD_TYPE_ORGANIZATION ? TYPE_WORK : TYPE_HOME,
                    Is_Default__c = true,
                    Street__c = account.BillingStreet,
                    City__c = account.BillingCity,
                    State__c = account.BillingState,
                    Postal_Code__c = account.BillingPostalCode,
                    Country__c = account.BillingCountry
                )
            );
        }
    }

    private static void captureContacts(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        List<Contact> withAddress = new List<Contact>();
        for (Contact contact : contacts) {
            if (
                hasAnyValue(
                    contact.MailingStreet,
                    contact.MailingCity,
                    contact.MailingState,
                    contact.MailingPostalCode,
                    contact.MailingCountry
                )
            ) {
                withAddress.add(contact);
            }
        }
        if (withAddress.isEmpty()) {
            return;
        }
        if (behavior() == BEHAVIOR_PERSONAL_ADDRESS) {
            capturePersonalAddresses(withAddress, toInsert, toUpdate);
        } else {
            captureHouseholdAddresses(withAddress, toInsert, toUpdate);
        }
    }

    private static void captureHouseholdAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Id> householdByPerson = HouseholdService.getHouseholdIdsFor(contactIds);
        if (householdByPerson == null || householdByPerson.isEmpty()) {
            return;
        }
        Map<Id, Contact> sourceByHousehold = new Map<Id, Contact>();
        for (Contact contact : contacts) {
            Id householdId = householdByPerson.get(contact.Id);
            if (householdId == null) {
                continue;
            }
            sourceByHousehold.put(householdId, contact);
        }
        if (sourceByHousehold.isEmpty()) {
            return;
        }
        Map<Id, Address__c> defaultByHousehold = new Map<Id, Address__c>();
        for (
            Address__c address : AddressSelector.selectDefaultsByOwnerIds(
                sourceByHousehold.keySet(),
                null
            )
        ) {
            if (address.Account__c != null) {
                defaultByHousehold.put(address.Account__c, address);
            }
        }
        for (Id householdId : sourceByHousehold.keySet()) {
            Contact source = sourceByHousehold.get(householdId);
            Address__c existing = defaultByHousehold.get(householdId);
            if (existing == null) {
                toInsert.add(newAddressFromContact(source, TYPE_HOME, householdId, null));
            } else {
                toUpdate.add(copyContactAddressOnto(new Address__c(Id = existing.Id), source));
            }
        }
    }

    private static void capturePersonalAddresses(
        List<Contact> contacts,
        List<Address__c> toInsert,
        List<Address__c> toUpdate
    ) {
        Set<Id> contactIds = new Map<Id, Contact>(contacts).keySet();
        Map<Id, Address__c> defaultByContact = new Map<Id, Address__c>();
        for (Address__c address : AddressSelector.selectDefaultsByOwnerIds(contactIds, null)) {
            if (address.Contact__c != null) {
                defaultByContact.put(address.Contact__c, address);
            }
        }
        for (Contact contact : contacts) {
            Address__c existing = defaultByContact.get(contact.Id);
            if (existing == null) {
                toInsert.add(newAddressFromContact(contact, TYPE_HOME, null, contact.Id));
            } else {
                toUpdate.add(copyContactAddressOnto(new Address__c(Id = existing.Id), contact));
            }
        }
    }

    private static Address__c newAddressFromContact(
        Contact source,
        String addressType,
        Id accountId,
        Id contactId
    ) {
        Address__c address = new Address__c(
            Account__c = accountId,
            Contact__c = contactId,
            Type__c = addressType,
            Is_Default__c = true
        );
        return copyContactAddressOnto(address, source);
    }

    private static Address__c copyContactAddressOnto(Address__c address, Contact source) {
        address.Street__c = source.MailingStreet;
        address.City__c = source.MailingCity;
        address.State__c = source.MailingState;
        address.Postal_Code__c = source.MailingPostalCode;
        address.Country__c = source.MailingCountry;
        address.Is_Default__c = true;
        return address;
    }

    private static String behavior() {
        BarnCRM_Settings__c settings = SettingsService.getSettings();
        String value = settings == null ? null : settings.Contact_Address_Change_Behavior__c;
        return String.isBlank(value) ? BEHAVIOR_UPDATE_HOUSEHOLD : value;
    }

    private static Boolean hasAnyValue(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        return String.isNotBlank(street) ||
            String.isNotBlank(city) ||
            String.isNotBlank(state) ||
            String.isNotBlank(postalCode) ||
            String.isNotBlank(country);
    }
}
