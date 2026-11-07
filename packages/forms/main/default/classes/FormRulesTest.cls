/**
 * The server applies the form's rules exactly as the pages do (canonical model R-FS1; ADR-0175
 * `0175-forms-module.md`, decision 5). The cases are the shared vectors of `c/formRules`
 * (`formRules/__tests__/data/formVectors.json`), copied below as they are; a Jest test fails when
 * the two copies differ.
 */
@IsTest(testFor='ApexClass:FormRules')
private class FormRulesTest {
	// runs-as: deploying user (pure logic: reads JSON and compares answers, no DML or SOQL)
	// vectors:start
	private static final String VECTORS =
		'{"definition":{"schemaVersion":1,"steps":[{"key":"about","title":"About You","fi' +
		'elds":[{"key":"firstName","label":"First Name","type":"text","required":true},{"' +
		'key":"lastName","label":"Last Name","type":"text","required":true},{"key":"email' +
		'","label":"Email","type":"email","required":true},{"key":"age","label":"Age","ty' +
		'pe":"number","min":14,"max":120},{"key":"role","label":"Role","type":"picklist",' +
		'"options":[{"label":"Volunteer","value":"Volunteer"},{"label":"Donor","value":"D' +
		'onor"}]},{"key":"shirt","label":"Shirt Size","type":"text","maxLength":3,"showWh' +
		'en":{"all":[{"field":"role","op":"equals","value":"volunteer"}]}}]},{"key":"mino' +
		'r","title":"Guardian","showWhen":{"any":[{"field":"age","op":"lessThan","value":' +
		'18}]},"fields":[{"key":"guardian","label":"Guardian Name","type":"text","require' +
		'd":true},{"key":"consent","label":"Guardian Consent","type":"checkbox","required' +
		'":true}]},{"key":"more","title":"More","fields":[{"key":"start","label":"Start D' +
		'ate","type":"date"},{"key":"phone","label":"Phone","type":"phone"},{"key":"why",' +
		'"label":"Why","type":"textarea","showWhen":{"all":[{"field":"shirt","op":"isNotB' +
		'lank"}]}}]}],"records":[{"key":"person","kind":"person"}]},"cases":[{"name":"an ' +
		'adult volunteer","answers":{"firstName":" Pat ","lastName":"Lee","email":"pat@ex' +
		'ample.org","age":"30","role":"Volunteer","shirt":"M","why":"To help","guardian":' +
		'"Not asked"},"visibleSteps":[0,2],"counted":{"firstName":"Pat","lastName":"Lee",' +
		'"email":"pat@example.org","age":30,"role":"Volunteer","shirt":"M","why":"To help' +
		'"},"problems":{}},{"name":"a minor without consent, hidden answers dropped","ans' +
		'wers":{"firstName":"Sam","lastName":"Lee","email":"sam@example.org","age":16,"ro' +
		'le":"Donor","shirt":"XL","why":"Hidden because shirt is hidden","guardian":"Jo L' +
		'ee"},"visibleSteps":[0,1,2],"counted":{"firstName":"Sam","lastName":"Lee","email' +
		'":"sam@example.org","age":16,"role":"Donor","guardian":"Jo Lee","consent":false}' +
		',"problems":{"consent":"mustTick"}},{"name":"every kind of bad answer","answers"' +
		':{"firstName":"  ","lastName":"Lee","email":"not an email","age":"ten","role":"B' +
		'oard","start":"2026-02-30x","phone":"12"},"visibleSteps":[0,2],"counted":{"lastN' +
		'ame":"Lee","email":"not an email","age":"ten","role":"Board","start":"2026-02-30' +
		'x","phone":"12"},"problems":{"firstName":"required","email":"badEmail","age":"ba' +
		'dNumber","role":"notAnOption","start":"badDate","phone":"badPhone"}},{"name":"li' +
		'mits","answers":{"firstName":"Al","lastName":"Lee","email":"al@example.org","age' +
		'":121,"role":"Volunteer","shirt":"XXXL"},"visibleSteps":[0,2],"counted":{"firstN' +
		'ame":"Al","lastName":"Lee","email":"al@example.org","age":121,"role":"Volunteer"' +
		',"shirt":"XXXL"},"problems":{"age":"aboveMax","shirt":"tooLong"}}]}';
	// vectors:end

