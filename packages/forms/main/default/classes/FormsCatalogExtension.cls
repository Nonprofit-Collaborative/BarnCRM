/**
 * Forms' side of Core's form catalog seam (ADR-NEXT `NEXT-event-post-event-survey.md`): lets a
 * module such as Event Management offer the published public forms, read a form's questions and
 * build the address a person with no login opens. Core finds this class by name
 * (`FormCatalogExtensions.EXTENSION_CLASSES`). Reads run with the person's own access.
 */
@NamespaceAccessible
public with sharing class FormsCatalogExtension implements FormCatalogExtension {
	private static final Integer FORM_LIMIT = 200;

	@NamespaceAccessible
	public FormsCatalogExtension() {
		// Built by name from Core (FormCatalogExtensions), so it needs a public constructor.
	}

	/** The published forms that accept public answers, by name. */
	public List<FormCatalogEntry> publicForms() {
		List<FormCatalogEntry> forms = new List<FormCatalogEntry>();
		for (Form__c form : [
			SELECT Id, Name
			FROM Form__c
			WHERE Status__c = 'Published' AND Public__c = TRUE
			WITH USER_MODE
			ORDER BY Name
			LIMIT :FORM_LIMIT
		]) {
			FormCatalogEntry entry = new FormCatalogEntry();
			entry.key = form.Id;
			entry.label = form.Name;
			forms.add(entry);
		}
		return forms;
	}

	/** The questions of the form's working definition in order, each with its type. */
	public List<FormCatalogEntry> questions(Id formId) {
		List<FormCatalogEntry> questions = new List<FormCatalogEntry>();
		for (Form__c form : [
			SELECT Definition__c
			FROM Form__c
			WHERE Id = :formId
			WITH USER_MODE
		]) {
			questions.addAll(questionsIn(form.Definition__c));
		}
		return questions;
	}

	/** The address on the first active Site that has one; null for a form that is not public. */
	public String publicLink(Id formId, Id contextRecordId) {
		Boolean isPublic = false;
		for (Form__c form : [
			SELECT Id
			FROM Form__c
			WHERE Id = :formId AND Status__c = 'Published' AND Public__c = TRUE
			WITH USER_MODE
		]) {
			isPublic = true;
		}
		List<String> urls = FormsSites.activeSiteUrls();
		if (!isPublic || urls.isEmpty()) {
			return null;
		}
		String link = urls[0] + '/FormsPublic?form=' + formId;
		return contextRecordId == null ? link : link + '&record=' + contextRecordId;
	}

	@TestVisible
	private static List<FormCatalogEntry> questionsIn(String definitionJson) {
		List<FormCatalogEntry> questions = new List<FormCatalogEntry>();
		if (String.isBlank(definitionJson)) {
			return questions;
		}
		try {
			Map<String, Object> definition = (Map<String, Object>) JSON.deserializeUntyped(
				definitionJson
			);
			for (Object step : listOf(definition.get('steps'))) {
				for (Object field : listOf(((Map<String, Object>) step).get('fields'))) {
					Map<String, Object> question = (Map<String, Object>) field;
					FormCatalogEntry entry = new FormCatalogEntry();
					entry.key = String.valueOf(question.get('key'));
					Object label = question.get('label');
					entry.label = label == null ? entry.key : String.valueOf(label);
					Object kind = question.get('type');
					entry.kind = kind == null ? 'text' : String.valueOf(kind);
					questions.add(entry);
				}
			}
		} catch (Exception unreadable) {
			return new List<FormCatalogEntry>();
		}
		return questions;
	}

	private static List<Object> listOf(Object value) {
		return value instanceof List<Object> ? (List<Object>) value : new List<Object>();
	}
}
