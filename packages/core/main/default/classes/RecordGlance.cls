/**
 * What one module shows about a record in the glance card on Core's record pages (ADR-NEXT
 * `NEXT-record-glance-extension.md`): a title, a few figures and a few actions. Core draws it
 * and knows nothing of what it says, so a module returns finished label text and a page
 * reference, never keys Core would have to translate.
 *
 * The fields are read by the page (`@AuraEnabled`) and set by a module only through the
 * constructors and methods below: the platform refuses `@NamespaceAccessible` on an
 * `@AuraEnabled` field, so another package cannot set one directly once namespaced.
 */
@NamespaceAccessible
public with sharing class RecordGlance {
	/** Figure kinds the card formats for the person's locale. */
	public static final String KIND_CURRENCY = 'currency';
	public static final String KIND_NUMBER = 'number';
	public static final String KIND_DATE = 'date';
	public static final String KIND_TEXT = 'text';

	/** One card. A module with nothing to say returns null instead. */
	@NamespaceAccessible
	public class Card {
		/** Names the card for the page; the module's own name is enough. */
		@AuraEnabled
		public String key;
		@AuraEnabled
		public String title;
		/** A `custom:` or `standard:` icon, the tab icon of the object the card is about. */
		@AuraEnabled
		public String iconName;
		@AuraEnabled
		public List<Tile> tiles = new List<Tile>();
		@AuraEnabled
		public List<Action> actions = new List<Action>();

		@NamespaceAccessible
		public Card(String key, String title, String iconName) {
			this.key = key;
			this.title = title;
			this.iconName = iconName;
		}

		/** A money figure; null shows nothing. */
		@NamespaceAccessible
		public Card addCurrency(String label, Decimal value) {
			Tile tile = new Tile(label, KIND_CURRENCY);
			tile.numberValue = value;
			tiles.add(tile);
			return this;
		}

		/** A count or other plain number; null shows nothing. */
		@NamespaceAccessible
		public Card addNumber(String label, Decimal value) {
			Tile tile = new Tile(label, KIND_NUMBER);
			tile.numberValue = value;
			tiles.add(tile);
			return this;
		}

		/** A date, written in the viewer's locale; null shows nothing. */
		@NamespaceAccessible
		public Card addDate(String label, Date value) {
			Tile tile = new Tile(label, KIND_DATE);
			tile.dateValue = value;
			tiles.add(tile);
			return this;
		}

		/** A short word or name; blank shows nothing. */
		@NamespaceAccessible
		public Card addText(String label, String value) {
			Tile tile = new Tile(label, KIND_TEXT);
			tile.textValue = value;
			tiles.add(tile);
			return this;
		}

		/** A button that opens a Lightning page reference, for example a navItemPage with state. */
		@NamespaceAccessible
		public Card addAction(String label, Map<String, Object> pageReference) {
			Action action = new Action();
			action.label = label;
			action.pageReference = JSON.serialize(pageReference);
			actions.add(action);
			return this;
		}
	}

	/** One figure: a label and a value of one kind. */
	public class Tile {
		@AuraEnabled
		public String label;
		/** One of the KIND_ constants. */
		@AuraEnabled
		public String kind;
		@AuraEnabled
		public Decimal numberValue;
		@AuraEnabled
		public Date dateValue;
		@AuraEnabled
		public String textValue;

		Tile(String label, String kind) {
			this.label = label;
			this.kind = kind;
		}
	}

	/** One button: its text and where it goes, as a Lightning page reference in JSON. */
	public class Action {
		@AuraEnabled
		public String label;
		@AuraEnabled
		public String pageReference;
	}
}
