/**
 * The Erase person action (canonical model Section 29H). Everything is decided in
 * `PersonErasure`; this class turns its refusals into messages the screen shows, and anything
 * unexpected into the generic message, logged.
 */
public with sharing class PersonErasureController {
	private static final UserErrors.Screen ERRORS = new UserErrors.Screen(
		null,
		'Core',
		'Core_Households_ErrorUnexpected'
	);

	/** What erasing this person would change, with nothing changed. */
	@AuraEnabled
	public static PersonErasure.Result preview(Id personId) {
		try {
			return PersonErasure.preview(personId);
		} catch (Exception failed) {
			throw ERRORS.wrap(failed, 'PersonErasureController', personId);
		}
	}

	/** Erases the person, once the typed name matches. */
	@AuraEnabled
	public static PersonErasure.Result erase(
		Id personId,
		String typedName,
		String requestReference
	) {
		try {
			return PersonErasure.erase(personId, typedName, requestReference);
		} catch (Exception failed) {
			throw ERRORS.wrap(failed, 'PersonErasureController', personId);
		}
	}
}
