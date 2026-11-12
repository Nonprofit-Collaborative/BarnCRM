/**
 * What the Scholarships and Outbound Grants classes share (ADR-NEXT
 * `NEXT-scholarships-outbound-grants-module.md`): the Manage Scholarships check, the
 * module's bell notification and the refusal a person reads as written.
 */
public with sharing class Scholarships {
	public static final String MODULE = 'Scholarships';
	public static final String MANAGE = 'Scholarships_Manage';
	private static final String NOTIFICATION_TYPE = 'Scholarships_Reminder';

	/** Every notification handed to the platform this transaction, by title, for the tests. */
	@TestVisible
	private static List<String> sentTitles = new List<String>();

	/** A refusal written for the person: `UserErrors` shows it as it is. */
	public class ScholarshipException extends Exception {
	}

	/** Whether the running user holds Manage Scholarships (in Scholarships Admin). */
	public static Boolean canManage() {
		return FeatureManagement.checkPermission(MANAGE);
	}

	/** Refuses, in words, anyone without Manage Scholarships. */
	public static void requireManage() {
		if (!canManage()) {
			throw new ScholarshipException(
				BarnHelp.text('Scholarships', 'Scholarships_Error_NoPermission')
			);
		}
	}

	/** A refusal written for the person, from the module's help text. */
	public static ScholarshipException refuse(String message) {
		return new ScholarshipException(message);
	}

	/**
	 * Sends one bell notification of the module's own type. Never throws: an org whose edition
	 * has no custom notifications sends nothing, and a refused send is written to the Error Log.
	 */
	public static void notify(Set<String> recipientIds, String title, Id targetId) {
		if (recipientIds == null || recipientIds.isEmpty()) {
			return;
		}
		sentTitles.add(title);
		JobNotifier.ownType(
			NOTIFICATION_TYPE,
			recipientIds,
			title,
			BarnHelp.text('Scholarships', 'Scholarships_Notify_Body'),
			targetId,
			'Scholarships.notify'
		);
	}
}
