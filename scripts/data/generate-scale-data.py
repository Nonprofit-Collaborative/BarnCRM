#!/usr/bin/env python3
"""generate-scale-data.py

Generates the CSV files for the v0.11 tier 1 scale test (docs/contributor-guide/
scale-and-mobile-test-plan.md) and the 25,000 row import wizard file. Python 3 standard
library only. Deterministic: the same seed writes byte-identical files.

Names, streets and cities come from the lists in generate-sample-data.py, so no real person
appears in any file. Generated files are never committed (scale-test-data/ is ignored).

Modes:
    python3 scripts/data/generate-scale-data.py [--tier1] [--out-dir DIR]
        Writes funds.csv, households.csv, contacts.csv, gifts.csv, soft_credits.csv and
        allocations.csv. Tier 1 is the default and the only tier: 4,000 households,
        10,000 contacts, 30,000 gifts, 10% of gifts with a soft credit, 5% with a second
        allocation. Override with --households, --contacts and --gifts to shrink a run.
    python3 scripts/data/generate-scale-data.py --import-file [--import-rows 25000]
        Writes import-wizard-25k.csv: one gift per row with the donor's name and email, in the
        headings the "Generic gift list" default template maps without any column changes.
    python3 scripts/data/generate-scale-data.py --resolve IN --out OUT [--map IDMAP \\
            --key-col COL --id-col COL] [--const COL=VALUE ...]
        Used by scripts/org/scale-test-tier1.sh between loads: replaces the key column with
        the Salesforce Id the previous load gave that key (IDMAP is an export of
        Id,Sample_Data_Key__c). --const COL=VALUE (repeatable) adds a constant column, used
        for the Household record type Id.

Relationships: Account and Contact have no external id field, so the files carry
Sample_Data_Key__c (prefix SCALE-) and the shell script resolves keys to Ids after each load.
Gifts carry External_Id__c, funds carry Accounting_Code__c, so soft credits and allocations
join to them directly.
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


def person_name(rng, sample):
    female = rng.random() < 0.5
    first = rng.choice(sample.FEMALE_FIRST_NAMES if female else sample.MALE_FIRST_NAMES)
    return first, rng.choice(sample.SURNAME_POOL)


def address(rng, sample):
    state = rng.choice(sample.STATES)
    city, zip_prefix = rng.choice(sample.STATE_CITIES[state])
    street = "%d %s %s" % (
        rng.randint(10, 9899),
        rng.choice(sample.STREET_NAMES),
        rng.choice(sample.STREET_SUFFIXES),
    )
    return street, city, state, "%s%02d" % (zip_prefix, rng.randint(0, 99))


def generate_tier1(args):
    rng = random.Random(SEED)
    sample = load_sample_lists()
    out = Path(args.out_dir)
    out.mkdir(parents=True, exist_ok=True)

    sizes = household_sizes(rng, args.households, args.contacts)

    household_rows, contact_rows = [], []
    contact_keys, contact_household = [], []
    for h, size in enumerate(sizes):
        hkey = "%sH-%05d" % (KEY_PREFIX, h + 1)
        street, city, state, postal = address(rng, sample)
        surname = rng.choice(sample.SURNAME_POOL)
        household_rows.append([hkey, "%s Household" % surname, street, city, state, postal])
        for m in range(size):
            ckey = "%sC-%06d" % (KEY_PREFIX, len(contact_keys) + 1)
            first, last = person_name(rng, sample)
            if m == 0:
                last = surname
            email = "%s.%s.%d@scale-test.example.org" % (
                first.lower().replace("'", ""),
                last.lower().replace("'", ""),
                len(contact_keys) + 1,
            )
            phone = "555-%03d-%04d" % (rng.randint(100, 999), rng.randint(0, 9999))
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

    # Every gift already gets one automatic allocation to the default fund when the gift
    # trigger runs, so a second allocation is what makes the gift a two allocation gift.
    alloc_rows = []
    for g in sorted(rng.sample(range(total), round(total * 0.05))):
        alloc_rows.append(
            [gift_ids[g], rng.choice(FUND_CODES), "%.2f" % round(gift_amounts[g] * 0.3, 2)]
        )

    counts_out = {
        "funds": write_csv(
            out / "funds.csv",
            ["Name", "Accounting_Code__c", "Active__c"],
            [[n, c, "true"] for n, c in zip(FUND_NAMES, FUND_CODES)],
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
        "allocations": write_csv(
            out / "allocations.csv",
            ["Gift__r.External_Id__c", "Fund__r.Accounting_Code__c", "Amount__c"],
            alloc_rows,
        ),
    }
    explicit = sum(counts_out.values())
    automatic = counts_out["gifts"]  # one default allocation per gift
    print("Wrote %s" % out)
    for name, n in counts_out.items():
        print("  %-13s %7d rows" % (name, n))
    print("Rows in the files:                      %7d" % explicit)
    print("Plus automatic default allocations:     %7d" % automatic)
    print("Expected records once loaded:           %7d" % (explicit + automatic))
    biggest = max(counts)
    tail = sum(1 for c in counts if c >= 50)
    print("Donors with 50+ gifts: %d (largest %d); donors with none: %d"
          % (tail, biggest, sum(1 for c in counts if c == 0)))
    loaded = counts_out["households"] + counts_out["contacts"] + counts_out["gifts"]
    print("Households + contacts + gifts: %d" % loaded)
    if explicit + automatic > CEILING:
        print(
            "WARNING: %d expected records is over the %d ceiling (about 100,000 fit in a "
            "200 MB scratch org). Lower --gifts, --contacts and --households to fit."
            % (explicit + automatic, CEILING),
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
    consts = [c.split("=", 1) for c in args.const]
    missing = 0
    with open(args.resolve, newline="", encoding="utf-8") as src, open(
        args.out, "w", newline="", encoding="utf-8"
    ) as dst:
        reader = csv.reader(src)
        writer = csv.writer(dst, lineterminator="\n")
        header = next(reader)
        k = header.index(args.key_col) if args.key_col else None
        new_header = list(header)
        if k is not None:
            new_header[k] = args.id_col
        writer.writerow(new_header + [c for c, _ in consts])
        for row in reader:
            if k is not None:
                if row[k] not in mapping:
                    missing += 1
                    continue
                row[k] = mapping[row[k]]
            writer.writerow(row + [v for _, v in consts])
    if missing:
        print("%d rows had a key with no Id and were dropped" % missing, file=sys.stderr)
    print("resolved %s -> %s" % (args.resolve, args.out))


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
    args = p.parse_args()
    if args.resolve:
        if not args.out or bool(args.key_col) != bool(args.map) or (args.key_col and not args.id_col):
            p.error("--resolve needs --out; --key-col, --id-col and --map go together")
        resolve(args)
    elif args.import_file:
        generate_import_file(args)
    else:
        generate_tier1(args)


if __name__ == "__main__":
    main()
