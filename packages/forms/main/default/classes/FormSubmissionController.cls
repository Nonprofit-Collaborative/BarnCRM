/**
 * The Submission panel (C-42a): Process Again for a submission held for review or failed
 * (R-FS2). The panel reads the submission, its answers by question and what it wrote through
 * GraphQL and shapes them in `c/formSubmissionModel` (ADR-0093). Thin by design (plan 9.9);
 * everything runs as the person.
 */
public with sharing class FormSubmissionController {
	private static final String CONTEXT = 'FormSubmissionController';

	/** Processes a held or failed submission again with the person and organization set on it. */
	@AuraEnabled
	public static FormSubmitService.Result processAgain(Id submissionId) {
		try {
			return FormSubmitService.reprocess(submissionId);
		} catch (FormSubmitService.FormException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.processAgain', true);
		}
	}
}
