/**
 * Contact trigger handler, registered as "Keep a household together when a person's
 * address changes" in the automation registry and dispatched by TriggerDispatcher on the
 * one Contact trigger, so no other feature's handler is touched by this one.
 *
 * When a person's mailing address is entered or changed, the org's Addresses setting
 * decides what happens: the household moves together, or that person gets an address of
 * their own (canonical model R-AD5).
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler.
 */
public with sharing class ContactAddressHandler extends TriggerHandler {
	public override void afterInsert() {
		capture((List<Contact>) newRecords());
	}

	public override void afterUpdate() {
		List<Contact> records = (List<Contact>) newRecords();
		Map<Id, SObject> previousById = oldRecordsById();
		List<Contact> moved = new List<Contact>();
		if (records == null) {
			return;
		}
		for (Contact person : records) {
			Contact old = previousById == null ? null : (Contact) previousById.get(person.Id);
			if (old == null || mailingAddressChanged(person, old)) {
				moved.add(person);
			}
		}
		capture(moved);
	}

	private void capture(List<Contact> contacts) {
		if (contacts == null || contacts.isEmpty()) {
			return;
		}
		try {
			AddressService.captureFromStandardFields(null, contacts);
		} catch (Exception thrown) {
			ErrorLogger.log(thrown, 'ContactAddressHandler.capture');
			for (Contact person : contacts) {
				person.addError(BarnHelp.text('Core', 'Core_Address_PropagationFailed'));
			}
		}
	}

	private Boolean mailingAddressChanged(Contact person, Contact old) {
		return person.MailingStreet != old.MailingStreet ||
			person.MailingCity != old.MailingCity ||
			person.MailingState != old.MailingState ||
			person.MailingPostalCode != old.MailingPostalCode ||
			person.MailingCountry != old.MailingCountry;
	}
}
