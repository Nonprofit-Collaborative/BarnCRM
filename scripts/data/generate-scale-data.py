#!/usr/bin/env python3
"""generate-scale-data.py

Generates the CSV files for the v0.11 tier 1 scale test (docs/contributor-guide/
scale-and-mobile-test-plan.md) and the 25,000 row import wizard file. Python 3 standard
library only. Deterministic: the same seed writes byte-identical files.

Names, streets and cities come from the lists in generate-sample-data.py, so no real person
appears in any file. Generated files are never committed (scale-test-data/ is ignored).

Modes:
    python3 scripts/data/generate-scale-data.py [--tier1] [--out-dir DIR] [--no-default-fund]
        Writes funds.csv, households.csv, contacts.csv, gifts.csv, soft_credits.csv and
        splits.csv, plus split-apex/split-NNN.apex (one anonymous Apex script per chunk of
        200 gifts). Tier 1 is the default and the only tier: 4,000 households, 10,000
        contacts, 30,000 gifts, 10% of gifts with a soft credit, 5% split across two funds
        (70% to the automatic default allocation, 30% to a second fund). Override with
        --households, --contacts and --gifts to shrink a run. The "Scale test General" fund
        is written as the default fund (Is_Default__c true) so the load works on an org
        with no sample data; --no-default-fund leaves the flag off for an org that already
        has a default fund (marking a second one would move the org's default).
        Households get a unique street address and contacts a unique name pair, email and
        phone, so the org's standard duplicate rules (which Bulk API 2.0 cannot override)
        do not reject rows.
    python3 scripts/data/generate-scale-data.py --import-file [--import-rows 25000]
        Writes import-wizard-25k.csv: one gift per row with the donor's name and email, in the
        headings the "Generic gift list" default template maps without any column changes.
    python3 scripts/data/generate-scale-data.py --resolve IN --out OUT [--map IDMAP \\
            --key-col COL --id-col COL] [--const COL=VALUE ...]
        Used by scripts/org/scale-test-tier1.sh between loads: replaces the key column with
        the Salesforce Id the previous load gave that key (IDMAP is an export of
        Id,Sample_Data_Key__c). --const COL=VALUE (repeatable) adds a constant column, used
        for the Household record type Id. --only-col COL --only-from FILE keeps only the rows
        whose COL value is in FILE's first column (an export of what loaded), so
        a child file is cut down to the parents that exist. Rows dropped for either reason
        are counted on stderr.

Relationships: Account and Contact have no external id field, so the files carry
Sample_Data_Key__c (prefix SCALE-) and the shell script resolves keys to Ids after each load.
Gifts carry External_Id__c, funds carry Accounting_Code__c, so soft credits join to gifts
directly and the split scripts find gifts and funds by those codes.
"""

import argparse
import csv
import datetime
import importlib.util
import random
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parent.parent

