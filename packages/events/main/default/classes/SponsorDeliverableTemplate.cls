/**
 * Turns a sponsorship level's deliverables text, one deliverable per line, into the checklist a
 * new sponsor at that level starts with (EV-09, R-SP3). A line naming Logo, Booth or Passes (as
 * its first word) gets that type; any other line is type Other. Blank and repeated lines are
 * dropped, a name is cut to the 80 characters a name holds, and at most 50 items are made.
 */
public with sharing class SponsorDeliverableTemplate {
	public static final Integer MAX_ITEMS = 50;
	private static final Set<String> TYPES = new Set<String>{ 'logo', 'booth', 'passes' };

	/** One checklist item to make. */
	public class Item {
		public String name;
		public String type;
	}

	/**
	 * The checklist items for this text.
	 *
	 * @param text the level's Deliverables field, or null
	 * @return the items in line order
	 */
	public static List<Item> parse(String text) {
		List<Item> items = new List<Item>();
		if (String.isBlank(text)) {
			return items;
		}
		Set<String> seen = new Set<String>();
		for (String line : text.split('[\\r\\n]+')) {
			String name = line.trim();
			if (String.isBlank(name) || !seen.add(name.toLowerCase())) {
				continue;
			}
			Item item = new Item();
			item.name = name.left(80);
			String first = name.split('\\s+')[0].toLowerCase().replaceAll('[^a-z]', '');
			item.type = TYPES.contains(first) ? first.capitalize() : 'Other';
			items.add(item);
			if (items.size() == MAX_ITEMS) {
				break;
			}
		}
		return items;
	}
}
