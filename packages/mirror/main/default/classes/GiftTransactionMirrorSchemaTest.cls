/**
 * What the Gift Transaction mirror reads from the org's describe (X-07, canonical model Section
 * 29C1, R-GT1, R-GT5). The test org has no Nonprofit Cloud, so the present path runs against the
 * stand-ins of `GiftTransactionMirrorSchema.useStandIns` (ADR-0157 decision 9), and the absent
 * path is forced with `absentForTest`, so both are proved on any org.
 */
@IsTest(testFor='ApexClass:GiftTransactionMirrorSchema')
private class GiftTransactionMirrorSchemaTest {
	/** Maria: an administrator who runs the mirror. */
	private static User maria() {
		return TestDataFactory.createUserOnTheRunningUsersProfile(
			'Maria',
			new List<String>{ 'BarnCRM_Admin', 'Giving_Admin', 'Gift_Transaction_Mirror' }
		);
	}

	@IsTest
	static void withoutGiftTransactionNothingIsAvailable() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.absentForTest = true;
			Assert.isNull(GiftTransactionMirrorSchema.objectType(), 'No Gift Transaction (R-GT1).');
			Assert.isFalse(GiftTransactionMirrorSchema.isAvailable());
			Assert.isNull(GiftTransactionMirrorSchema.objectName());
			Assert.isFalse(GiftTransactionMirrorSchema.canRead(GiftTransactionMirrorSchema.read()));
			Assert.isFalse(
				GiftTransactionMirrorSchema.canCreate(
					GiftTransactionMirrorSchema.requiredToCreate()
				)
			);
			Assert.isFalse(
				GiftTransactionMirrorSchema.canUpdate(GiftTransactionMirrorSchema.compared())
			);
			Assert.isTrue(GiftTransactionMirrorSchema.creatable().isEmpty());
			Assert.isFalse(GiftTransactionMirrorSchema.isActiveStatus('Paid'));
			Assert.isFalse(GiftTransactionMirrorSchema.hasOptional('Name'));
			Assert.isFalse(GiftTransactionMirrorSchema.canWriteDesignations());
			Assert.isNull(GiftTransactionMirrorSchema.designationType());
			Assert.isNull(GiftTransactionMirrorSchema.linkObjectName());
		}
	}

	@IsTest
	static void standInsOfTheRightShapeAreAvailable() {
		System.runAs(maria()) {
			GiftTransactionMirrorSchema.useStandIns();
			GiftTransactionMirrorSchema.Names names = GiftTransactionMirrorSchema.names;
			Assert.areEqual(Gift__c.SObjectType, GiftTransactionMirrorSchema.objectType());
			Assert.areEqual(names.transactionObject, GiftTransactionMirrorSchema.objectName());
			Assert.isTrue(GiftTransactionMirrorSchema.canRead(GiftTransactionMirrorSchema.read()));
			Assert.isTrue(
				GiftTransactionMirrorSchema.canCreate(
					GiftTransactionMirrorSchema.requiredToCreate()
				)
			);
			Assert.isTrue(
				GiftTransactionMirrorSchema.canUpdate(GiftTransactionMirrorSchema.compared())
			);

			Set<String> creatable = GiftTransactionMirrorSchema.creatable();
			Assert.isTrue(creatable.containsAll(GiftTransactionMirrorSchema.requiredToCreate()));
			Assert.isFalse(creatable.contains('Name'), 'A numbered name is never written.');
			Assert.isTrue(
				creatable.containsAll(names.createdAlso.keySet()),
				'The stand-in values are written too.'
			);

			Assert.isTrue(GiftTransactionMirrorSchema.isActiveStatus('Received'));
			Assert.isFalse(GiftTransactionMirrorSchema.isActiveStatus('Settled'));
			Assert.isFalse(GiftTransactionMirrorSchema.isActiveStatus(null));
			Assert.isFalse(GiftTransactionMirrorSchema.hasOptional('No_Such_Field__c'));

			Assert.isTrue(GiftTransactionMirrorSchema.canWriteDesignations(), 'R-GT5.');
			Assert.areEqual(Fund__c.SObjectType, GiftTransactionMirrorSchema.designationType());
			Assert.areEqual(
				Gift_Allocation__c.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED)
					.getName(),
				GiftTransactionMirrorSchema.linkObjectName()
			);
		}
	}

	@IsTest
	static void amountsCompareByValue() {
		System.runAs(maria()) {
			Assert.isNull(GiftTransactionMirrorSchema.decimalOf(null));
			Assert.areEqual(12.5, GiftTransactionMirrorSchema.decimalOf(12.5));
			Assert.areEqual(12.5, GiftTransactionMirrorSchema.decimalOf(Double.valueOf('12.5')));
		}
	}
}
