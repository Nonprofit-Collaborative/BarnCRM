/**
 * Published forms for the Forms module's tests. Test only.
 */
@IsTest
public class FormsTestData {
	public static final String ADMIN = 'Forms_Admin';

	/**
	 * A volunteer interest form: a person (first and last name, email, postal code), the
	 * organization they work for, and an affiliation between them, with an under 18 step shown
	 * by a condition.
	 */
	public static Map<String, Object> definition() {
		return new Map<String, Object>{
			'schemaVersion' => 1,
			'steps' => new List<Object>{
				new Map<String, Object>{
					'key' => 'you',
					'title' => 'You',
					'fields' => new List<Object>{
						field('first', 'text', false, 'person', 'FirstName'),
						field('last', 'text', true, 'person', 'LastName'),
						field('email', 'email', false, 'person', 'Email'),
						field('postal', 'text', false, 'person', 'MailingPostalCode'),
						field('employer', 'text', false, 'employer', 'Name'),
						field('role', 'text', false, 'link', 'Role__c'),
						field('age', 'number', false, null, null)
					}
				},
				new Map<String, Object>{
					'key' => 'minor',
					'title' => 'Guardian',
					'showWhen' => new Map<String, Object>{
						'all' => new List<Object>{
							new Map<String, Object>{
								'field' => 'age',
								'op' => 'lessThan',
								'value' => 18
							}
						}
					},
					'fields' => new List<Object>{
						field('guardian', 'text', true, 'person', 'Description')
					}
				}
			},
			'records' => new List<Object>{
				new Map<String, Object>{ 'key' => 'person', 'kind' => 'person' },
				new Map<String, Object>{ 'key' => 'employer', 'kind' => 'organization' },
				new Map<String, Object>{
					'key' => 'link',
					'kind' => 'related',
					'object' => 'Affiliation__c',
					'links' => new Map<String, Object>{
						'Contact__c' => 'person',
						'Organization__c' => 'employer'
					},
					'values' => new Map<String, Object>{ 'Status__c' => 'Current' }
				}
			}
		};
	}

	public static Map<String, Object> field(
		String key,
		String type,
		Boolean required,
		String record,
		String targetField
	) {
		Map<String, Object> field = new Map<String, Object>{
			'key' => key,
			'label' => key.capitalize(),
			'type' => type,
			'required' => required
		};
		if (record != null) {
			field.put(
				'target',
				new Map<String, Object>{ 'record' => record, 'field' => targetField }
			);
		}
		return field;
	}

	/** A published form with this definition, at version 1. */
	public static Form__c published(String name, Map<String, Object> definition) {
		String text = JSON.serialize(definition);
		Form__c form = new Form__c(
			Name = name,
			Status__c = 'Published',
			Definition__c = text,
			Published_Version__c = 1
		);
		insert as user form;
		insert as user new Form_Version__c(Form__c = form.Id, Version__c = 1, Definition__c = text);
		return form;
	}

	/** The volunteer interest form, published. */
	public static Form__c volunteerInterest() {
		return published('Volunteer Interest', definition());
	}

	/** The volunteer interest definition, public, at most `hourlyLimit` sends an hour (C-42b). */
	public static Map<String, Object> publicDefinition(Integer hourlyLimit) {
		Map<String, Object> definition = definition();
		definition.put(
			'public',
			new Map<String, Object>{
				'enabled' => true,
				'minSeconds' => 3,
				'hourlyLimit' => hourlyLimit,
				'confirmation' => 'Thanks for signing up.'
			}
		);
		return definition;
	}

	/** The volunteer interest form, published as a public form with its signing key. */
	public static Form__c publicVolunteerInterest(Integer hourlyLimit) {
		return publicForm(publicDefinition(hourlyLimit));
	}

	/**
	 * The public volunteer interest form with a file question `cv` and save for later (C-42c).
	 */
	public static Form__c publicWithFileAndSaving() {
		Map<String, Object> definition = publicDefinition(50);
		((Map<String, Object>) definition.get('public')).put('saveForLater', true);
		Map<String, Object> firstStep = (Map<String, Object>) ((List<Object>) definition.get(
			'steps'
		))[0];
		((List<Object>) firstStep.get('fields')).add(field('cv', 'file', false, null, null));
		return publicForm(definition);
	}

	/** A form published as a public form with its signing key. */
	public static Form__c publicForm(Map<String, Object> definition) {
		Form__c form = published('Public Volunteer Interest', definition);
		update as user new Form__c(Id = form.Id, Public__c = true);
		FormIntakeService.giveKey(
			[SELECT Id FROM Form_Version__c WHERE Form__c = :form.Id WITH USER_MODE][0].Id
		);
		return form;
	}
}
