/**
 * One import row's gift as read from the file, before anything is looked up (canonical model
 * R-GI1 to R-GI4). Reading is kept apart from saving so the dry run and the commit make the
 * same decisions from the same values (R-GI8).
 *
 * The values arrive grouped by entity, as Core's importer hands them over (R-IR6): `Gift`,
 * `Allocation`, `SoftCredit` and `Tribute`, each attribute to its text. Attribute names are
 * matched ignoring case, because a template is typed by a person.
 */
public with sharing class GiftImportRow {
	public static final String ENTITY_GIFT = 'Gift';
	public static final String ENTITY_ALLOCATION = 'Allocation';
	public static final String ENTITY_SOFT_CREDIT = 'SoftCredit';
	public static final String ENTITY_TRIBUTE = 'Tribute';

	public static final String ATTRIBUTE_DONOR = 'Donor';
	public static final String ATTRIBUTE_APPEAL = 'Appeal';
	public static final String ATTRIBUTE_FUND = 'Fund';
	public static final String ATTRIBUTE_AMOUNT = 'Amount';
	public static final String ATTRIBUTE_PERCENT = 'Percent';

	public static final String DONOR_CONTACT_1 = 'Contact1';
	public static final String DONOR_ORGANIZATION = 'Organization';
	public static final String DONOR_HOUSEHOLD = 'Household';

	/** The payment method whose gifts carry no amount (R-G12). */
	public static final String TYPE_IN_KIND = 'In-kind';

	/** The most parts a split can have in one row. */
	public static final Integer MAX_PARTS = 5;

	/** The gift attributes the package writes itself, never a file (R-GI3). */
	private static final Set<String> WRITTEN_BY_THE_PACKAGE = new Set<String>{
		'household__c',
		'status__c',
		'receipt_number__c',
		'tribute__c',
		'commitment__c',
		'installment__c',
		'original_gift__c',
		'matched_gift__c',
		'created_by_import_batch__c',
		'sample_data__c',
		'donor_contact__c',
		'donor_account__c',
		'appeal__c',
		'acknowledgment_status__c',
		'acknowledgment_date__c',
		'refund_reason__c'
	};

	/** The words payment files use for a payment method, beyond the picklist's own values. */
	private static final Map<String, String> TYPE_ALIASES = new Map<String, String>{
		'credit card' => 'Card',
		'debit card' => 'Card',
		'credit' => 'Card',
		'cheque' => 'Check',
		'bank transfer' => 'ACH',
		'direct debit' => 'ACH',
		'eft' => 'ACH',
		'wire' => 'ACH',
		'wire transfer' => 'ACH',
		'in kind' => 'In-kind',
		'inkind' => 'In-kind',
		'gift in kind' => 'In-kind',
		'securities' => 'Stock',
		'shares' => 'Stock'
	};

	private static final Pattern ISO_DATE = Pattern.compile(
		'^(\\d{4})-(\\d{1,2})-(\\d{1,2})(?:[ T].*)?$'
	);

	/** One part of a split, or the single fund of a gift that is not split. */
	public class Part {
		public Integer index;
		public String fund;
		public Decimal amount;
		public Decimal percent;
		public Id fundId;
	}

	public Import_Row__c row;
	/** Why the row cannot become a gift, or null. */
	public String error;
	/** False when the row names nothing a gift is made from (R-GI1). */
	public Boolean carriesGift = false;
	public Decimal amount;
	/** The amount as the file had it, readable or not, for the control total (R-GI8). */
	public Decimal readableAmount;
	public Date giftDate;
	public String externalId;
	public String appeal;
	public Id appealId;
	public String donorChoice;
	/** The single fund named with `Allocation.Fund`, or null. */
	public Part singleFund;
	/** The numbered parts of a split, in order. */
	public List<Part> parts = new List<Part>();
	/** The other gift attributes, by field, as values of the field's own type. */
	public Map<Schema.SObjectField, Object> values = new Map<Schema.SObjectField, Object>();
	/** Gift attributes the file names that are no field the import may write. */
	public Set<String> notLoaded = new Set<String>();

	// What the processor decides for the row (R-GI2, R-DM1).
	public Id donorContactId;
	public Id donorAccountId;
	/** The gift this row made, or the one it matched by external ID. */
	public Id giftId;
	/** True when the row's gift already exists, found by its external ID. */
	public Boolean matchedExisting = false;
	/** An earlier row of the same chunk whose gift this row's external ID also names. */
	public GiftImportRow sameAs;
	/** True when an earlier chunk of the same run loaded this row's external ID (R-DM1). */
	public Boolean repeatsEarlierChunk = false;
	/** The scheduled payment this row's gift pays, and its pledge (R-DM6). */
	public Id installmentId;
	public Id commitmentId;

	// The row's soft credit and tribute (R-GI5, R-GI6), read by GiftImportCredits.
	public Soft_Credit__c credit;
	public String creditParty;
	public Tribute__c tribute;

	private final Map<String, Map<String, String>> entities;

	public GiftImportRow(Import_Row__c row, Map<String, Map<String, String>> entities) {
		this.row = row;
		this.entities = new Map<String, Map<String, String>>();
		for (String entity : entities == null ? new Set<String>() : entities.keySet()) {
			Map<String, String> held = new Map<String, String>();
			Map<String, String> given = entities.get(entity);
			for (String attribute : given == null ? new Set<String>() : given.keySet()) {
				held.put(attribute.toLowerCase(), given.get(attribute));
			}
			this.entities.put(entity.toLowerCase(), held);
		}
		read();
	}

	/** The text of one attribute, or null. */
	public String value(String entity, String attribute) {
		Map<String, String> held = entities.get(entity.toLowerCase());
		String text = held == null ? null : held.get(attribute.toLowerCase());
		return String.isBlank(text) ? null : text.trim();
	}

	/** Whether the row names anything in this entity. */
	public Boolean names(String entity) {
		Map<String, String> held = entities.get(entity.toLowerCase());
		if (held == null) {
			return false;
		}
		for (String text : held.values()) {
			if (String.isNotBlank(text)) {
				return true;
			}
		}
		return false;
	}

	/** Whether the row is a split across funds rather than a single fund. */
	public Boolean isSplit() {
		return !parts.isEmpty();
	}

	// -------------------------------------------------------------------------------------
	// Reading
	// -------------------------------------------------------------------------------------

	private void read() {
		Boolean namesGift = names(ENTITY_GIFT);
		carriesGift =
			namesGift ||
			names(ENTITY_ALLOCATION) ||
			names(ENTITY_SOFT_CREDIT) ||
			names(ENTITY_TRIBUTE);
		if (!carriesGift) {
			return;
		}
		try {
			readAmount();
			if (amount == null) {
				// Allocations, credits and tributes need a gift to hang on (R-GI1).
				fail(
					namesGift
						? Label.Giving_Import_ErrorAmountMissing
						: Label.Giving_Import_ErrorPartsWithoutGift
				);
				return;
			}
			readDate();
			readDonorChoice();
			readGiftValues();
			if (values.get(Gift__c.Type__c) == null) {
				// The gift's type is required, and a guessed one would be wrong on a receipt.
				throw new GiftImportException(Label.Giving_Import_ErrorTypeMissing);
			}
			readAllocations();
		} catch (GiftImportException unreadable) {
			fail(unreadable.getMessage());
		}
	}

	private void fail(String message) {
		if (error == null) {
			error = message;
		}
	}

	/**
	 * An in-kind gift has no amount (R-G12): what the goods were worth goes in Fair Market
	 * Value, so its amount is zero whether the file leaves it empty or writes 0.
	 */
	private void readAmount() {
		String text = value(ENTITY_GIFT, 'Amount__c');
		Boolean inKind = isInKind();
		if (text == null) {
			amount = inKind ? 0 : null;
			return;
		}
		Decimal parsed = parseAmount(text);
		if (parsed == null) {
			throw new GiftImportException(
				String.format(Label.Giving_Import_ErrorAmountUnreadable, new List<String>{ text })
			);
		}
		readableAmount = parsed;
		if (inKind && parsed != 0) {
			throw new GiftImportException(Label.Giving_Import_ErrorInKindAmount);
		}
		if (!inKind && parsed <= 0) {
			throw new GiftImportException(Label.Giving_Import_ErrorAmountNotPositive);
		}
		amount = parsed;
	}

	/** Whether the row's payment method reads as In-kind; an unreadable one is refused later. */
	private Boolean isInKind() {
		String text = value(ENTITY_GIFT, 'Type__c');
		if (text == null) {
			return false;
		}
		try {
			return paymentMethod(text) == TYPE_IN_KIND;
		} catch (GiftImportException unknown) {
			return false;
		}
	}

	private void readDate() {
		String text = value(ENTITY_GIFT, 'Gift_Date__c');
		if (text == null) {
			throw new GiftImportException(Label.Giving_Import_ErrorDateMissing);
		}
		giftDate = parseDate(text);
		if (giftDate == null) {
			throw new GiftImportException(
				String.format(Label.Giving_Import_ErrorDateUnreadable, new List<String>{ text })
			);
		}
	}

	private void readDonorChoice() {
		String text = value(ENTITY_GIFT, ATTRIBUTE_DONOR);
		if (text == null) {
			return;
		}
		for (
			String choice : new List<String>{ DONOR_CONTACT_1, DONOR_ORGANIZATION, DONOR_HOUSEHOLD }
		) {
			if (choice.equalsIgnoreCase(text.deleteWhitespace())) {
				donorChoice = choice;
				return;
			}
		}
		throw new GiftImportException(
			String.format(Label.Giving_Import_ErrorDonorChoice, new List<String>{ text })
		);
	}

	/**
	 * The gift attributes named by API name, as their fields' types, skipping amount and date
	 * (read above) and anything the package writes itself (R-GI3).
	 */
	private void readGiftValues() {
		appeal = value(ENTITY_GIFT, ATTRIBUTE_APPEAL);
		externalId = value(ENTITY_GIFT, 'External_Id__c');
		Map<String, String> held = entities.get(ENTITY_GIFT.toLowerCase());
		if (held == null) {
			return;
		}
		Map<String, Schema.SObjectField> fields = Schema.SObjectType.Gift__c.fields.getMap();
		for (String attribute : held.keySet()) {
			String text = held.get(attribute);
			if (
				String.isBlank(text) ||
				attribute == 'amount__c' ||
				attribute == 'gift_date__c' ||
				attribute == ATTRIBUTE_DONOR.toLowerCase() ||
				attribute == ATTRIBUTE_APPEAL.toLowerCase()
			) {
				continue;
			}
			Schema.SObjectField field = fields.get(attribute);
			Schema.DescribeFieldResult described = field == null ? null : field.getDescribe();
			if (
				described == null ||
				WRITTEN_BY_THE_PACKAGE.contains(described.getLocalName().toLowerCase()) ||
				described.getType() == Schema.DisplayType.REFERENCE ||
				!described.isCreateable()
			) {
				notLoaded.add(ENTITY_GIFT + '.' + attribute);
				continue;
			}
			values.put(field, typed(text.trim(), described));
		}
	}

	/**
	 * `Allocation.Fund` alone is a single fund. Numbered attributes (`Fund1`, `Amount1`,
	 * `Percent1`, and so on, with no number meaning part 1) are a split (R-GI4).
	 */
	private void readAllocations() {
		Map<Integer, Part> byIndex = new Map<Integer, Part>();
		for (Integer index = 1; index <= MAX_PARTS; index++) {
			String fund = value(ENTITY_ALLOCATION, ATTRIBUTE_FUND + index);
			String partAmount = value(ENTITY_ALLOCATION, ATTRIBUTE_AMOUNT + index);
			String partPercent = value(ENTITY_ALLOCATION, ATTRIBUTE_PERCENT + index);
			if (index == 1) {
				partAmount = partAmount == null
					? value(ENTITY_ALLOCATION, ATTRIBUTE_AMOUNT)
					: partAmount;
				partPercent = partPercent == null
					? value(ENTITY_ALLOCATION, ATTRIBUTE_PERCENT)
					: partPercent;
			}
			if (fund == null && partAmount == null && partPercent == null) {
				continue;
			}
			Part part = new Part();
			part.index = index;
			part.fund = fund;
			part.amount = partAmount == null
				? null
				: requireAmount(partAmount, ATTRIBUTE_AMOUNT + index);
			part.percent = partPercent == null
				? null
				: requireAmount(partPercent, ATTRIBUTE_PERCENT + index);
			byIndex.put(index, part);
		}
		String single = value(ENTITY_ALLOCATION, ATTRIBUTE_FUND);
		Part first = byIndex.get(1);
		if (single != null && (first == null || first.fund == null)) {
			if (first == null) {
				first = new Part();
				first.index = 1;
				byIndex.put(1, first);
			}
			first.fund = single;
		}
		// One fund with no amount or percent is the whole gift, not a split.
		if (byIndex.size() == 1 && first != null && first.amount == null && first.percent == null) {
			singleFund = first;
			return;
		}
		List<Integer> order = new List<Integer>(byIndex.keySet());
		order.sort();
		for (Integer index : order) {
			parts.add(byIndex.get(index));
		}
		checkSplit();
	}

	/** A split must name a fund and one of amount or percent for each part, and add up. */
	private void checkSplit() {
		if (parts.isEmpty()) {
			return;
		}
		Boolean anyAmount = false;
		Boolean anyPercent = false;
		Decimal amountTotal = 0;
		Decimal percentTotal = 0;
		for (Part part : parts) {
			if (part.fund == null || (part.amount == null) == (part.percent == null)) {
				throw new GiftImportException(
					String.format(
						Label.Giving_Import_ErrorSplitPartIncomplete,
						new List<String>{ String.valueOf(part.index) }
					)
				);
			}
			anyAmount = anyAmount || part.amount != null;
			anyPercent = anyPercent || part.percent != null;
			amountTotal += part.amount == null ? 0 : part.amount;
			percentTotal += part.percent == null ? 0 : part.percent;
		}
		if (anyAmount && anyPercent) {
			throw new GiftImportException(Label.Giving_Import_ErrorSplitMixed);
		}
		if (anyAmount && amountTotal.setScale(2) != amount.setScale(2)) {
			throw new GiftImportException(
				String.format(
					Label.Giving_Import_ErrorSplitAmountsDiffer,
					new List<String>{
						amountTotal.setScale(2).format(),
						amount.setScale(2).format()
					}
				)
			);
		}
		if (anyPercent && percentTotal != 100) {
			throw new GiftImportException(
				String.format(
					Label.Giving_Import_ErrorSplitPercentsDiffer,
					new List<String>{ percentTotal.format() }
				)
			);
		}
	}

	private static Decimal requireAmount(String text, String column) {
		Decimal parsed = parseAmount(text);
		if (parsed == null) {
			throw new GiftImportException(
				String.format(
					Label.Giving_Import_ErrorValueUnreadable,
					new List<String>{ text, column }
				)
			);
		}
		return parsed;
	}

	// -------------------------------------------------------------------------------------
	// Values
	// -------------------------------------------------------------------------------------

	/**
	 * A money amount as files write it: currency signs, spaces and thousands separators are
	 * ignored, and a dot is the decimal point. Null when what is left is not a number.
	 */
	public static Decimal parseAmount(String text) {
		if (String.isBlank(text)) {
			return null;
		}
		String cleaned = text.trim();
		Boolean negative =
			cleaned.startsWith('-') || (cleaned.startsWith('(') && cleaned.endsWith(')'));
		cleaned = cleaned.replaceAll('[^0-9.]', '');
		if (String.isBlank(cleaned) || cleaned.countMatches('.') > 1) {
			return null;
		}
		try {
			Decimal parsed = Decimal.valueOf(cleaned);
			return negative ? -parsed : parsed;
		} catch (Exception notANumber) {
			return null;
		}
	}

	/**
	 * A date written `YYYY-MM-DD` (with a time after it, as a workbook's date cell gives), or
	 * the way the running user's locale writes dates. Null when neither reads, never today.
	 */
	@TestVisible
	private static Date parseDate(String text) {
		if (String.isBlank(text)) {
			return null;
		}
		String trimmed = text.trim();
		Matcher iso = ISO_DATE.matcher(trimmed);
		if (iso.matches()) {
			Integer year = Integer.valueOf(iso.group(1));
			Integer month = Integer.valueOf(iso.group(2));
			Integer day = Integer.valueOf(iso.group(3));
			if (month < 1 || month > 12 || day < 1 || day > Date.daysInMonth(year, month)) {
				return null;
			}
			return Date.newInstance(year, month, day);
		}
		try {
			return Date.parse(trimmed);
		} catch (Exception notADate) {
			return null;
		}
	}

	/** A payment method matched to the picklist ignoring case, or through a common word. */
	@TestVisible
	private static String paymentMethod(String text) {
		List<String> accepted = new List<String>();
		for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
			if (!entry.isActive()) {
				continue;
			}
			accepted.add(entry.getValue());
			if (
				entry.getValue().equalsIgnoreCase(text) || entry.getLabel().equalsIgnoreCase(text)
			) {
				return entry.getValue();
			}
		}
		String alias = TYPE_ALIASES.get(text.normalizeSpace().toLowerCase());
		if (alias != null && accepted.contains(alias)) {
			return alias;
		}
		throw new GiftImportException(
			String.format(
				Label.Giving_Import_ErrorTypeUnknown,
				new List<String>{ text, String.join(accepted, ', ') }
			)
		);
	}

	/** A value as its field's own type; one that cannot be read rejects the row. */
	private static Object typed(String text, Schema.DescribeFieldResult field) {
		if (field.getName() == Gift__c.Type__c.getDescribe().getName()) {
			return paymentMethod(text);
		}
		Object result;
		switch on field.getType() {
			when CURRENCY, DOUBLE, PERCENT {
				result = parseAmount(text);
			}
			when INTEGER {
				Decimal parsed = parseAmount(text);
				result = parsed == null ? null : parsed.intValue();
			}
			when DATE {
				result = parseDate(text);
			}
			when BOOLEAN {
				String lowered = text.toLowerCase();
				result = new Set<String>{ 'true', 'yes', 'y', '1' }.contains(lowered)
					? true
					: new Set<String>{ 'false', 'no', 'n', '0' }.contains(lowered) ? false : null;
			}
			when else {
				result = text;
			}
		}
		if (result == null) {
			throw new GiftImportException(
				String.format(
					Label.Giving_Import_ErrorValueUnreadable,
					new List<String>{ text, field.getLabel() }
				)
			);
		}
		return result;
	}

	/** A row value that cannot be read; its message goes on the row. */
	public class GiftImportException extends Exception {
	}
}
