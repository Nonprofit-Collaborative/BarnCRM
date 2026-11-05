/**
 * Keeps the standard email on a person in step with the address they chose (R-C6).
 *
 * The standard email field is the one Salesforce and every email tool reads, so a person
 * who keeps a personal, a work and an alternate address needs it to hold whichever of the
 * three they said to use. This copies it on every save, before the record is written.
 *
 * Nothing is read and nothing is queried here: this is upkeep on the record in front of
 * it, and it runs as the trigger does (ADR-0021). Leaving the choice empty means the org
 * is not using the three addresses, so nothing is touched at all.
 *
 * Two entry points because the two objects hold the standard email in different places. A
 * contact holds it on `Email`, which every org has. An org that stores people as accounts
 * holds it on a field the account object only has where the org is shaped that way, so
 * that half never names it at compile time: the field is looked up by name and written
 * with SObject.put, exactly as `PersonRecordSelector` reads the person name fields.
 */
public with sharing class PreferredEmailService {
    private static final Map<String, String> FIELD_BY_PREFERENCE = new Map<String, String>{
        'Personal' => 'Personal_Email__c',
        'Work' => 'Work_Email__c',
        'Alternate' => 'Alternate_Email__c'
    };

    // The account object carries the standard email under this name only in orgs that store
    // people as accounts, so it is held as text and never referenced statically.
    private static final String ACCOUNT_EMAIL_FIELD = 'PersonEmail';

    /**
     * People stored as contacts. Called before insert and before update.
     */
    public static void apply(List<Contact> records) {
        if (records == null) {
            return;
        }
        for (Contact person : records) {
            String chosen = chosenEmail(person, person.Preferred_Email__c);
            if (chosen != null) {
                person.Email = chosen;
            }
        }
    }

    /**
     * People stored as accounts. Called before insert and before update, and does nothing
     * at all unless this org keeps people that way and the account object really has the
     * standard email field.
     */
    public static void applyToPersonRecords(List<Account> records) {
        if (records == null || records.isEmpty() || !HouseholdService.isPersonAccountOrg()) {
            return;
        }
        if (!Schema.SObjectType.Account.fields.getMap().containsKey(ACCOUNT_EMAIL_FIELD)) {
            return;
        }
        for (Account record : records) {
            if (!PersonRecordSelector.isPersonRecord(record)) {
                continue;
            }
            String chosen = chosenEmail(record, (String) record.get('Preferred_Email__c'));
            if (chosen != null) {
                record.put(ACCOUNT_EMAIL_FIELD, chosen);
            }
        }
    }

    /**
     * The address this person chose, or null when there is nothing to copy.
     *
     * Refusing the save is the answer when the chosen address is empty: blanking the
     * standard email would take the person off every mailing and nobody would notice.
     */
    private static String chosenEmail(SObject person, String preference) {
        if (String.isBlank(preference)) {
            return null;
        }
        String fieldName = FIELD_BY_PREFERENCE.get(preference);
        if (fieldName == null) {
            return null;
        }
        String chosen = (String) person.get(fieldName);
        if (String.isBlank(chosen)) {
            person.addError(
                String.format(
                    BarnHelp.text('Core', 'Core_Emails_PreferredEmpty'),
                    new List<String>{ preference }
                )
            );
            return null;
        }
        return chosen;
    }
}
