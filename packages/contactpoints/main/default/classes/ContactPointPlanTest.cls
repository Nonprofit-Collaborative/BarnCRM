/**
 * What a person's Contact Points should be (R-CPL2), worked out from plain values.
 */
@IsTest(testFor='ApexClass:ContactPointPlan')
private class ContactPointPlanTest {
	// runs-as: deploying user (pure logic: plans from plain maps, no DML or SOQL)

	private static final Set<String> ALL_KINDS = new Set<String>{
		ContactPointPlan.EMAIL,
		ContactPointPlan.PHONE,
		ContactPointPlan.ADDRESS
	};

	private static Map<String, ContactPointPlan.Desired> byKey(
		List<ContactPointPlan.Desired> plan
	) {
		Map<String, ContactPointPlan.Desired> result = new Map<String, ContactPointPlan.Desired>();
		for (ContactPointPlan.Desired wanted : plan) {
			result.put(wanted.key(), wanted);
		}
		return result;
	}

	@IsTest
	static void aPersonAccountHoldsEachPersonFieldUnderItsAccountName() {
		Assert.areEqual('PersonEmail', ContactPointPlan.accountFieldFor('Email'));
		Assert.areEqual('PersonHomePhone', ContactPointPlan.accountFieldFor('HomePhone'));
		Assert.areEqual('Phone', ContactPointPlan.accountFieldFor('Phone'));
		Assert.areEqual(
			'Personal_Email__pc',
			ContactPointPlan.accountFieldFor('Personal_Email__c')
		);
		Assert.areEqual(
			ContactPointPlan.personFields().size(),
			ContactPointPlan.accountFields().size(),
			'One account field per person field'
		);
	}

	@IsTest
	static void oneCopyPerDistinctEmailAndPhoneThePreferredOnePrimary() {
		Map<String, Object> person = new Map<String, Object>{
			'Personal_Email__c' => 'ana@home.example',
			'Work_Email__c' => 'ANA@home.example ',
			'Alternate_Email__c' => 'ana@work.example',
			'Email' => 'ana@work.example',
			'HomePhone' => '(555) 010-0001',
			'MobilePhone' => '555 010 0002',
			'Phone' => '555.010.0002'
		};

		Map<String, ContactPointPlan.Desired> plan = byKey(
			ContactPointPlan.plan(person, null, ALL_KINDS)
		);

		Assert.areEqual(4, plan.size(), 'Two emails and two phones: duplicates are one copy');
		ContactPointPlan.Desired personal = plan.get('Email|Personal_Email__c');
		Assert.areEqual('ana@home.example', personal.values.get('EmailAddress'));
		Assert.areEqual(false, personal.values.get('IsPrimary'), 'Not the preferred email');
		Assert.areEqual(
			true,
			plan.get('Email|Alternate_Email__c').values.get('IsPrimary'),
			'The address equal to Email is primary'
		);
		Assert.areEqual('Home', plan.get('Phone|HomePhone').values.get('PhoneType'));
		Assert.areEqual(
			true,
			plan.get('Phone|MobilePhone').values.get('IsPrimary'),
			'Digits compared: the mobile is the preferred phone'
		);
		Assert.isFalse(plan.containsKey('Phone|Phone'), 'The standard phone repeats the mobile');
	}

	@IsTest
	static void onlyCurrentAddressesAndOnlyTheKindsAsked() {
		List<Map<String, Object>> addresses = new List<Map<String, Object>>{
			new Map<String, Object>{
				'Id' => 'a01000000000001',
				'Street__c' => '1 Main St',
				'City__c' => 'Springfield',
				'Postal_Code__c' => '01101',
				'Is_Default__c' => true,
				'Type__c' => 'Home',
				'Status__c' => 'Current'
			},
			new Map<String, Object>{
				'Id' => 'a01000000000002',
				'Street__c' => '9 Old Rd',
				'Status__c' => 'Former'
			},
			new Map<String, Object>{ 'Id' => 'a01000000000003' }
		};

		List<ContactPointPlan.Desired> plan = ContactPointPlan.plan(
			new Map<String, Object>{ 'Email' => 'a@b.example' },
			addresses,
			new Set<String>{ ContactPointPlan.ADDRESS }
		);

		Assert.areEqual(1, plan.size(), 'A former and an empty address are not copied; no email');
		Assert.areEqual('Address|a01000000000001', plan[0].key());
		Assert.areEqual(true, plan[0].values.get('IsDefault'));
		Assert.areEqual('Home', plan[0].values.get('Name'));
		Assert.areEqual('1 main st|springfield|01101', plan[0].matchKey());
	}