SEED = 20261013
ANCHOR_DATE = datetime.date(2026, 10, 1)  # gift dates run back ten years from here
GIFT_DAYS = 3650
KEY_PREFIX = "SCALE-"
FUND_CODES = ["SCALE-GEN", "SCALE-PROG", "SCALE-CAP", "SCALE-SCHOL", "SCALE-EVENT", "SCALE-ANNUAL"]
FUND_NAMES = [
    "Scale test General",
    "Scale test Programs",
    "Scale test Capital",
    "Scale test Scholarships",
    "Scale test Events",
    "Scale test Annual",
]
PAYMENT_TYPES = ["Cash", "Check", "Card", "ACH", "Stock", "Other"]
PAYMENT_WEIGHTS = [4, 22, 50, 18, 1, 5]
# Not "Household Member": Giving can add those automatically, and a hand-made one would
# double up with it.
SOFT_CREDIT_ROLES = ["Solicitor", "Influencer", "Honoree", "Matched Donor"]
ROLE_BY_POSITION = ["Head", "Spouse or Partner", "Child", "Other", "Other"]
TAIL_SHARE = 0.01
CEILING = 90000
SPLIT_SHARE = 0.05  # gifts split across two funds
SPLIT_PRIMARY_PERCENT = 70  # the default allocation keeps this much; the second fund gets the rest
SPLIT_CHUNK = 200  # gifts per anonymous Apex script
# Invented surnames (prefix + suffix) added to the sample list, so first + last name pairs
# stay distinct across 10,000 contacts and the standard Contact duplicate rule has no near twin.
SURNAME_PREFIXES = [
    "Ash", "Alder", "Bram", "Birch", "Black", "Brook", "Cald", "Carl", "Chester", "Clay",
    "Col", "Cran", "Dun", "East", "Elm", "Fair", "Fen", "Fern", "Gar", "Glen",
    "Green", "Hale", "Har", "Hazel", "High", "Hol", "Kings", "Lang", "Lin", "Mar",
    "Mill", "Moor", "New", "Nor", "Oak", "Pen", "Pine", "Quin", "Rad", "Red",
    "Rich", "Rose", "Rush", "Sand", "Sher", "Stan", "Stone", "Thorn", "Wal", "West",
    "Whit", "Wil", "Win", "Wood", "Yar", "Bel", "Dray", "Ever", "Ful", "Gil",
]
SURNAME_SUFFIXES = [
    "ford", "ton", "well", "ley", "wick", "field", "mont", "stead", "worth", "dale",
    "wood", "brook", "ridge", "hurst", "ham", "low", "more", "ner", "by", "croft",
    "bury", "gate", "shaw", "thwaite", "vale",
]


