/**
 * Keeps the standard phone on a contact in step with the number they chose (R-C6a).
 *
 * The standard phone is the one list views and dialers read, so a person who keeps a home, a
 * mobile and another number needs it to hold whichever of the three they said to call. This
 * copies it on every save, before the record is written, the same way PreferredEmailService
 * keeps the standard email. Nothing is queried here. Leaving the choice empty means the org is
 * not using the choice, so nothing is touched at all.
 *
 * Contacts only: the three source fields are standard fields every org has on Contact, so
 * nothing here depends on Person Accounts (ADR-0013).
 */
public with sharing class PreferredPhoneService {
    private static final Map<String, String> FIELD_BY_PREFERENCE = new Map<String, String>{
        'Home' => 'HomePhone',
        'Mobile' => 'MobilePhone',
        'Work' => 'Work_Phone__c',
        'Other' => 'OtherPhone'
    };

    /**
     * Called before insert and before update.
     */
    public static void apply(List<Contact> records) {
        if (records == null) {
            return;
        }
        for (Contact person : records) {
            String preference = person.Preferred_Phone__c;
            if (String.isBlank(preference)) {
                continue;
            }
            String fieldName = FIELD_BY_PREFERENCE.get(preference);
            if (fieldName == null) {
                continue;
            }
            String chosen = (String) person.get(fieldName);
            if (String.isBlank(chosen)) {
                // Blanking the standard phone would take the person off every call list and
                // nobody would notice, so the save is refused instead.
                person.addError(
                    String.format(Label.Core_Phones_PreferredEmpty, new List<String>{ preference })
                );
            } else {
                person.Phone = chosen;
            }
        }
    }
}