	@IsTest
	static void differencesAndMatchKeys() {
		Map<String, Object> wanted = new Map<String, Object>{
			'EmailAddress' => 'a@b.example',
			'IsPrimary' => true
		};
		Assert.isTrue(
			ContactPointPlan.differences(
					wanted,
					new Map<String, Object>{ 'EmailAddress' => 'a@b.example', 'IsPrimary' => true }
				)
				.isEmpty(),
			'Nothing to change'
		);
		Assert.areEqual(
			new Set<String>{ 'EmailAddress' },
			ContactPointPlan.differences(
				wanted,
				new Map<String, Object>{ 'EmailAddress' => 'old@b.example', 'IsPrimary' => true }
			)
		);
		Assert.areEqual(
			new Set<String>{ 'EmailAddress' },
			ContactPointPlan.differences(
				wanted,
				new Map<String, Object>{ 'EmailAddress' => 'A@B.example', 'IsPrimary' => true }
			),
			'A change of case alone reaches the copy'
		);
		Assert.isTrue(ContactPointPlan.changed('Main St', 'main st'), 'Capitals count');
		Assert.isFalse(ContactPointPlan.changed(null, null));
		Assert.isTrue(ContactPointPlan.changed('x', null));
		List<String> compared = new List<String>{ 'Email', 'Phone' };
		Contact lower = new Contact(Email = 'a@b.example');
		Assert.isTrue(
			ContactPointPlan.anyChanged(new Contact(Email = 'A@b.example'), lower, compared),
			'Values differing only in capitals are a change'
		);
		Assert.isFalse(
			ContactPointPlan.anyChanged(new Contact(Email = 'a@b.example'), lower, compared),
			'The same values are not'
		);
		Assert.areEqual(
			'5550100001',
			ContactPointPlan.matchKey(
				ContactPointPlan.PHONE,
				new Map<String, Object>{ 'TelephoneNumber' => '(555) 010-0001' }
			)
		);
		Assert.isNull(
			ContactPointPlan.matchKey(ContactPointPlan.ADDRESS, new Map<String, Object>())
		);
		Assert.isTrue(ContactPointPlan.plan(null, null, ALL_KINDS).isEmpty(), 'No person, no plan');
	}

	@IsTest
	static void hasEmailOrPhoneAgreesWithThePlan() {
		Set<String> values = new Set<String>{ ContactPointPlan.EMAIL, ContactPointPlan.PHONE };
		List<Map<String, Object>> people = new List<Map<String, Object>>{
			new Map<String, Object>(),
			new Map<String, Object>{ 'Email' => '   ' },
			new Map<String, Object>{ 'HomePhone' => 'ext. -' },
			new Map<String, Object>{ 'Work_Email__c' => 'ana@work.example' },
			new Map<String, Object>{ 'OtherPhone' => '(555) 010-0001' }
		};
		for (Map<String, Object> person : people) {
			Assert.areEqual(
				!ContactPointPlan.plan(person, null, values).isEmpty(),
				ContactPointPlan.hasEmailOrPhone(person, values),
				'Same answer as the plan for ' + person
			);
		}
		Assert.isFalse(
			ContactPointPlan.hasEmailOrPhone(
				new Map<String, Object>{ 'Email' => 'ana@home.example' },
				new Set<String>{ ContactPointPlan.PHONE }
			),
			'Only the kinds asked about'
		);
		Assert.isFalse(ContactPointPlan.hasEmailOrPhone(null, values), 'No person');
	}
}
