/**
 * Quick gift entry (G-03).
 *
 * Serves the `quickGiftEntry` component: the defaults a new gift starts from, and the save
 * of one gift with at most one allocation, and with the tribute it honors and the employee
 * gift it matches when the person entered them (people-giving-23). Everything a gift needs
 * beyond what this form collects (the derived household, the default allocation, the
 * auto-number name, the other side of a matching pair) is the Giving domain's work, so this
 * class stays a thin, validating entry point.
 *
 * Errors the person can act on are returned in the typed result and rendered beside the
 * field that caused them. Anything unexpected is logged to the Error Log and reported as
 * one plain sentence, because the person entering gifts at an event cannot act on a stack
 * trace (plan Section 2.3).
 */
public with sharing class QuickGiftEntryController {
	private static final String STATUS_RECEIVED = 'Received';
	private static final String TYPE_IN_KIND = 'In-kind';
	private static final String CONTEXT = 'QuickGiftEntryController';
	private static final String KIND_PERSON = 'person';
	private static final String KIND_ORGANIZATION = 'organization';
	/** How many employee gifts the "Matches an Employee's Gift" list offers, newest first. */
	private static final Integer MATCHABLE_GIFT_LIMIT = 50;

	/**
	 * The values a new gift starts from: today's date, the org's default fund and appeal,
	 * the gift types, the tribute types, the field labels the form borrows from the org's
	 * describe, and whether people in this org are accounts rather than contacts.
	 */
	@AuraEnabled(cacheable=true)
	public static EntryDefaults getDefaults() {
		try {
			EntryDefaults defaults = new EntryDefaults();
			defaults.giftDate = Date.today();
			defaults.giftTypes = giftTypeOptions();
			defaults.tributeTypes = picklistOptions(Tribute__c.Type__c.getDescribe());
			defaults.fieldLabels = fieldLabels();
			defaults.hasPersonAccounts = OrgShapeDetector.hasPersonAccounts();
			Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
			applyDefaultFund(defaults, settings);
			applyDefaultAppeal(defaults, settings);
			return defaults;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getDefaults');
			throw UserErrors.message(Label.Giving_QuickGiftEntry_ErrorLoadDefaults);
		}
	}

	/**
	 * Whether a donor named by id is a person or an organization, so a form opened for a known
	 * donor (a record page, the Enter a Gift action, or the Quick Gift Entry tab with
	 * c__donorId) starts on the right side of the Person and Organization choice. A contact is
	 * a person; an account is a person only where people are accounts and this one is a person
	 * account. Null for an id that names neither.
	 */
	@AuraEnabled(cacheable=true)
	public static String getDonorKind(String donorId) {
		try {
			if (asId(donorId, Contact.SObjectType) != null) {
				return KIND_PERSON;
			}
			Id accountId = asId(donorId, Account.SObjectType);
			if (accountId == null) {
				return null;
			}
			return OrgShapeDetector.hasPersonAccounts() && isPersonAccount(accountId)
				? KIND_PERSON
				: KIND_ORGANIZATION;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getDonorKind');
			throw UserErrors.message(Label.Giving_QuickGiftEntry_ErrorLoadDefaults);
		}
	}

	/**
	 * The gifts an organization's gift can match (people-giving-23): recent gifts of money from
	 * people whose Employer is this organization, not matched yet, and not refunds. The gift
	 * trigger still checks the pair when the gift is saved (R-G11); this list only narrows the
	 * choice to the gifts that can pass.
	 */
	@AuraEnabled
	public static List<GiftChoice> getMatchableGifts(String organizationId) {
		Id employerId = asId(organizationId, Account.SObjectType);
		List<GiftChoice> choices = new List<GiftChoice>();
		if (employerId == null) {
			return choices;
		}
		try {
			for (Gift__c gift : [
				SELECT
					Id,
					Name,
					Amount__c,
					Gift_Date__c,
					Donor_Contact__r.Name,
					Donor_Account__r.Name
				FROM Gift__c
				WHERE
					(Donor_Contact__r.Employer__c = :employerId
					OR Donor_Account__r.Employer__c = :employerId)
					AND Matched_Gift__c = NULL
					AND Original_Gift__c = NULL
					AND Amount__c > 0
				WITH USER_MODE
				ORDER BY Gift_Date__c DESC, Name DESC
				LIMIT :MATCHABLE_GIFT_LIMIT
			]) {
				choices.add(new GiftChoice(gift));
			}
			return choices;
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getMatchableGifts');
			throw UserErrors.message(Label.Giving_QuickGiftEntry_ErrorUnexpected);
		}
	}

	/**
	 * The scheduled payments the donor still owes, for the "Pays a scheduled payment" list
	 * (R-DM8), with the one suggestion chosen in advance only when it is the only one. Not
	 * cacheable: a payment paid a minute ago must not be offered again.
	 */
	@AuraEnabled
	public static GiftEntryPayments.Choices getPaymentChoices(
		String donorContactId,
		String donorAccountId,
		Date giftDate,
		Decimal amount
	) {
		try {
			GiftEntryPayments.Request request = new GiftEntryPayments.Request(
				'gift',
				asId(donorContactId, Contact.SObjectType),
				asId(donorAccountId, Account.SObjectType),
				giftDate,
				amount
			);
			return GiftEntryPayments.forRequests(new List<GiftEntryPayments.Request>{ request })
				.get('gift');
		} catch (Exception e) {
			ErrorLogger.log(e, CONTEXT + '.getPaymentChoices');
			throw UserErrors.message(Label.Giving_GiftEntryPays_ErrorLoad);
		}
	}

	/**
	 * Saves one gift and, in the same transaction, what came with it: the fund chosen for its
	 * single allocation, the tribute it honors and the employee gift it matches. Returns a
	 * result the component can render: the saved gift's name and id, or the errors that
	 * stopped it. A failure in any part undoes the whole save, so a gift never lands without
	 * the tribute the person typed for it.
	 */
	@AuraEnabled
	public static SaveResult saveGift(GiftInput input) {
		SaveResult result = new SaveResult();
		if (input == null) {
			result.formError = Label.Giving_QuickGiftEntry_ErrorNoInput;
			return result;
		}
		result.fieldErrors = input.validate();
		if (!result.fieldErrors.isEmpty()) {
			return result;
		}
		Savepoint beforeSave = Database.setSavepoint();
		try {
			Gift__c gift = input.toGift();
			if (!applyChosenPayment(gift, input)) {
				result.fieldErrors.add(
					new FieldError('installmentId', Label.Giving_GiftEntryPays_ErrorNotOpen)
				);
				return result;
			}
			Boolean split = input.isSplit();
			insertGift(gift, split);
			Tribute__c tribute = input.toTribute(gift.Id);
			if (tribute != null) {
				Database.insert(tribute, true, AccessLevel.USER_MODE);
			}
			Boolean applyChosenFundWasApplied = true;
			if (split) {
				Database.insert(input.toAllocations(gift.Id), true, AccessLevel.USER_MODE);
			} else {
				applyChosenFundWasApplied = applyChosenFund(
					gift,
					asId(input.fundId, Fund__c.SObjectType)
				);
			}
			result.success = true;
			result.giftId = gift.Id;
			result.giftName = nameOf(gift.Id);
			result.fundNotApplied = !applyChosenFundWasApplied;
			return result;
		} catch (DmlException e) {
			Database.rollback(beforeSave);
			ErrorLogger.log(e, CONTEXT + '.saveGift');
			result.formError = e.getNumDml() > 0
				? e.getDmlMessage(0)
				: Label.Giving_QuickGiftEntry_ErrorUnexpected;
			return result;
		} catch (Exception e) {
			Database.rollback(beforeSave);
			ErrorLogger.log(e, CONTEXT + '.saveGift');
			result.formError = Label.Giving_QuickGiftEntry_ErrorUnexpected;
			return result;
		}
	}

	/**
	 * A gift split across funds (people-giving-16) is inserted without the default allocation,
	 * because its own allocations follow in the same transaction and must total the gift alone
	 * (R-GA1), the way the import saves a split. The caller's suppression is put back after.
	 */
	private static void insertGift(Gift__c gift, Boolean split) {
		Boolean callerSuppression = GiftService.suppressDefaultAllocations;
		try {
			GiftService.suppressDefaultAllocations = split || callerSuppression;
			Database.insert(gift, true, AccessLevel.USER_MODE);
		} finally {
			GiftService.suppressDefaultAllocations = callerSuppression;
		}
	}

	/**
	 * The gift is inserted first, so the Giving domain has already given it its default
	 * allocation. When the person chose a fund, that one allocation is pointed at their
	 * choice rather than a second one being added, so the allocations still total the
	 * gift (canonical model R-GA1).
	 *
	 * Returns false when the choice could not be applied, which happens only when the gift
	 * already carries a split across several funds. The gift is saved either way, and the
	 * component says so rather than reporting a designation the gift does not have.
	 */
	private static Boolean applyChosenFund(Gift__c gift, Id fundId) {
		if (fundId == null) {
			return true;
		}
		return !GiftService.applyChosenFunds(
				new List<Gift__c>{ gift },
				new Map<Id, Id>{ gift.Id => fundId }
			)
			.contains(gift.Id);
	}

	/**
	 * R-DM8: the payment the person chose is checked again now, because it can have been paid
	 * or its pledge closed since the list was drawn. The gift then carries it and its pledge,
	 * and the gift triggers apply it (R-DM6). Returns false when the choice no longer stands.
	 */
	private static Boolean applyChosenPayment(Gift__c gift, GiftInput input) {
		Id chosen = asId(input.installmentId, Installment__c.SObjectType);
		if (chosen == null) {
			return true;
		}
		Installment__c installment = GiftEntryPayments.confirm(
				new List<GiftEntryPayments.Request>{
					new GiftEntryPayments.Request(
						'gift',
						gift.Donor_Contact__c,
						gift.Donor_Account__c,
						gift.Gift_Date__c,
						gift.Amount__c
					)
				},
				new Map<String, Id>{ 'gift' => chosen }
			)
			.get('gift');
		if (installment == null) {
			return false;
		}
		gift.Installment__c = installment.Id;
		gift.Commitment__c = installment.Commitment__c;
		return true;
	}

	private static String nameOf(Id giftId) {
		List<Gift__c> saved = GiftSelector.selectById(new Set<Id>{ giftId });
		return saved.isEmpty() ? null : saved[0].Name;
	}

	private static Boolean isPersonAccount(Id accountId) {
		// Dynamic, because the person account flag exists only where person accounts are turned
		// on, and BarnCRM runs on orgs without them (ADR-0013).
		List<SObject> rows = Database.queryWithBinds(
			PERSON_ACCOUNT_QUERY,
			new Map<String, Object>{ 'accountId' => accountId },
			AccessLevel.USER_MODE
		);
		return !rows.isEmpty() && rows[0].get(PERSON_ACCOUNT_FIELD) == true;
	}

	private static final String PERSON_ACCOUNT_QUERY = 'SELECT IsPersonAccount FROM Account WHERE Id = :accountId LIMIT 1'; // detection-only: run only after the describe found person accounts
	private static final String PERSON_ACCOUNT_FIELD = 'IsPersonAccount'; // detection-only: read from the row the person account query returned

	/**
	 * The field labels the tribute and matching sections show, from the org's own describe
	 * rather than custom labels, keyed by the field's name without any namespace.
	 */
	private static Map<String, String> fieldLabels() {
		return new Map<String, String>{
			'tributeType' => Tribute__c.Type__c.getDescribe().getLabel(),
			'honoreeContact' => Tribute__c.Honoree_Contact__c.getDescribe().getLabel(),
			'honoreeAccount' => Tribute__c.Honoree_Account__c.getDescribe().getLabel(),
			'honoreeName' => Tribute__c.Honoree_Name__c.getDescribe().getLabel(),
			'notifyContact' => Tribute__c.Notification_Recipient_Contact__c.getDescribe()
				.getLabel(),
			'notifyAccount' => Tribute__c.Notification_Recipient_Account__c.getDescribe()
				.getLabel(),
			'notifyName' => Tribute__c.Notification_Recipient_Name__c.getDescribe().getLabel(),
			'matchedGift' => Gift__c.Matched_Gift__c.getDescribe().getLabel()
		};
	}

	/**
	 * The form shows the fund the gift will actually land in. Where the settings key names
	 * no usable fund, the save falls back to the fund carrying the default flag (R-F4,
	 * R-GA2), so the form asks the domain the same question rather than showing an empty
	 * Fund box and then designating the gift somewhere the person never saw.
	 */
	private static void applyDefaultFund(EntryDefaults defaults, Giving_Settings__c settings) {
		Id fundId = asId(settings.Default_Fund__c, Fund__c.SObjectType);
		if (fundId == null) {
			fundId = GiftService.resolveDefaultFundId();
		}
		if (fundId == null) {
			return;
		}
		for (Fund__c fund : FundSelector.selectById(new Set<Id>{ fundId })) {
			if (fund.Active__c) {
				defaults.defaultFundId = fund.Id;
				defaults.defaultFundName = fund.Name;
			}
		}
	}

	private static void applyDefaultAppeal(EntryDefaults defaults, Giving_Settings__c settings) {
		Id appealId = asId(settings.Default_Appeal__c, Appeal__c.SObjectType);
		if (appealId == null) {
			return;
		}
		for (Appeal__c appeal : AppealSelector.selectById(new Set<Id>{ appealId })) {
			if (appeal.Active__c) {
				defaults.defaultAppealId = appeal.Id;
				defaults.defaultAppealName = appeal.Name;
			}
		}
	}

	/**
	 * A settings key holds an identifier as text (ADR-0014), and the record it names can
	 * have been deleted since. Anything that is not a live identifier of the expected kind
	 * is treated as no default rather than as an error, so a stale key never blocks entry.
	 */
	private static Id asId(String value, Schema.SObjectType expected) {
		if (String.isBlank(value)) {
			return null;
		}
		try {
			Id parsed = Id.valueOf(value.trim());
			return parsed.getSobjectType() == expected ? parsed : null;
		} catch (System.StringException e) {
			return null;
		}
	}

	/** A person picked for a tribute is a contact, or an account where people are accounts. */
	private static Id asPersonId(String value) {
		Id contactId = asId(value, Contact.SObjectType);
		return contactId != null ? contactId : asId(value, Account.SObjectType);
	}

	private static List<PicklistOption> giftTypeOptions() {
		return picklistOptions(Gift__c.Type__c.getDescribe());
	}

	private static List<PicklistOption> picklistOptions(Schema.DescribeFieldResult field) {
		List<PicklistOption> options = new List<PicklistOption>();
		for (Schema.PicklistEntry entry : field.getPicklistValues()) {
			if (entry.isActive()) {
				options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
			}
		}
		return options;
	}

	private static Set<String> optionValues(List<PicklistOption> options) {
		Set<String> values = new Set<String>();
		for (PicklistOption option : options) {
			values.add(option.value);
		}
		return values;
	}

	/** One choice in the "How it arrived" list. */
	public class PicklistOption {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String value;

		public PicklistOption(String label, String value) {
			this.label = label;
			this.value = value;
		}
	}

	/** One employee gift an organization's gift can match. */
	public class GiftChoice {
		@AuraEnabled
		public String id;
		@AuraEnabled
		public String name;
		@AuraEnabled
		public String donorName;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public Date giftDate;

		public GiftChoice(Gift__c gift) {
			this.id = gift.Id;
			this.name = gift.Name;
			this.amount = gift.Amount__c;
			this.giftDate = gift.Gift_Date__c;
			this.donorName = gift.Donor_Contact__r != null
				? gift.Donor_Contact__r.Name
				: (gift.Donor_Account__r != null ? gift.Donor_Account__r.Name : null);
		}
	}

	/** What a new gift starts from. */
	public class EntryDefaults {
		@AuraEnabled
		public Date giftDate;
		@AuraEnabled
		public Boolean hasPersonAccounts = false;
		@AuraEnabled
		public String defaultFundId;
		@AuraEnabled
		public String defaultFundName;
		@AuraEnabled
		public String defaultAppealId;
		@AuraEnabled
		public String defaultAppealName;
		@AuraEnabled
		public List<PicklistOption> giftTypes = new List<PicklistOption>();
		@AuraEnabled
		public List<PicklistOption> tributeTypes = new List<PicklistOption>();
		@AuraEnabled
		public Map<String, String> fieldLabels = new Map<String, String>();
	}

	/** One message the component shows beside one field. */
	public class FieldError {
		@AuraEnabled
		public String field;
		@AuraEnabled
		public String message;

		public FieldError(String field, String message) {
			this.field = field;
			this.message = message;
		}
	}

	/** One fund and its share of a split gift. */
	public class AllocationInput {
		@AuraEnabled
		public String fundId;
		@AuraEnabled
		public Decimal amount;
	}

	/** What came of a save. */
	public class SaveResult {
		@AuraEnabled
		public Boolean success = false;
		@AuraEnabled
		public String giftId;
		@AuraEnabled
		public String giftName;
		@AuraEnabled
		public String formError;
		@AuraEnabled
		public Boolean fundNotApplied = false;
		@AuraEnabled
		public List<FieldError> fieldErrors = new List<FieldError>();
	}

	/**
	 * The gift the person typed. Every value arrives as it was entered and is validated
	 * here, so no other class has to trust the browser.
	 */
	public class GiftInput {
		@AuraEnabled
		public String donorContactId;
		@AuraEnabled
		public String donorAccountId;
		@AuraEnabled
		public Decimal amount;
		@AuraEnabled
		public Date giftDate;
		@AuraEnabled
		public String giftType;
		@AuraEnabled
		public String appealId;
		@AuraEnabled
		public String fundId;
		@AuraEnabled
		public String paymentReference;
		@AuraEnabled
		public String inKindDescription;
		@AuraEnabled
		public Decimal fairMarketValue;
		/** The scheduled payment this gift pays, or empty for a gift on its own (R-DM8). */
		@AuraEnabled
		public String installmentId;
		/** In honor of or In memory of; empty when the gift honors nobody. */
		@AuraEnabled
		public String tributeType;
		/** The person honored, a contact or (where people are accounts) an account. */
		@AuraEnabled
		public String honoreeId;
		/** The person honored, by name, when they are not a record. */
		@AuraEnabled
		public String honoreeName;
		/** Who is told about the tribute, a contact or (where people are accounts) an account. */
		@AuraEnabled
		public String notifyId;
		/** Who is told about the tribute, by name, when they are not a record. */
		@AuraEnabled
		public String notifyName;
		/** The employee's gift an organization's gift matches (R-G11). */
		@AuraEnabled
		public String matchedGiftId;
		/** The funds the gift is split across, two or more; otherwise empty and fundId applies. */
		@AuraEnabled
		public List<AllocationInput> allocations;

		public Boolean isSplit() {
			return this.allocations != null && this.allocations.size() > 1;
		}

		/** One allocation row per fund in the split, all inserted with the gift. */
		public List<Gift_Allocation__c> toAllocations(Id giftId) {
			List<Gift_Allocation__c> rows = new List<Gift_Allocation__c>();
			for (AllocationInput entry : this.allocations) {
				rows.add(
					new Gift_Allocation__c(
						Gift__c = giftId,
						Fund__c = asId(entry.fundId, Fund__c.SObjectType),
						Amount__c = entry.amount
					)
				);
			}
			return rows;
		}

		/**
		 * A split is for a gift of money: every row names its own fund and an amount above
		 * zero, and the rows add up to the gift's amount exactly (R-GA1).
		 */
		private void validateSplit(List<FieldError> errors) {
			if (!isSplit()) {
				return;
			}
			Boolean fits = !isInKind() && this.amount != null;
			Set<Id> funds = new Set<Id>();
			Decimal total = 0;
			for (AllocationInput entry : this.allocations) {
				Id fundId = entry == null ? null : asId(entry.fundId, Fund__c.SObjectType);
				if (
					fundId == null ||
					!funds.add(fundId) ||
					entry.amount == null ||
					entry.amount <= 0
				) {
					fits = false;
					break;
				}
				total += entry.amount;
			}
			if (!fits || total != this.amount) {
				errors.add(
					new FieldError(
						'allocations',
						BarnHelp.text('Giving', 'Giving_QuickGiftEntry_ErrorSplit')
					)
				);
			}
		}

		public List<FieldError> validate() {
			List<FieldError> errors = new List<FieldError>();
			validateDonor(errors);
			validateAmountOrGoods(errors);
			if (this.giftDate == null) {
				errors.add(
					new FieldError('giftDate', Label.Giving_QuickGiftEntry_ErrorDateRequired)
				);
			}
			validateType(errors);
			if (
				String.isNotBlank(this.appealId) &&
				asId(this.appealId, Appeal__c.SObjectType) == null
			) {
				errors.add(
					new FieldError('appealId', Label.Giving_QuickGiftEntry_ErrorAppealUnavailable)
				);
			}
			if (String.isNotBlank(this.fundId) && asId(this.fundId, Fund__c.SObjectType) == null) {
				errors.add(
					new FieldError('fundId', Label.Giving_QuickGiftEntry_ErrorFundUnavailable)
				);
			}
			validatePayment(errors);
			validateTribute(errors);
			validateMatch(errors);
			validateSplit(errors);
			return errors;
		}

		/**
		 * A gift is money or goods, never both (R-G12, ADR-0030). A gift of money needs an amount
		 * above zero; a gift of goods has no amount at all and needs the description that its
		 * receipt will print. The fair market value is optional, because a donor can hand over a
		 * carload of furniture before anybody has put a figure on it, but it is never negative.
		 */
		private void validateAmountOrGoods(List<FieldError> errors) {
			if (isInKind()) {
				if (String.isBlank(this.inKindDescription)) {
					errors.add(
						new FieldError(
							'inKindDescription',
							Label.Giving_QuickGiftEntry_ErrorInKindDescriptionRequired
						)
					);
				}
				if (this.fairMarketValue != null && this.fairMarketValue < 0) {
					errors.add(
						new FieldError(
							'fairMarketValue',
							Label.Giving_QuickGiftEntry_ErrorFairMarketValueNegative
						)
					);
				}
				return;
			}
			if (this.amount == null || this.amount <= 0) {
				errors.add(
					new FieldError('amount', Label.Giving_QuickGiftEntry_ErrorAmountRequired)
				);
			}
		}

		/** A gift of goods pays no scheduled payment (R-DM8), and the choice must be one. */
		private void validatePayment(List<FieldError> errors) {
			if (String.isBlank(this.installmentId)) {
				return;
			}
			if (isInKind()) {
				errors.add(new FieldError('installmentId', Label.Giving_GiftEntryPays_ErrorInKind));
			} else if (asId(this.installmentId, Installment__c.SObjectType) == null) {
				errors.add(
					new FieldError('installmentId', Label.Giving_GiftEntryPays_ErrorNotOpen)
				);
			}
		}

		/**
		 * A tribute needs its type and the person honored, as a record or a name (the Tribute
		 * validation rules say the same on save). Nothing typed in the section means no tribute.
		 */
		private void validateTribute(List<FieldError> errors) {
			if (!hasTribute()) {
				return;
			}
			if (
				String.isBlank(this.tributeType) ||
				!optionValues(picklistOptions(Tribute__c.Type__c.getDescribe()))
					.contains(this.tributeType)
			) {
				errors.add(
					new FieldError(
						'tributeType',
						BarnHelp.text('Giving', 'Giving_QuickGiftEntry_ErrorTributeType')
					)
				);
			}
			if (asPersonId(this.honoreeId) == null && String.isBlank(this.honoreeName)) {
				errors.add(new FieldError('honoree', Label.Giving_Tribute_HonoreeRequired));
			}
		}

		/** Only an organization's gift matches an employee's (R-G11). */
		private void validateMatch(List<FieldError> errors) {
			if (String.isBlank(this.matchedGiftId)) {
				return;
			}
			if (
				asId(this.matchedGiftId, Gift__c.SObjectType) == null ||
				asId(this.donorAccountId, Account.SObjectType) == null
			) {
				errors.add(
					new FieldError(
						'matchedGiftId',
						BarnHelp.text('Giving', 'Giving_QuickGiftEntry_ErrorMatchedGift')
					)
				);
			}
		}

		@TestVisible
		private Boolean isInKind() {
			return TYPE_IN_KIND.equalsIgnoreCase(this.giftType);
		}

		@TestVisible
		private Boolean hasTribute() {
			return String.isNotBlank(this.tributeType) ||
				String.isNotBlank(this.honoreeId) ||
				String.isNotBlank(this.honoreeName) ||
				String.isNotBlank(this.notifyId) ||
				String.isNotBlank(this.notifyName);
		}

		private void validateDonor(List<FieldError> errors) {
			Boolean hasContact =
				String.isNotBlank(this.donorContactId) &&
				asId(this.donorContactId, Contact.SObjectType) != null;
			Boolean hasAccount =
				String.isNotBlank(this.donorAccountId) &&
				asId(this.donorAccountId, Account.SObjectType) != null;
			if (hasContact && hasAccount) {
				errors.add(
					new FieldError(
						'donor',
						BarnHelp.text('Giving', 'Giving_GiftEntry_ErrorOneDonor')
					)
				);
			} else if (!hasContact && !hasAccount) {
				errors.add(new FieldError('donor', Label.Giving_QuickGiftEntry_ErrorDonorRequired));
			}
		}

		private void validateType(List<FieldError> errors) {
			if (String.isBlank(this.giftType)) {
				errors.add(
					new FieldError('giftType', Label.Giving_QuickGiftEntry_ErrorTypeRequired)
				);
				return;
			}
			if (!optionValues(giftTypeOptions()).contains(this.giftType)) {
				errors.add(
					new FieldError('giftType', Label.Giving_QuickGiftEntry_ErrorTypeInvalid)
				);
			}
		}

		/**
		 * An in-kind gift is saved with an amount of zero and its worth on Fair Market Value, and
		 * a gift that is not in-kind carries neither of the in-kind attributes, whatever the
		 * browser sent: a description left behind by somebody switching the type back and forth
		 * would otherwise read later as a gift of goods (R-G12).
		 */
		public Gift__c toGift() {
			Boolean inKind = isInKind();
			return new Gift__c(
				Donor_Contact__c = asId(this.donorContactId, Contact.SObjectType),
				Donor_Account__c = asId(this.donorAccountId, Account.SObjectType),
				Gift_Date__c = this.giftDate,
				Amount__c = inKind ? 0 : this.amount,
				Type__c = this.giftType,
				Status__c = STATUS_RECEIVED,
				Appeal__c = asId(this.appealId, Appeal__c.SObjectType),
				Payment_Reference__c = this.paymentReference,
				In_Kind_Description__c = inKind ? this.inKindDescription : null,
				Fair_Market_Value__c = inKind ? this.fairMarketValue : null,
				Matched_Gift__c = asId(this.matchedGiftId, Gift__c.SObjectType)
			);
		}

		/**
		 * The tribute the person typed for this gift, or null when they typed none. A person
		 * picked is a contact, or an account where people are accounts; one typed by name is
		 * kept as the name.
		 */
		public Tribute__c toTribute(Id giftId) {
			if (!hasTribute()) {
				return null;
			}
			Id honoree = asPersonId(this.honoreeId);
			Id notify = asPersonId(this.notifyId);
			return new Tribute__c(
				Gift__c = giftId,
				Type__c = this.tributeType,
				Honoree_Contact__c = honoree != null &&
					honoree.getSobjectType() == Contact.SObjectType
					? honoree
					: null,
				Honoree_Account__c = honoree != null &&
					honoree.getSobjectType() == Account.SObjectType
					? honoree
					: null,
				Honoree_Name__c = honoree == null ? this.honoreeName : null,
				Notification_Recipient_Contact__c = notify != null &&
					notify.getSobjectType() == Contact.SObjectType
					? notify
					: null,
				Notification_Recipient_Account__c = notify != null &&
					notify.getSobjectType() == Account.SObjectType
					? notify
					: null,
				Notification_Recipient_Name__c = notify == null ? this.notifyName : null
			);
		}
	}
}
