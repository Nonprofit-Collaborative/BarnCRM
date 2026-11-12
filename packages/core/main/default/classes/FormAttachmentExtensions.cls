/**
 * Finds the form attachment extensions modules installed (ADR-0175 `0175-forms-module.md`,
 * decision 9), the pattern `RecordGlanceExtensions` uses (ADR-0167). A class that is not
 * installed, cannot be built or does not implement the interface is absent, and a failure is
 * logged: a form must be filled in and processed whatever a module does.
 */
@NamespaceAccessible
public with sharing class FormAttachmentExtensions {
	/**
	 * The class names modules register: Event Management's registrations (EV-02) and Volunteers'
	 * shift sign-ups and personal page (V-09), and Scholarships' applications and reports (SG-02).
	 */
	@NamespaceAccessible
	public static final List<String> EXTENSION_CLASSES = new List<String>{
		'EventFormAttachment',
		'VolunteerFormAttachment',
		'ScholarshipFormAttachment'
	};

	/** Injected by tests by class name, since no module is there to resolve. */
	@TestVisible
	private static Map<String, FormAttachmentExtension> overrides = new Map<String, FormAttachmentExtension>();

	/** Every installed extension, in registration order. */
	@NamespaceAccessible
	public static List<FormAttachmentExtension> installed() {
		List<FormAttachmentExtension> found = new List<FormAttachmentExtension>();
		for (String className : EXTENSION_CLASSES) {
			FormAttachmentExtension extension = overrides.containsKey(className)
				? overrides.get(className)
				: resolve(className);
			if (extension != null) {
				found.add(extension);
			}
		}
		return found;
	}

	/** The form a module attached to this record, or null when none did. */
	@NamespaceAccessible
	public static Id formFor(Id contextRecordId) {
		if (contextRecordId == null) {
			return null;
		}
		for (FormAttachmentExtension extension : handling(contextRecordId)) {
			try {
				Id formId = extension.formFor(contextRecordId);
				if (formId != null) {
					return formId;
				}
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'FormAttachmentExtensions.formFor', contextRecordId);
			}
		}
		return null;
	}

	/** Whether a module asks that a public link to this record carry a signed claim (EV-18). */
	@NamespaceAccessible
	public static Boolean signedClaimRequired(Id contextRecordId) {
		if (contextRecordId == null) {
			return false;
		}
		for (FormAttachmentExtension extension : handling(contextRecordId)) {
			try {
				if (extension.signedClaim(contextRecordId) == true) {
					return true;
				}
			} catch (Exception failed) {
				ErrorLogger.log(
					failed,
					'FormAttachmentExtensions.signedClaimRequired',
					contextRecordId
				);
				return true;
			}
		}
		return false;
	}

	/**
	 * Hands a processed submission to every extension that handles its context record's object.
	 * Each runs under its own savepoint: one that fails is rolled back and logged, and its message
	 * is returned so the submission can be marked for review. The form's own records stay.
	 *
	 * @return the failures' messages, empty when every extension took it
	 */
	@NamespaceAccessible
	public static List<String> notify(FormSubmissionReceipt receipt) {
		List<String> failures = new List<String>();
		if (receipt == null || receipt.contextRecordId == null) {
			return failures;
		}
		for (FormAttachmentExtension extension : handling(receipt.contextRecordId)) {
			System.Savepoint before = Database.setSavepoint();
			try {
				extension.received(receipt);
			} catch (Exception failed) {
				Database.rollback(before);
				ErrorLogger.log(failed, 'FormAttachmentExtensions.notify', receipt.submissionId);
				failures.add(failed.getMessage());
			}
		}
		return failures;
	}

	private static List<FormAttachmentExtension> handling(Id recordId) {
		Schema.SObjectType type = recordId.getSObjectType();
		List<FormAttachmentExtension> found = new List<FormAttachmentExtension>();
		for (FormAttachmentExtension extension : installed()) {
			try {
				if (extension.handles(type) == true) {
					found.add(extension);
				}
			} catch (Exception failed) {
				ErrorLogger.log(failed, 'FormAttachmentExtensions.handling', recordId);
			}
		}
		return found;
	}

	private static FormAttachmentExtension resolve(String className) {
		return (FormAttachmentExtension) NamespaceUtil.build(
			className,
			FormAttachmentExtension.class,
			'FormAttachmentExtensions.resolve'
		);
	}
}
