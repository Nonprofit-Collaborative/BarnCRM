/**
 * The Form Builder (C-42a; ADR-0175 `0175-forms-module.md`, decision 12): a form's draft
 * definition, the objects and fields its answers can be written to, saving the draft and
 * publishing it as a new version. Thin by design (plan 9.9): the page builds and checks the
 * definition with `c/formBuilderModel` and `c/formDefinition`; this class reads it back, checks
 * every target exists in this org and stores it. Everything runs as the person.
 */
public with sharing class FormBuilderController {
	private static final String CONTEXT = 'FormBuilderController';
	private static final Set<String> OWN_OBJECTS = new Set<String>{
		'form__c',
		'form_version__c',
		'form_submission__c',
		'error_log__c'
	};

	/** A form as the builder draws it. */
	public class BuilderView {
		@AuraEnabled
		public String formId;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String status;
		/** The draft definition's JSON; blank for a new form. */
		@AuraEnabled
		public String definition;
		@AuraEnabled
		public Integer publishedVersion;
		/** Whether the person may change the form. */
		@AuraEnabled
		public Boolean canEdit = false;
		/** Whether the published version may be filled in on a Site (C-42b). */
		@AuraEnabled
		public Boolean isPublic = false;
		/** The public form's address on each active Site, when it is public. */
		@AuraEnabled
		public List<String> publicLinks = new List<String>();
	}

	/** An object or a field to choose, with the field's type. */
	public class Choice implements Comparable {
		@AuraEnabled
		public String value;
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String type;

		public Integer compareTo(Object other) {
			return label.compareTo(((Choice) other).label);
		}
	}

	@AuraEnabled
	public static BuilderView getBuilder(Id formId) {
		try {
			return view(formId);
		} catch (FormSubmitService.FormException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getBuilder', true);
		}
	}

	/**
	 * The objects a related record can be: the custom objects the person can create, except the
	 * form's own. People and organizations are the person and organization kinds.
	 */
	@AuraEnabled(cacheable=true)
	public static List<Choice> getObjects() {
		try {
			List<Choice> choices = new List<Choice>();
			for (Schema.SObjectType type : Schema.getGlobalDescribe().values()) {
				Schema.DescribeSObjectResult described = type.getDescribe(
					SObjectDescribeOptions.DEFERRED
				);
				String name = described.getName();
				if (
					described.isCustom() &&
					!described.isCustomSetting() &&
					described.isCreateable() &&
					name.endsWith('__c') &&
					!OWN_OBJECTS.contains(name.toLowerCase())
				) {
					choices.add(choice(name, described.getLabel(), null));
				}
			}
			choices.sort();
			return choices;
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getObjects', false);
		}
	}

	/** The fields of an object the person can write, by label, for answers and links. */
	@AuraEnabled(cacheable=true)
	public static List<Choice> getFields(String objectName) {
		try {
			List<Choice> choices = new List<Choice>();
			Schema.DescribeSObjectResult described = Schema.describeSObjects(
				new List<String>{ objectName },
				SObjectDescribeOptions.DEFERRED
			)[0];
			for (Schema.SObjectField field : described.fields.getMap().values()) {
				Schema.DescribeFieldResult about = field.getDescribe();
				if (about.isCreateable() && about.isAccessible()) {
					choices.add(
						choice(
							about.getName(),
							about.getLabel(),
							String.valueOf(about.getType()).toLowerCase()
						)
					);
				}
			}
			choices.sort();
			return choices;
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.getFields', false);
		}
	}

	/** Saves the draft. The published version, and what is filled in, stays as it was. */
	@AuraEnabled
	public static BuilderView saveDraft(Id formId, String definitionJson) {
		try {
			FormRules.parse(definitionJson);
			update as user new Form__c(Id = formId, Definition__c = definitionJson);
			return view(formId);
		} catch (FormRules.DefinitionException e) {
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			throw UserErrors.wrap(e, CONTEXT + '.saveDraft', true);
		}
	}

	/**
	 * Publishes the draft as the next version: what the Form Runner fills in from now on.
	 * Earlier submissions keep the version they were filled from (R-FM2).
	 */
	@AuraEnabled
	public static BuilderView publish(Id formId, String definitionJson) {
		System.Savepoint before = Database.setSavepoint();
		try {
			Map<String, Object> definition = FormRules.parse(definitionJson);
			if (definition.get('schemaVersion') != 1) {
				throw new FormSubmitService.FormException(
					BarnHelp.text('Forms', 'Forms_Builder_SchemaVersion')
				);
			}
			FormSubmitService.checkTargets(definition);
			Boolean isPublic = FormPublicPolicy.isPublic(definition);
			String refused = isPublic ? FormPublicPolicy.problem(definition) : null;
			if (refused != null) {
				throw new FormSubmitService.FormException(refused);
			}
			BuilderView current = view(formId);
			Integer next = (current.publishedVersion == null ? 0 : current.publishedVersion) + 1;
			Form_Version__c version = new Form_Version__c(
				Form__c = formId,
				Version__c = next,
				Definition__c = definitionJson
			);
			insert as user version;
			FormIntakeService.giveKey(version.Id);
			update as user new Form__c(
				Id = formId,
				Definition__c = definitionJson,
				Status__c = 'Published',
				Published_Version__c = next,
				Public__c = isPublic
			);
			return view(formId);
		} catch (FormRules.DefinitionException e) {
			Database.rollback(before);
			throw UserErrors.message(e.getMessage());
		} catch (FormSubmitService.FormException e) {
			Database.rollback(before);
			throw UserErrors.message(e.getMessage());
		} catch (Exception e) {
			Database.rollback(before);
			throw UserErrors.wrap(e, CONTEXT + '.publish', true);
		}
	}

	private static BuilderView view(Id formId) {
		List<Form__c> forms = [
			SELECT Id, Name, Status__c, Definition__c, Published_Version__c, Public__c
			FROM Form__c
			WHERE Id = :formId
			WITH USER_MODE
		];
		if (forms.isEmpty()) {
			throw new FormSubmitService.FormException(
				BarnHelp.text('Forms', 'Forms_Builder_NotFound')
			);
		}
		Form__c form = forms[0];
		BuilderView result = new BuilderView();
		result.formId = form.Id;
		result.name = form.Name;
		result.status = form.Status__c;
		result.definition = form.Definition__c;
		result.publishedVersion = form.Published_Version__c == null
			? null
			: form.Published_Version__c.intValue();
		result.canEdit =
			Schema.SObjectType.Form__c.isUpdateable() &&
			Schema.SObjectType.Form_Version__c.isCreateable();
		result.isPublic = form.Public__c == true && form.Status__c == 'Published';
		if (result.isPublic) {
			for (String base : FormsSites.activeSiteUrls()) {
				result.publicLinks.add(base + '/FormsPublic?form=' + form.Id);
			}
		}
		return result;
	}

	private static Choice choice(String value, String label, String type) {
		Choice result = new Choice();
		result.value = value;
		result.label = label;
		result.type = type;
		return result;
	}
}
