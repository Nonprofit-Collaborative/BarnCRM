/**
 * Turns a failure into the sentence a person sees, for every package. An exception BarnCRM
 * raised on purpose carries a label-based message and is shown as it is. Anything else (a
 * platform exception such as a failed save or an empty query) is replaced by a label that says
 * what to do, so nobody sees raw exception text; the detail stays in the Error Log.
 */
@NamespaceAccessible
public with sharing class UserErrors {
	/**
	 * The exception an @AuraEnabled method throws so the screen shows this text rather than
	 * the platform's generic "script thrown" text.
	 */
	@NamespaceAccessible
	public static AuraHandledException message(String text) {
		AuraHandledException reported = new AuraHandledException(text);
		reported.setMessage(text);
		return reported;
	}

	/**
	 * Any BarnCRM exception is shown as written; anything else becomes Core's unexpected-error
	 * label.
	 * @param caught the failure
	 * @param context where it happened, for the Error Log
	 * @param log false when the caller cannot insert a record (a cacheable call)
	 */
	@NamespaceAccessible
	public static AuraHandledException wrap(Exception caught, String context, Boolean log) {
		if (log != false) {
			ErrorLogger.log(caught, context);
		}
		String text = isKnown(caught) ? caught.getMessage() : Label.Core_UnexpectedError;
		if (String.isBlank(text)) {
			text = Label.Core_UnexpectedError;
		}
		return message(text);
	}

	/**
	 * The caller decides which failures speak for themselves.
	 * @param caught the failure
	 * @param shown true when its message is written for a person: shown as it is, not logged
	 * @param context where it happened, for the Error Log
	 * @param fallbackLabel the feature's label for anything else, which is logged
	 */
	@NamespaceAccessible
	public static AuraHandledException wrap(
		Exception caught,
		Boolean shown,
		String context,
		String fallbackLabel
	) {
		return wrap(caught, shown, context, null, fallbackLabel);
	}

	/** As above, with the record the failure is about, for the Error Log. */
	@NamespaceAccessible
	public static AuraHandledException wrap(
		Exception caught,
		Boolean shown,
		String context,
		Id recordId,
		String fallbackLabel
	) {
		if (shown == true) {
			return message(caught.getMessage());
		}
		ErrorLogger.log(caught, context, recordId);
		return message(fallbackLabel);
	}

	/**
	 * One call for a controller's catch block. A failure written for a person is shown as it is
	 * and not logged: a BarnCRM exception, or an AuraHandledException already worded for the
	 * screen. Anything else is logged and replaced by the fallback text.
	 * @param caught the failure
	 * @param context where it happened, for the Error Log
	 * @param fallbackText what the screen shows for anything else
	 */
	@NamespaceAccessible
	public static AuraHandledException wrap(Exception caught, String context, String fallbackText) {
		return new Screen(context, null, fallbackText).wrap(caught);
	}

	/**
	 * One screen's catch blocks, kept as a static final on its controller so that each catch is
	 * a single `throw ERRORS.wrap(e)` and no controller carries its own forwarding helper. What
	 * it shows and logs is the three-argument `wrap` above. The fallback is help text read only
	 * when a failure needs it, or a label's text.
	 */
	@NamespaceAccessible
	public with sharing class Screen {
		private final String context;
		private final String helpPackage;
		private final String fallback;
		private Boolean showsDml = false;

		/**
		 * @param context where its failures happen, for the Error Log, when a call names none
		 * @param helpPackage the package whose help text holds the fallback, or null when the
		 *   fallback is the text itself (a label)
		 * @param fallback the help key, or the text, shown for an unexpected failure
		 */
		@NamespaceAccessible
		public Screen(String context, String helpPackage, String fallback) {
			this.context = context;
			this.helpPackage = helpPackage;
			this.fallback = fallback;
		}

		/**
		 * A failed save also shows the platform's first message for the row (a validation
		 * rule's own wording, for example) and is not logged.
		 */
		@NamespaceAccessible
		public Screen showingDml() {
			showsDml = true;
			return this;
		}

		/** The failure as the screen shows it, logged under the screen's context. */
		@NamespaceAccessible
		public AuraHandledException wrap(Exception caught) {
			return this.wrap(caught, context, (Id) null);
		}

		/** As above, logged under the given context. */
		@NamespaceAccessible
		public AuraHandledException wrap(Exception caught, String logContext) {
			return this.wrap(caught, logContext, (Id) null);
		}

		/** As above, with the record the failure is about, for the Error Log. */
		@NamespaceAccessible
		public AuraHandledException wrap(Exception caught, String logContext, Id recordId) {
			if (caught instanceof AuraHandledException) {
				return (AuraHandledException) caught;
			}
			Boolean known = UserErrors.isKnown(caught);
			if (showsDml && !known && caught instanceof DmlException && caught.getNumDml() > 0) {
				return UserErrors.message(caught.getDmlMessage(0));
			}
			return UserErrors.wrap(
				caught,
				known,
				logContext,
				recordId,
				helpPackage == null ? fallback : BarnHelp.text(helpPackage, fallback)
			);
		}
	}

	/**
	 * Not logged (the caller logs first). A BarnCRM exception is shown as written, a failed save
	 * shows the first message the platform gives for the row (a validation rule's own wording,
	 * for example), and anything else becomes the feature's label.
	 * @param caught the failure
	 * @param fallbackLabel the label shown for an unexpected failure
	 */
	@NamespaceAccessible
	public static AuraHandledException wrapShowingDml(Exception caught, String fallbackLabel) {
		String text = fallbackLabel;
		if (isKnown(caught)) {
			text = caught.getMessage();
		} else if (caught instanceof DmlException && caught.getNumDml() > 0) {
			text = caught.getDmlMessage(0);
		}
		if (String.isBlank(text)) {
			text = fallbackLabel;
		}
		return message(text);
	}

	/**
	 * A failure raised by BarnCRM code with a message written for a person. The platform's own
	 * exception types live in the System namespace.
	 */
	@TestVisible
	private static Boolean isKnown(Exception caught) {
		String typeName = caught.getTypeName();
		return !typeName.startsWith('System.') &&
			!typeName.startsWith('Database.') &&
			typeName.endsWith('Exception');
	}
}