def load_sample_lists():
    spec = importlib.util.spec_from_file_location("sample_data", HERE / "generate-sample-data.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)
    return len(rows)


def household_sizes(rng, households, contacts):
    """Sizes of 1 to 5 summing to exactly `contacts`; the first household has 30 members."""
    if households * 5 < contacts or households > contacts:
        raise SystemExit("contacts must fit between 1 and 5 per household")
    big = 30 if households > 1 and contacts >= households + 29 else 0
    sizes = rng.choices([1, 2, 3, 4, 5], weights=[20, 35, 20, 17, 8], k=households)
    if big:
        sizes[0] = big
    diff = contacts - sum(sizes)
    start = 1 if big else 0
    while diff != 0:
        i = rng.randrange(start, households)
        if diff > 0 and sizes[i] < 5:
            sizes[i] += 1
            diff -= 1
        elif diff < 0 and sizes[i] > 1:
            sizes[i] -= 1
            diff += 1
    return sizes


def gift_counts(rng, donors, gifts):
    """Gifts per donor: 1% of donors with 50+ (one with 500), the rest spread randomly."""
    counts = [0] * donors
    tail = max(1, int(donors * TAIL_SHARE))
    order = list(range(donors))
    rng.shuffle(order)
    remaining = gifts
    for n, donor in enumerate(order[:tail]):
        count = 500 if n == 0 and gifts >= 5000 else rng.randint(50, 100)
        count = min(count, remaining)
        counts[donor] = count
        remaining -= count
    rest = order[tail:]
    while remaining > 0 and rest:
        donor = rng.choice(rest)
        if counts[donor] < 49:
            counts[donor] += 1
            remaining -= 1
    return counts


def gift_amount(rng):
    amount = rng.lognormvariate(3.9, 1.0)
    return "%.2f" % min(max(amount, 5.0), 25000.0)


def gift_date(rng):
    return (ANCHOR_DATE - datetime.timedelta(days=rng.randrange(GIFT_DAYS))).isoformat()


def person_name(rng, sample, surnames=None):
    female = rng.random() < 0.5
    first = rng.choice(sample.FEMALE_FIRST_NAMES if female else sample.MALE_FIRST_NAMES)
    return first, rng.choice(surnames or sample.SURNAME_POOL)


def wide_surnames(sample):
    """The sample surnames plus invented prefix + suffix ones, in a fixed order."""
    invented = [p + s for p in SURNAME_PREFIXES for s in SURNAME_SUFFIXES]
    return list(sample.SURNAME_POOL) + invented


def address(rng, sample, number):
    """A street address whose house number is `number`; callers pass a number used once."""
    state = rng.choice(sample.STATES)
    city, zip_prefix = rng.choice(sample.STATE_CITIES[state])
    street = "%d %s %s" % (
        number,
        rng.choice(sample.STREET_NAMES),
        rng.choice(sample.STREET_SUFFIXES),
    )
    return street, city, state, "%s%02d" % (zip_prefix, rng.randint(0, 99))


def contact_email(index, first, last):
    """Unique per contact (the index is in it) and unlike every other contact's."""
    clean = lambda text: "".join(ch for ch in text.lower() if ch.isalnum())
    return "c%06d.%s.%s@scale-test.example.org" % (index, clean(first), clean(last))


def contact_phone(index):
    """Unique per contact: 7919 is coprime with 10,000, so the line number never repeats
    within a block of 10,000 contacts, and the exchange changes between blocks."""
    return "555-%03d-%04d" % (200 + (index // 10000) % 800, (index * 7919) % 10000)


def split_rows_to_chunks(split_rows, size=SPLIT_CHUNK):
    return [split_rows[i : i + size] for i in range(0, len(split_rows), size)]


def render_split_apex(chunk):
    """Anonymous Apex that splits each gift in `chunk` ([gift external id, fund code, ...]).

    Per gift, the default allocation is cut to the primary share and a second allocation takes
    the rest. Giving refuses any save that leaves a gift's allocations not totalling the gift,
    checking after each DML statement, and a mixed upsert is still two operations (proven on
    oi-test), so the script pauses the Gift_Allocation_Totals automation for the update and
    the insert. That automation also fills Percent__c, so the script sets it. Afterwards
    GiftService.validateAllocations checks every gift in the chunk, and any problem rolls the
    whole chunk back. Gifts that did not load, or that have no single default allocation, are
    skipped and counted. Prints one SCALE_SPLIT line with the counts and the first error.
    """
    pairs = ", ".join("'%s' => '%s'" % (gift, fund) for gift, fund, *_ in chunk)
    return """Map<String, String> fundByGift = new Map<String, String>{ %(pairs)s };
Set<String> fundCodes = new Set<String>(fundByGift.values());
Map<String, Id> fundIds = new Map<String, Id>();
for (Fund__c f : [SELECT Id, Accounting_Code__c FROM Fund__c
                  WHERE Accounting_Code__c IN :fundCodes]) {
    fundIds.put(f.Accounting_Code__c, f.Id);
}
List<Gift__c> gifts = [SELECT Id, External_Id__c, Amount__c,
                              (SELECT Id FROM Gift_Allocations__r)
                       FROM Gift__c WHERE External_Id__c IN :fundByGift.keySet()];
List<Gift_Allocation__c> primaries = new List<Gift_Allocation__c>();
List<Gift_Allocation__c> seconds = new List<Gift_Allocation__c>();
Set<Id> splitGiftIds = new Set<Id>();
Integer skipped = fundByGift.size() - gifts.size();
for (Gift__c g : gifts) {
    Id fundId = fundIds.get(fundByGift.get(g.External_Id__c));
    if (fundId == null || g.Gift_Allocations__r.size() != 1 || g.Amount__c == null || g.Amount__c == 0) {
        skipped++;
        continue;
    }
    Decimal primary = (g.Amount__c * %(percent)d / 100).setScale(2, System.RoundingMode.HALF_UP);
    Decimal primaryPercent = (primary / g.Amount__c * 100).setScale(2, System.RoundingMode.HALF_UP);
    primaries.add(new Gift_Allocation__c(Id = g.Gift_Allocations__r[0].Id, Amount__c = primary,
        Percent__c = primaryPercent));
    seconds.add(new Gift_Allocation__c(Gift__c = g.Id, Fund__c = fundId, Amount__c = g.Amount__c - primary,
        Percent__c = 100 - primaryPercent));
    splitGiftIds.add(g.Id);
}
Integer rowCount = primaries.size() + seconds.size();
Integer failed = 0;
String firstError = '';
Savepoint sp = Database.setSavepoint();
try {
    AutomationControl.bypass('Gift_Allocation_Totals');
    update primaries;
    insert seconds;
    AutomationControl.clearBypass('Gift_Allocation_Totals');
    Map<Id, String> problems = GiftService.validateAllocations(splitGiftIds);
    if (!problems.isEmpty()) {
        Database.rollback(sp);
        failed = rowCount;
        firstError = problems.size() + ' gifts do not balance, chunk rolled back: ' + problems.values()[0];
    }
} catch (Exception e) {
    AutomationControl.clearBypass('Gift_Allocation_Totals');
    Database.rollback(sp);
    failed = rowCount;
    firstError = e.getMessage();
}
System.debug('SCALE_SPLIT requested=' + fundByGift.size() + ' skipped=' + skipped
    + ' rows=' + rowCount + ' failedRows=' + failed + ' firstError=' + firstError);
""" % {"pairs": pairs, "percent": SPLIT_PRIMARY_PERCENT}


def generate_tier1(args):
    rng = random.Random(SEED)
    sample = load_sample_lists()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    sizes = household_sizes(rng, args.households, args.contacts)

    surnames = wide_surnames(sample)
    # One house number per household, never reused: the standard Account duplicate rule
    # (fuzzy name plus address) cannot match two households with different street addresses.
    house_numbers = rng.sample(range(100, 100 + max(99800, args.households * 3)), args.households)
    used_names = set()

    household_rows, contact_rows = [], []
    contact_keys, contact_household = [], []
    for h, size in enumerate(sizes):
        hkey = "%sH-%05d" % (KEY_PREFIX, h + 1)
        street, city, state, postal = address(rng, sample, house_numbers[h])
        surname = rng.choice(surnames)
        household_rows.append([hkey, "%s Household" % surname, street, city, state, postal])
        for m in range(size):
            ckey = "%sC-%06d" % (KEY_PREFIX, len(contact_keys) + 1)
            # No two contacts share a first and last name (the standard Contact rule is a fuzzy
            # name match plus an email or phone match; this keeps the name half apart too).
            while True:
                first, last = person_name(rng, sample, surnames)
                if m == 0:
                    last = surname
                if (first, last) not in used_names:
                    used_names.add((first, last))
                    break
            email = contact_email(len(contact_keys) + 1, first, last)
            phone = contact_phone(len(contact_keys))
            role = ROLE_BY_POSITION[min(m, 4)]
            contact_rows.append(
                [ckey, hkey, first, last, email, phone, street, city, state, postal, role]
            )
            contact_keys.append(ckey)
            contact_household.append(h)

    counts = gift_counts(rng, args.contacts, args.gifts)
    gift_rows, gift_ids, gift_amounts, gift_donor = [], [], [], []
    for donor, count in enumerate(counts):
        for _ in range(count):
            gid = "SCALE-G-%07d" % (len(gift_ids) + 1)
            amount = gift_amount(rng)
            gift_rows.append(
                [
                    gid,
                    contact_keys[donor],
                    amount,
                    gift_date(rng),
                    rng.choices(PAYMENT_TYPES, weights=PAYMENT_WEIGHTS)[0],
                    "Received",
                    "Not required",
                    "SCALE-%07d" % (len(gift_ids) + 1),
                ]
            )
            gift_ids.append(gid)
            gift_amounts.append(float(amount))
            gift_donor.append(donor)

    total = len(gift_ids)
    soft_rows = []
    for g in sorted(rng.sample(range(total), round(total * 0.10))):
        credited = rng.randrange(args.contacts)
        while credited == gift_donor[g]:
            credited = rng.randrange(args.contacts)
        soft_rows.append(
            [gift_ids[g], contact_keys[credited], rng.choice(SOFT_CREDIT_ROLES),
             "%.2f" % gift_amounts[g]]
        )

    # Every gift already gets one automatic allocation (100%) to the default fund when the gift
    # trigger runs, and Giving refuses a save that leaves a gift's allocations not totalling the
    # gift, so a second allocation cannot be Bulk loaded. A split is made after the gifts load,
    # by the generated Apex scripts: the default allocation drops to 70% and a 30% allocation to
    # another fund is added in the same save. splits.csv lists the gifts and their second fund.
    split_rows = []
    for g in sorted(rng.sample(range(total), round(total * SPLIT_SHARE))):
        split_rows.append([gift_ids[g], rng.choice(FUND_CODES[1:])])
    split_n = write_csv(out / "splits.csv", ["Gift_External_Id", "Second_Fund_Code"], split_rows)
    apex_dir = out / "split-apex"
    apex_dir.mkdir(exist_ok=True)
    for old in apex_dir.glob("split-*.apex"):
        old.unlink()
    chunks = split_rows_to_chunks(split_rows)
    for i, chunk in enumerate(chunks):
        (apex_dir / ("split-%03d.apex" % (i + 1))).write_text(render_split_apex(chunk), encoding="utf-8")

    funds_rows = [
        [n, c, "true", "true" if i == 0 and not args.no_default_fund else "false"]
        for i, (n, c) in enumerate(zip(FUND_NAMES, FUND_CODES))
    ]
    counts_out = {
        "funds": write_csv(
            out / "funds.csv",
            ["Name", "Accounting_Code__c", "Active__c", "Is_Default__c"],
            funds_rows,
        ),
        "households": write_csv(
            out / "households.csv",
            ["Sample_Data_Key__c", "Name", "BillingStreet", "BillingCity", "BillingState",
             "BillingPostalCode"],
            household_rows,
        ),
        "contacts": write_csv(
            out / "contacts.csv",
            ["Sample_Data_Key__c", "Household_Key", "FirstName", "LastName", "Email", "Phone",
             "MailingStreet", "MailingCity", "MailingState", "MailingPostalCode",
             "Household_Role__c"],
            contact_rows,
        ),
        "gifts": write_csv(
            out / "gifts.csv",
            ["External_Id__c", "Contact_Key", "Amount__c", "Gift_Date__c", "Type__c", "Status__c",
             "Acknowledgment_Status__c", "Payment_Reference__c"],
            gift_rows,
        ),
        "soft_credits": write_csv(
            out / "soft_credits.csv",
            ["Gift__r.External_Id__c", "Contact_Key", "Role__c", "Amount__c"],
            soft_rows,
        ),
    }
    explicit = sum(counts_out.values())
    automatic = counts_out["gifts"]  # one default allocation per gift
    expected = explicit + automatic + split_n  # each split adds one second allocation
    print("Wrote %s" % out)
    for name, n in counts_out.items():
        print("  %-13s %7d rows" % (name, n))
    print("  %-13s %7d gifts, %d Apex scripts in split-apex/" % ("splits", split_n, len(chunks)))
    print("Rows in the loaded files:               %7d" % explicit)
    print("Plus automatic default allocations:     %7d" % automatic)
    print("Plus second allocations from splits:    %7d" % split_n)
    print("Expected records once loaded:           %7d" % expected)
    biggest = max(counts)
    tail = sum(1 for c in counts if c >= 50)
    print("Donors with 50+ gifts: %d (largest %d); donors with none: %d"
          % (tail, biggest, sum(1 for c in counts if c == 0)))
    loaded = counts_out["households"] + counts_out["contacts"] + counts_out["gifts"]
    print("Households + contacts + gifts: %d" % loaded)
    if expected > CEILING:
        print(
            "WARNING: %d expected records is over the %d ceiling (about 100,000 fit in a "
            "200 MB scratch org). Lower --gifts, --contacts and --households to fit."
            % (expected, CEILING),
            file=sys.stderr,
        )


def generate_import_file(args):
    rng = random.Random(SEED + 1)
    sample = load_sample_lists()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rows = args.import_rows
    donors = max(1, rows // 3)
    names = [person_name(rng, sample) for _ in range(donors)]
    data = []
    for i in range(rows):
        d = i % donors
        first, last = names[d]
        data.append(
            [
                first,
                last,
                "donor%05d@import-test.example.org" % (d + 1),
                gift_amount(rng),
                gift_date(rng),
                rng.choices(PAYMENT_TYPES, weights=PAYMENT_WEIGHTS)[0],
                "IMP-%07d" % (i + 1),
                FUND_NAMES[0],
            ]
        )
    path = out / "import-wizard-25k.csv"
    n = write_csv(
        path,
        ["Donor First Name", "Donor Last Name", "Donor Email", "Gift Amount", "Gift Date",
         "Payment Method", "Payment Reference", "Fund"],
        data,
    )
    print("Wrote %s: %d gift rows, %d donors (Generic gift list template; needs the fund '%s')"
          % (path, n, donors, FUND_NAMES[0]))


def resolve(args):
    mapping = {}
    if args.map:
        with open(args.map, newline="", encoding="utf-8") as handle:
            for row in csv.DictReader(handle):
                mapping[row["Sample_Data_Key__c"]] = row["Id"]
    only = None
    if args.only_col:
        with open(args.only_from, newline="", encoding="utf-8") as handle:
            reader = csv.reader(handle)
            next(reader, None)  # header: its first column holds the values, whatever it is called
            only = {row[0] for row in reader if row}
    consts = [c.split("=", 1) for c in args.const]
    missing = 0  # key with no Id: the parent row did not load
    not_loaded = 0  # parent not in the --only-from export
    kept = 0
    with open(args.resolve, newline="", encoding="utf-8") as src, open(
        args.out, "w", newline="", encoding="utf-8"
    ) as dst:
        reader = csv.reader(src)
        writer = csv.writer(dst, lineterminator="\n")
        header = next(reader)
        k = header.index(args.key_col) if args.key_col else None
        o = header.index(args.only_col) if only is not None else None
        new_header = list(header)
        if k is not None:
            new_header[k] = args.id_col
        writer.writerow(new_header + [c for c, _ in consts])
        for row in reader:
            if o is not None and row[o] not in only:
                not_loaded += 1
                continue
            if k is not None:
                if row[k] not in mapping:
                    missing += 1
                    continue
                row[k] = mapping[row[k]]
            writer.writerow(row + [v for _, v in consts])
            kept += 1
    total = kept + missing + not_loaded
    print("resolved %s -> %s: kept %d of %d rows" % (args.resolve, args.out, kept, total))
    if missing:
        print("DROPPED %d rows: their key has no Id (the parent row did not load)" % missing,
              file=sys.stderr)
    if not_loaded:
        print("DROPPED %d rows: %s is not among the loaded rows" % (not_loaded, args.only_col),
              file=sys.stderr)
    return kept, missing, not_loaded


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("--tier1", action="store_true", help="tier 1 volumes (the default)")
    p.add_argument("--import-file", action="store_true", help="write the import wizard file")
    p.add_argument("--import-rows", type=int, default=25000)
    p.add_argument("--out-dir", default=str(REPO_ROOT / "scale-test-data"))
    p.add_argument("--households", type=int, default=4000)
    p.add_argument("--contacts", type=int, default=10000)
    p.add_argument("--gifts", type=int, default=30000)
    p.add_argument("--resolve", metavar="IN")
    p.add_argument("--out")
    p.add_argument("--map")
    p.add_argument("--key-col")
    p.add_argument("--id-col")
    p.add_argument("--const", action="append", default=[])
    p.add_argument("--only-col")
    p.add_argument("--only-from")
    p.add_argument("--no-default-fund", action="store_true",
                   help="write the general fund without Is_Default__c (the org has a default)")
    args = p.parse_args()
    if args.resolve:
        if not args.out or bool(args.key_col) != bool(args.map) or (args.key_col and not args.id_col):
            p.error("--resolve needs --out; --key-col, --id-col and --map go together")
        if bool(args.only_col) != bool(args.only_from):
            p.error("--only-col and --only-from go together")
        resolve(args)
    elif args.import_file:
        generate_import_file(args)
    else:
        generate_tier1(args)


if __name__ == "__main__":
    main()
