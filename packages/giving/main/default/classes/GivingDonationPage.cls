/**
 * An appeal's online donation page (G-34; ADR-NEXT `NEXT-online-donation-pages.md`, decisions
 * 1 to 4; canonical model R-AP5). Core finds this class by name in `PublicPageExtensions` and
 * `FormAttachmentExtensions`; BarnCRM Forms serves the page with the appeal's form and, when the
 * form is sent, asks `startCheckout` before it stores anything. Without Forms nothing calls it.
 *
 * `without sharing`, system mode reads, because a Site guest user has no object access. It reads
 * only an active appeal with Donation Page on, and only its name, description, goal and form
 * key; never a gift, a donor or a total. It writes nothing: the gift is written by
 * `GivingDonations`, as staff, when Forms processes the submission.
 */
@NamespaceAccessible
public without sharing class GivingDonationPage implements PublicPageExtension, PublicCheckoutExtension, FormAttachmentExtension {
	public static final String KIND = 'appeals';
	public static final String ANSWER_AMOUNT = 'amount';
	private static final String OPEN = 'Open';
	private static final String NONE = 'None';
	/** Checkouts one appeal's page may start in an hour (card-testing guard). */
	@TestVisible
	private static final Integer CHECKOUTS_PER_HOUR = 30;
	private static final Decimal DEFAULT_MINIMUM = 5;

	@NamespaceAccessible
	public GivingDonationPage() {
		// Built by name from Core, so it needs a public constructor.
	}

	public String kind() {
		return KIND;
	}

	public Boolean handles(Schema.SObjectType recordType) {
		return recordType == Appeal__c.SObjectType;
	}

	public Map<String, Object> page(Id recordId) {
		Appeal__c appeal = published(recordId);
		if (appeal == null) {
			return null;
		}
		Boolean taking = formOf(appeal) != null && GivingDonations.paymentsReady();
		String offline = BarnHelp.text('Giving', 'Giving_Donate_Offline');
		Map<String, Object> view = new Map<String, Object>{
			'kind' => KIND,
			'recordId' => appeal.Id,
			'title' => appeal.Name,
			'description' => appeal.Description__c,
			'facts' => new List<Object>(),
			'sections' => goalSection(appeal),
			'formTitle' => BarnHelp.text('Giving', 'Giving_Donate_FormTitle'),
			'offlineMessage' => offline
		};
		view.put('registration', taking ? OPEN : NONE);
		view.put('formId', taking ? formOf(appeal) : null);
		view.put('message', taking ? null : offline);
		return view;
	}

	/** Appeals have no public list: each page is shared by its own address. */
	public Map<String, Object> listPage() {
		return null;
	}

	/** Starts the org's own hosted checkout for the answer `amount` (decision 4). */
	public Map<String, Object> startCheckout(
		Id recordId,
		Map<String, Object> answers,
		String returnUrl
	) {
		Appeal__c appeal = published(recordId);
		if (appeal == null || formOf(appeal) == null) {
			return null;
		}
		Map<String, Object> given = answers == null ? new Map<String, Object>() : answers;
		String name = (text(given, 'firstName') + ' ' + text(given, 'lastName')).trim();
		Callable payments = GivingDonations.payments();
		refuseCardTesting(appeal.Id, given.get(ANSWER_AMOUNT), payments);
		Map<String, Object> started = (Map<String, Object>) payments
			.call(
				'startCheckout',
				new Map<String, Object>{
					'amount' => given.get(ANSWER_AMOUNT),
					'description' => appeal.Name,
					'successUrl' => returnUrl + '&payment=done',
					'cancelUrl' => returnUrl + '&payment=cancelled',
					'payerName' => String.isBlank(name) ? null : name,
					'payerEmail' => String.isBlank(text(given, 'email'))
						? null
						: text(given, 'email'),
					'sourceRecordId' => appeal.Id,
					'listener' => GivingDonations.LISTENER
				}
			);
		return new Map<String, Object>{
			'paymentId' => started.get('paymentId'),
			'checkoutUrl' => started.get('checkoutUrl')
		};
	}

	/** A donation page's form is filled anonymously, so it carries no signed claim. */
	public Boolean signedClaim(Id contextRecordId) {
		return false;
	}

	public Id formFor(Id contextRecordId) {
		Appeal__c appeal = published(contextRecordId);
		return appeal == null ? null : formOf(appeal);
	}

	/** Writes the gift, as the staff user processing the submission (decision 5). */
	public void received(FormSubmissionReceipt receipt) {
		GivingDonations.record(receipt);
	}

	/**
	 * Against card testing (stolen cards tried with small gifts): an amount under the Donation
	 * Page Minimum Amount setting, or a checkout past CHECKOUTS_PER_HOUR on the appeal in the last
	 * hour, is refused before any checkout starts.
	 */
	@TestVisible
	private static void refuseCardTesting(Id appealId, Object amount, Callable payments) {
		Decimal minimum = minimumAmount();
		Decimal given;
		try {
			given = amount == null ? null : Decimal.valueOf(String.valueOf(amount));
		} catch (TypeException notANumber) {
			given = null;
		}
		if (given == null || given < minimum) {
			throw new DonationPageException(
				BarnHelp.text(
					'Giving',
					'Giving_Donate_BelowMinimum',
					new List<Object>{ minimum.setScale(2).format() }
				)
			);
		}
		Object recent = payments.call(
			'countRecent',
			new Map<String, Object>{ 'sourceRecordId' => appealId, 'minutes' => 60 }
		);
		if (recent instanceof Integer && (Integer) recent >= CHECKOUTS_PER_HOUR) {
			throw new DonationPageException(BarnHelp.text('Giving', 'Giving_Donate_TooMany'));
		}
	}

	/** The Donation Page Minimum Amount setting; 5 when unset, unreadable or below 0. */
	private static Decimal minimumAmount() {
		Object value = SettingsService.getValue(
			'Giving_Settings__c',
			'Donation_Page_Minimum_Amount__c'
		);
		try {
			Decimal minimum = value == null ? null : Decimal.valueOf(String.valueOf(value).trim());
			return minimum == null || minimum < 0 ? DEFAULT_MINIMUM : minimum;
		} catch (TypeException unreadable) {
			return DEFAULT_MINIMUM;
		}
	}

	/** A checkout the page refuses; Forms logs it and answers Failed. */
	public class DonationPageException extends Exception {
	}

	private static Appeal__c published(Id recordId) {
		if (recordId == null || recordId.getSObjectType() != Appeal__c.SObjectType) {
			return null;
		}
		List<Appeal__c> found = [
			SELECT Id, Name, Description__c, Goal__c, Donation_Form_Key__c
			FROM Appeal__c
			WHERE Id = :recordId AND Active__c = TRUE AND Donation_Page__c = TRUE
			WITH SYSTEM_MODE
			LIMIT 1
		];
		return found.isEmpty() ? null : found[0];
	}

	private static Id formOf(Appeal__c appeal) {
		if (String.isBlank(appeal.Donation_Form_Key__c)) {
			return null;
		}
		try {
			return Id.valueOf(appeal.Donation_Form_Key__c.trim());
		} catch (StringException notAnId) {
			return null;
		}
	}

	private static List<Object> goalSection(Appeal__c appeal) {
		if (appeal.Goal__c == null || appeal.Goal__c <= 0) {
			return new List<Object>();
		}
		return new List<Object>{
			new Map<String, Object>{
				'key' => 'goal',
				'title' => BarnHelp.text('Giving', 'Giving_Donate_Goal'),
				'items' => new List<Object>{
					new Map<String, Object>{
						'title' => BarnHelp.text('Giving', 'Giving_Donate_GoalItem'),
						'amount' => appeal.Goal__c,
						'currency' => UserInfo.getDefaultCurrency()
					}
				}
			}
		};
	}

	private static String text(Map<String, Object> answers, String key) {
		Object value = answers.get(key);
		return value == null ? '' : String.valueOf(value).trim();
	}
}