	private static Map<String, Object> vectors() {
		return (Map<String, Object>) JSON.deserializeUntyped(VECTORS);
	}

	/** Two answer maps as text, so 30 and 30.0 and an Integer and a Decimal compare equal. */
	private static Map<String, String> asText(Object answers) {
		Map<String, String> text = new Map<String, String>();
		Map<String, Object> values = (Map<String, Object>) answers;
		for (String key : values.keySet()) {
			text.put(key, String.valueOf(values.get(key)));
		}
		return text;
	}

	@IsTest
	static void theSharedVectorsHold() {
		Map<String, Object> all = vectors();
		Map<String, Object> definition = (Map<String, Object>) all.get('definition');
		for (Map<String, Object> testCase : FormRules.maps(all.get('cases'))) {
			String name = String.valueOf(testCase.get('name'));
			Map<String, Object> answers = (Map<String, Object>) testCase.get('answers');
			Assert.areEqual(
				asText(testCase.get('counted')),
				asText(FormRules.countedAnswers(definition, answers)),
				name + ': the answers that count'
			);
			Map<String, String> expected = new Map<String, String>();
			Map<String, Object> problems = (Map<String, Object>) testCase.get('problems');
			for (String key : problems.keySet()) {
				expected.put(key, String.valueOf(problems.get(key)));
			}
			Assert.areEqual(expected, FormRules.checkAll(definition, answers), name + ': problems');
		}
	}

	@IsTest
	static void conditionsReadGroupsNumbersDatesAndCheckboxes() {
		Map<String, Object> answers = new Map<String, Object>{
			'n' => 10,
			'd' => '2026-01-01',
			't' => 'b',
			'c' => true
		};
		Assert.isTrue(FormRules.evaluate(null, answers), 'No condition holds');
		Assert.isTrue(
			FormRules.evaluate(
				new Map<String, Object>{ 'field' => 'n', 'op' => 'greaterThan', 'value' => '9' },
				answers
			),
			'Numbers compare as numbers'
		);
		Assert.isTrue(
			FormRules.evaluate(
				new Map<String, Object>{
					'field' => 'd',
					'op' => 'lessThan',
					'value' => '2026-01-02'
				},
				answers
			),
			'Dates compare as dates'
		);
		Assert.isFalse(
			FormRules.evaluate(
				new Map<String, Object>{ 'field' => 't', 'op' => 'greaterThan', 'value' => 'a' },
				answers
			),
			'Text is not ordered'
		);
		Assert.isTrue(
			FormRules.evaluate(
				new Map<String, Object>{ 'field' => 'c', 'op' => 'equals', 'value' => 'TRUE' },
				answers
			),
			'A checkbox reads as true or false'
		);
		Assert.isFalse(
			FormRules.evaluate(new Map<String, Object>{ 'field' => 'c', 'op' => 'nope' }, answers),
			'An unknown test never holds'
		);
		Assert.isFalse(FormRules.evaluate('not a condition', answers), 'Nor does anything else');
	}

	@IsTest
	static void answersAreCheckedByType() {
		Assert.areEqual(
			'belowMin',
			FormRules.checkAnswer(new Map<String, Object>{ 'type' => 'number', 'min' => 5 }, '4')
		);
		Assert.isNull(
			FormRules.checkAnswer(new Map<String, Object>{ 'type' => 'phone' }, '+1 (555) 123-4567')
		);
		Assert.isNull(
			FormRules.checkAnswer(new Map<String, Object>{ 'type' => 'date' }, '2028-02-29')
		);
		Assert.areEqual(
			'badDate',
			FormRules.checkAnswer(new Map<String, Object>{ 'type' => 'date' }, '2026-02-30')
		);
		Assert.areEqual(
			'tooLong',
			FormRules.checkAnswer(
				new Map<String, Object>{ 'type' => 'textarea' },
				'x'.repeat(32769)
			)
		);
		Assert.isFalse(FormRules.isDate('2026-13-01'), 'No thirteenth month');
	}

	@IsTest
	static void textThatIsNotADefinitionIsRefused() {
		for (String text : new List<String>{ '{oops', '[1]' }) {
			try {
				FormRules.parse(text);
				Assert.fail('Refused: ' + text);
			} catch (FormRules.DefinitionException expected) {
				Assert.isTrue(String.isNotBlank(expected.getMessage()), 'With a message');
			}
		}
	}
}
