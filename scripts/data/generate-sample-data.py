#!/usr/bin/env python3
"""generate-sample-data.py

Generates the C-10 sample data set and writes it as the JSON body of the two
static resources the sample data loaders read.

Core (SampleData): 200 realistic, diverse US households (440 contacts), 25
organizations, the connections between people in different households, and the
affiliations that join people to organizations.

Giving (GivingSampleData): funds, appeals, three years of gifts with their
allocations, pledges and recurring commitments, hand-entered soft credits, and
tributes. Its dates are day offsets from the day the set is loaded rather than
fixed dates, so a set loaded next year still has a gift this year.

Python 3 standard library only. Deterministic: fixed random seeds mean the
output is byte-identical across runs and across machines, so the generated
static resources can be regenerated and diffed in code review.

Usage:
    python3 scripts/data/generate-sample-data.py

Writes:
    packages/core/main/default/staticresources/SampleData.json
    packages/giving/main/default/staticresources/GivingSampleData.json

See data/sample/README.md for the JSON structure and regeneration notes.
"""

import json
import random
from pathlib import Path

SEED = 20260907
RNG = random.Random(SEED)

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
OUTPUT_PATH = (
    REPO_ROOT
    / "packages"
    / "core"
    / "main"
    / "default"
    / "staticresources"
    / "SampleData.json"
)
GIVING_OUTPUT_PATH = (
    REPO_ROOT
    / "packages"
    / "giving"
    / "main"
    / "default"
    / "staticresources"
    / "GivingSampleData.json"
)

# ---------------------------------------------------------------------------
# Name and address pools. Deliberately diverse: Hispanic, East Asian, South
# Asian, African-American, Middle Eastern, and Anglo-European names, so the
# sample set exercises naming rules (hyphenation, differing surnames, single
# words) the way a real donor list does.
# ---------------------------------------------------------------------------

MALE_FIRST_NAMES = [
    "James", "Robert", "John", "Michael", "David", "William", "Carlos",
    "Luis", "Miguel", "Jose", "Antonio", "Diego", "Wei", "Jun", "Hiroshi",
    "Kenji", "Raj", "Arjun", "Amir", "Omar", "Hassan", "Malik", "DeShawn",
    "Marcus", "Andre", "Terrence", "Kwame", "Liam", "Noah", "Ethan",
    "Mason", "Lucas", "Henry", "Samuel", "Benjamin", "Daniel", "Matthew",
    "Joseph", "Thomas", "Charles", "Gabriel", "Ricardo", "Fernando",
    "Alejandro", "Mateo", "Sung", "Minh", "Tuan", "Dmitri", "Pavel",
]

FEMALE_FIRST_NAMES = [
    "Mary", "Patricia", "Linda", "Barbara", "Elizabeth", "Jennifer",
    "Maria", "Sofia", "Isabella", "Camila", "Valentina", "Lucia", "Ana",
    "Mei", "Ling", "Yuki", "Priya", "Anika", "Fatima", "Layla", "Amara",
    "Keisha", "Aaliyah", "Jasmine", "Tanya", "Nia", "Olivia", "Emma",
    "Ava", "Sophia", "Charlotte", "Amelia", "Harper", "Evelyn", "Grace",
    "Chloe", "Victoria", "Rosa", "Carmen", "Elena", "Jun", "Hana",
    "Soo", "Anh", "Thu", "Katarina", "Ingrid", "Margaret", "Susan", "Jen",
]

SURNAMES = [
    "Garcia", "Martinez", "Rodriguez", "Hernandez", "Lopez", "Gonzalez",
    "Perez", "Sanchez", "Ramirez", "Torres", "Flores", "Alvarez", "Diaz",
    "Smith", "Johnson", "Williams", "Brown", "Jones", "Miller", "Davis",
    "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin",
    "Lee", "Walker", "Hall", "Allen", "Young", "King", "Wright", "Scott",
    "Chen", "Wang", "Zhang", "Liu", "Kim", "Park", "Nguyen", "Tran", "Pham",
    "Patel", "Shah", "Kumar", "Singh", "Khan", "Ahmed", "Hassan", "Ali",
    "Washington", "Jefferson", "Freeman", "Coleman", "Bell", "Foster",
    "Okafor", "Adeyemi", "Mensah", "Osei", "Silva", "Costa", "Rossi",
    "Novak", "Kowalski", "Petrov", "Ivanov", "Sullivan", "O'Brien",
    "O'Connor", "Murphy", "Reyes", "Morales", "Castillo", "Ortiz",
]

# Second halves for hyphenated surnames (a person's own surname combined
# with a partner's), kept separate so we can build realistic pairs.
HYPHEN_PARTNERS = [
    "Bennett", "Clarke", "Ferreira", "Nakamura", "Okonkwo", "Reyes",
    "Whitfield", "Ellison", "Duarte", "Sato",
]

SALUTATIONS_MALE = ["Mr."]
SALUTATIONS_FEMALE = ["Mrs.", "Ms."]
SALUTATION_NEUTRAL_TITLES = ["Dr."]

NICKNAMES = {
    "William": "Bill",
    "Robert": "Bob",
    "Richard": "Rick",
    "Elizabeth": "Liz",
    "Margaret": "Peggy",
    "Charles": "Chuck",
    "Katherine": "Kate",
    "Jennifer": "Jen",
    "Michael": "Mike",
    "Patricia": "Pat",
    "Anthony": "Tony",
    "Deborah": "Debbie",
    "James": "Jim",
    "Susan": "Sue",
    "Thomas": "Tom",
}

# A handful of states, each with a couple of cities and a zip prefix range,
# so mailing addresses are spread across several states rather than one.
STATE_CITIES = {
    "CA": [("San Diego", "921"), ("Fresno", "937"), ("Sacramento", "958")],
    "TX": [("Austin", "787"), ("El Paso", "799"), ("San Antonio", "782")],
    "NY": [("Rochester", "146"), ("Syracuse", "132"), ("Albany", "122")],
    "IL": [("Springfield", "627"), ("Peoria", "616"), ("Rockford", "611")],
    "OH": [("Columbus", "432"), ("Dayton", "454"), ("Toledo", "436")],
    "GA": [("Savannah", "314"), ("Macon", "312"), ("Athens", "306")],
    "WA": [("Spokane", "992"), ("Tacoma", "984"), ("Olympia", "985")],
    "CO": [("Boulder", "803"), ("Pueblo", "810"), ("Aurora", "800")],
    "FL": [("Tampa", "336"), ("Orlando", "328"), ("Tallahassee", "323")],
    "PA": [("Erie", "165"), ("Allentown", "181"), ("Scranton", "185")],
    "NC": [("Asheville", "288"), ("Durham", "277"), ("Wilmington", "284")],
    "MN": [("Duluth", "558"), ("Rochester", "559"), ("St. Cloud", "563")],
}
STATES = list(STATE_CITIES.keys())

STREET_NAMES = [
    "Maple", "Oak", "Cedar", "Elm", "Willow", "Birch", "Sunset", "Ridge",
    "Meadow", "River", "Lake", "Highland", "Prairie", "Orchard", "Chestnut",
    "Magnolia", "Aspen", "Juniper", "Harbor", "Foxglove", "Hillcrest",
    "Fairview", "Grand", "Pine", "Spruce",
]
STREET_SUFFIXES = ["St", "Ave", "Dr", "Ln", "Rd", "Ct", "Way", "Blvd"]

HOUSEHOLD_ROLES = ["Head", "Spouse or Partner", "Child", "Other"]

ADULT_MIN_AGE = 24
ADULT_MAX_AGE = 88
# Half the widest plausible gap between partners, so a couple is at most 24 years apart.
SPOUSE_AGE_SPREAD = 12

# "Garcia" is reserved for the single guaranteed household the admin guide's
# walkthrough looks for ("The Garcia Family"), so every other random draw
# uses this pool instead, keeping that name unique in the sample set.
SURNAME_POOL = [s for s in SURNAMES if s != "Garcia"]

# Core's sample data is neutral (ADR-0062):
# mostly businesses, schools and clubs, with one foundation and one church among them, as
# any organization's contact list has. Keep exactly eleven templates: the generator's draws
# depend on the list's length, and changing it would reshuffle every later record.
ORG_NAME_TEMPLATES = [
    ("business", "{word} & {word2} LLC"),
    ("business", "{word} Hardware"),
    ("business", "{word} Consulting Group"),
    ("business", "{word} Coffee Roasters"),
    ("business", "{word} Credit Union"),
    ("business", "{word} Family Dental"),
    ("school", "{word} County School District"),
    ("school", "{word} Community College"),
    ("club", "{word} Rotary Club"),
    ("foundation", "The {word} Foundation"),
    ("church", "{word} Community Church"),
]
ORG_WORDS = [
    "Cedar Valley", "Riverside", "Hilltop", "Northgate", "Bright Horizons",
    "Willowbrook", "Bayview", "Heritage", "Lakeside", "Franklin", "Oakwood",
    "Pinecrest", "Maple Ridge", "Unity", "Founders", "Evergreen", "Summit",
    "Meridian", "Cornerstone", "Stonebridge", "Harborview", "Ashford",
]


def pick_first_name(rng, gender):
    return rng.choice(MALE_FIRST_NAMES if gender == "M" else FEMALE_FIRST_NAMES)


# Children below this age get no salutation and no email address of their own:
# an organization does not address a nine year old as "Mr." or mail them directly.
MINOR_COURTESY_AGE = 13

REFERENCE_YEAR = 2026


def salutation_for(rng, gender, formal_title=None):
    if formal_title:
        return formal_title
    if gender == "M":
        return "Mr."
    return random_choice_weighted(rng, [("Mrs.", 0.6), ("Ms.", 0.4)])


def random_choice_weighted(rng, options):
    total = sum(weight for _, weight in options)
    threshold = rng.uniform(0, total)
    running = 0.0
    for value, weight in options:
        running += weight
        if threshold <= running:
            return value
    return options[-1][0]


def make_phone(rng):
    return "({:03d}) {:03d}-{:04d}".format(
        rng.choice([202, 312, 404, 415, 512, 617, 702, 720, 803, 919]),
        rng.randint(200, 999),
        rng.randint(0, 9999),
    )


def make_email(first, last, index):
    slug = "{0}.{1}{2}".format(first.lower(), last.lower().replace("'", "").replace(" ", ""), index)
    return "{0}@example.org".format(slug)


def make_address(rng):
    state = rng.choice(STATES)
    city, zip_prefix = rng.choice(STATE_CITIES[state])
    street_number = rng.randint(100, 9999)
    street = "{0} {1} {2}".format(
        street_number, rng.choice(STREET_NAMES), rng.choice(STREET_SUFFIXES)
    )
    postal_code = "{0}{1:02d}".format(zip_prefix, rng.randint(0, 99))
    return {
        "street": street,
        "city": city,
        "state": state,
        "postalCode": postal_code,
    }


def make_birthdate(rng, min_age, max_age, reference_year=REFERENCE_YEAR):
    age = rng.randint(min_age, max_age)
    year = reference_year - age
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    return "{0:04d}-{1:02d}-{2:02d}".format(year, month, day)


def maybe_preferred_name(rng, first_name):
    nickname = NICKNAMES.get(first_name)
    if nickname and rng.random() < 0.5:
        return nickname
    return None


def make_member(
    rng,
    first_name,
    last_name,
    gender,
    role,
    address,
    index,
    is_child=False,
    formal_title=None,
    deceased=False,
    min_age=None,
    max_age=None,
):
    if is_child:
        birthdate = make_birthdate(rng, 2, 17)
    else:
        birthdate = make_birthdate(
            rng,
            ADULT_MIN_AGE if min_age is None else min_age,
            ADULT_MAX_AGE if max_age is None else max_age,
        )
    age = age_from_birthdate(birthdate)

    member = {
        "firstName": first_name,
        "lastName": last_name,
    }
    if age >= MINOR_COURTESY_AGE:
        member["salutation"] = salutation_for(rng, gender, formal_title)
    member["householdRole"] = role
    if age >= MINOR_COURTESY_AGE:
        member["email"] = make_email(first_name, last_name, index)
    member["phone"] = make_phone(rng)
    member["mailingStreet"] = address["street"]
    member["mailingCity"] = address["city"]
    member["mailingState"] = address["state"]
    member["mailingPostalCode"] = address["postalCode"]
    member["birthdate"] = birthdate

    preferred = maybe_preferred_name(rng, first_name)
    if preferred:
        member["preferredName"] = preferred
    if deceased:
        member["deceased"] = True
    return member


def age_from_birthdate(birthdate):
    return REFERENCE_YEAR - int(birthdate[:4])


def spouse_age_range(head_member):
    """Keep partners within a plausible span: at most 24 years apart."""
    head_age = age_from_birthdate(head_member["birthdate"])
    return (
        max(ADULT_MIN_AGE, head_age - SPOUSE_AGE_SPREAD),
        min(ADULT_MAX_AGE, head_age + SPOUSE_AGE_SPREAD),
    )


def make_anniversary(rng, members):
    """A date after every adult in the household turned twenty, never before one was born."""
    adult_years = [
        int(member["birthdate"][:4])
        for member in members
        if member["householdRole"] != "Child"
    ]
    if not adult_years:
        return None
    earliest_year = max(adult_years) + 20
    if earliest_year > REFERENCE_YEAR:
        return None
    year = rng.randint(earliest_year, REFERENCE_YEAR)
    return "{0:04d}-{1:02d}-{2:02d}".format(year, rng.randint(1, 12), rng.randint(1, 28))


def build_family(
    rng, key, surname, address, member_index, deceased=False, extra_child=False, child_count=None
):
    """Head + Spouse or Partner + zero or more Children, shared surname."""
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)

    members = []
    head = make_member(rng, head_first, surname, head_gender, "Head", address, member_index[0])
    members.append(head)
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            deceased=deceased,
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1

    if child_count is None:
        child_count = 2 if extra_child else rng.randint(1, 2)
    for _ in range(child_count):
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng, child_first, surname, child_gender, "Child", address, member_index[0], is_child=True
            )
        )
        member_index[0] += 1

    anniversary = make_anniversary(rng, members) if rng.random() < 0.7 else None
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": anniversary,
        "address": address,
        "members": members,
    }


def build_single(rng, key, surname, address, member_index):
    gender = rng.choice(["M", "F"])
    first = pick_first_name(rng, gender)
    members = [make_member(rng, first, surname, gender, "Head", address, member_index[0])]
    member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": None,
        "address": address,
        "members": members,
    }


def build_differing_surnames(rng, key, address, member_index):
    """A household where the two adults kept different surnames."""
    surname_a = rng.choice(SURNAME_POOL)
    surname_b = rng.choice([s for s in SURNAME_POOL if s != surname_a])
    gender_a = rng.choice(["M", "F"])
    gender_b = "F" if gender_a == "M" else "M"
    first_a = pick_first_name(rng, gender_a)
    first_b = pick_first_name(rng, gender_b)
    head = make_member(rng, first_a, surname_a, gender_a, "Head", address, member_index[0])
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            first_b,
            surname_b,
            gender_b,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1
    if rng.random() < 0.5:
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        child_surname = rng.choice([surname_a, surname_b])
        members.append(
            make_member(
                rng,
                child_first,
                child_surname,
                child_gender,
                "Child",
                address,
                member_index[0],
                is_child=True,
            )
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.5 else None,
        "address": address,
        "members": members,
    }


def build_hyphenated(rng, key, address, member_index):
    base = rng.choice(SURNAME_POOL)
    partner = rng.choice(HYPHEN_PARTNERS)
    hyphenated = "{0}-{1}".format(base, partner)
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(rng, head_first, hyphenated, head_gender, "Head", address, member_index[0])
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            hyphenated,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1
    if rng.random() < 0.6:
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng,
                child_first,
                hyphenated,
                child_gender,
                "Child",
                address,
                member_index[0],
                is_child=True,
            )
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.7 else None,
        "address": address,
        "members": members,
    }


def build_three_generation(rng, key, surname, address, member_index):
    """Grandparent(s), a parent couple, and children, all sharing a surname."""
    members = []

    grandparent_gender = rng.choice(["M", "F"])
    grandparent_first = pick_first_name(rng, grandparent_gender)
    members.append(
        make_member(
            rng, grandparent_first, surname, grandparent_gender, "Other", address, member_index[0]
        )
    )
    member_index[0] += 1
    if rng.random() < 0.6:
        other_gp_gender = "F" if grandparent_gender == "M" else "M"
        other_gp_first = pick_first_name(rng, other_gp_gender)
        members.append(
            make_member(
                rng, other_gp_first, surname, other_gp_gender, "Other", address, member_index[0]
            )
        )
        member_index[0] += 1

    parent_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if parent_gender == "M" else "M"
    parent_first = pick_first_name(rng, parent_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(rng, parent_first, surname, parent_gender, "Head", address, member_index[0])
    members.append(head)
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
        )
    )
    member_index[0] += 1

    for _ in range(rng.randint(1, 2)):
        child_gender = rng.choice(["M", "F"])
        child_first = pick_first_name(rng, child_gender)
        members.append(
            make_member(
                rng, child_first, surname, child_gender, "Child", address, member_index[0], is_child=True
            )
        )
        member_index[0] += 1

    return {
        "key": key,
        "name": None,
        "customName": False,
        "anniversary": make_anniversary(rng, members) if rng.random() < 0.6 else None,
        "address": address,
        "members": members,
    }


def build_custom_name_household(rng, key, custom_name, surname, address, member_index, formal_title):
    head_gender = rng.choice(["M", "F"])
    spouse_gender = "F" if head_gender == "M" else "M"
    head_first = pick_first_name(rng, head_gender)
    spouse_first = pick_first_name(rng, spouse_gender)
    head = make_member(
        rng,
        head_first,
        surname,
        head_gender,
        "Head",
        address,
        member_index[0],
        formal_title=formal_title,
    )
    members = [head]
    member_index[0] += 1
    spouse_min, spouse_max = spouse_age_range(head)
    members.append(
        make_member(
            rng,
            spouse_first,
            surname,
            spouse_gender,
            "Spouse or Partner",
            address,
            member_index[0],
            min_age=spouse_min,
            max_age=spouse_max,
            # "The Doctors Nguyen": both members are doctors.
            formal_title="Dr." if formal_title == "Dr." else None,
        )
    )
    member_index[0] += 1
    return {
        "key": key,
        "name": custom_name,
        "customName": True,
        "anniversary": make_anniversary(rng, members),
        "address": address,
        "members": members,
    }


def build_staff_household(rng, key, address, member_index):
    staff = [
        ("Maria", "F", "Head"),
        ("David", "M", "Other"),
        ("Priya", "F", "Other"),
        ("Tom", "M", "Other"),
        ("Jen", "F", "Other"),
        ("Sam", "M", "Other"),
    ]
    surname = "Whitfield"
    members = []
    for first_name, gender, role in staff:
        members.append(
            make_member(rng, first_name, surname, gender, role, address, member_index[0])
        )
        member_index[0] += 1
    return {
        "key": key,
        "name": "Staff Household",
        "customName": True,
        "anniversary": None,
        "address": address,
        "members": members,
    }


def build_organization(rng, index):
    kind, template = rng.choice(ORG_NAME_TEMPLATES)
    word = rng.choice(ORG_WORDS)
    word2 = rng.choice([w for w in ORG_WORDS if w != word])
    name = template.format(word=word, word2=word2)
    domain_slug = "".join(ch.lower() for ch in name if ch.isalnum())[:20] or "org{0}".format(index)
    return {
        "key": "O{0:03d}".format(index),
        "name": name,
        "type": kind,
        "website": "https://www.{0}.example.org".format(domain_slug),
        "phone": make_phone(rng),
    }


def build_households(rng):
    households = []
    member_index = [1]
    household_number = 1

    def next_key():
        nonlocal household_number
        key = "H{0:03d}".format(household_number)
        household_number += 1
        return key

    # Guarantee "The Garcia Family" exists and computes naturally (not a
    # custom name), for the admin guide's five minute walkthrough.
    address = make_address(rng)
    households.append(build_family(rng, next_key(), "Garcia", address, member_index))

    # Staff household, so the walkthrough always finds Maria, David, Priya,
    # Tom, Jen, and Sam.
    address = make_address(rng)
    households.append(build_staff_household(rng, next_key(), address, member_index))

    # Three custom-name households (Custom_Name__c = true).
    custom_specs = [
        ("The Reverend and Mrs. Alvarez", "Alvarez", "Rev."),
        ("The Doctors Nguyen", "Nguyen", "Dr."),
        ("The Wilson Family Trust Household", "Wilson", None),
    ]
    for custom_name, surname, title in custom_specs:
        address = make_address(rng)
        households.append(
            build_custom_name_household(
                rng, next_key(), custom_name, surname, address, member_index, title
            )
        )

    # Five households with a deceased member.
    for _ in range(5):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(
            build_family(rng, next_key(), surname, address, member_index, deceased=True)
        )

    # Ten three-generation households.
    for _ in range(10):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(build_three_generation(rng, next_key(), surname, address, member_index))

    # Eight hyphenated-surname households.
    for _ in range(8):
        address = make_address(rng)
        households.append(build_hyphenated(rng, next_key(), address, member_index))

    # Twenty households with differing surnames.
    for _ in range(20):
        address = make_address(rng)
        households.append(build_differing_surnames(rng, next_key(), address, member_index))

    # Forty single-person households.
    for _ in range(40):
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        households.append(build_single(rng, next_key(), surname, address, member_index))

    # Fill the remainder with ordinary same-surname couples, mostly childless
    # (couples who give as a household but have grown children or none),
    # some with one child, a few with two, until we reach 200 households.
    while len(households) < 200:
        surname = rng.choice(SURNAME_POOL)
        address = make_address(rng)
        child_count = random_choice_weighted(
            rng, [(0, 0.82), (1, 0.13), (2, 0.05)]
        )
        households.append(
            build_family(rng, next_key(), surname, address, member_index, child_count=child_count)
        )

    return households


def build_organizations(rng):
    return [build_organization(rng, i) for i in range(1, 26)]


# ---------------------------------------------------------------------------
# Relationships and affiliations (C-15, C-16). Both are Core objects, so they
# ship in the Core payload beside the households they connect. Relationships are
# deliberately between people in different households: two people in the same
# household are already connected by the household itself, and the panel a
# person wants is the one showing the daughter who lives at her own address,
# the friend who introduced them, the colleague on the board.
# ---------------------------------------------------------------------------

RELATIONSHIP_SHAPES = [
    ("Parent", 0.28),
    ("Sibling", 0.2),
    ("Friend", 0.2),
    ("Colleague", 0.16),
    ("Grandparent", 0.1),
    ("Other", 0.06),
]

RELATIONSHIP_DESCRIPTIONS = {
    "Parent": "Lives in her own household; the two keep in close touch.",
    "Sibling": "Introduced by their sibling at the spring event.",
    "Friend": "Long-standing friendship; the two often come to the same events.",
    "Colleague": "They serve on the finance committee together.",
    "Grandparent": "Pays toward the grandchild's tuition every year.",
    "Other": "Met through the volunteer programme.",
}

AFFILIATION_ROLES = [
    ("Board Member", 0.16),
    ("Employee", 0.3),
    ("Volunteer", 0.16),
    ("Executive Director", 0.06),
    ("Owner", 0.08),
    ("Member", 0.16),
    ("Partnerships Manager", 0.08),
]

RELATIONSHIP_COUNT = 60
AFFILIATION_COUNT = 80


def assign_member_keys(households):
    """Stamps every member with a stable key, which is the join between the two files.

    The Giving payload names its donors by these keys and the Core loader writes
    them to `Sample_Data_Key__c`, so the Giving loader can find the person a
    sample gift belongs to without depending on names or on insert order.
    """
    for household in households:
        for position, member in enumerate(household["members"], start=1):
            member["key"] = "{0}-{1}".format(household["key"], position)


def adult_keys_by_household(households):
    """One list of living adult member keys per household, in file order."""
    result = []
    for household in households:
        result.append(
            [
                member["key"]
                for member in household["members"]
                if member["householdRole"] != "Child" and not member.get("deceased")
            ]
        )
    return result


def past_date(rng, earliest_years_ago, latest_years_ago):
    """A date wholly in the past, so no start or end date is dated in the future."""
    year = REFERENCE_YEAR - rng.randint(latest_years_ago, earliest_years_ago)
    if year == REFERENCE_YEAR:
        return "{0:04d}-{1:02d}-{2:02d}".format(year, rng.randint(1, 6), rng.randint(1, 28))
    return "{0:04d}-{1:02d}-{2:02d}".format(year, rng.randint(1, 12), rng.randint(1, 28))


def build_relationships(rng, households):
    adults = adult_keys_by_household(households)
    eligible = [index for index, keys in enumerate(adults) if keys]
    relationships = []
    seen = set()
    attempts = 0
    while len(relationships) < RELATIONSHIP_COUNT and attempts < RELATIONSHIP_COUNT * 40:
        attempts += 1
        first_household = rng.choice(eligible)
        second_household = rng.choice(eligible)
        if first_household == second_household:
            continue
        first = rng.choice(adults[first_household])
        second = rng.choice(adults[second_household])
        pair = tuple(sorted((first, second)))
        if pair in seen:
            continue
        seen.add(pair)
        relationship_type = random_choice_weighted(rng, RELATIONSHIP_SHAPES)
        former = rng.random() < 0.12
        relationships.append(
            {
                "person": first,
                "relatedPerson": second,
                "type": relationship_type,
                "status": "Former" if former else "Current",
                "startDate": past_date(rng, 30, 6) if former else past_date(rng, 30, 1),
                "endDate": past_date(rng, 4, 1) if former else None,
                "description": RELATIONSHIP_DESCRIPTIONS[relationship_type],
            }
        )
    return relationships


def build_affiliations(rng, households, organizations):
    adults = [key for keys in adult_keys_by_household(households) for key in keys]
    organization_keys = [organization["key"] for organization in organizations]
    affiliations = []
    seen_pairs = set()
    people_with_primary = set()
    attempts = 0
    while len(affiliations) < AFFILIATION_COUNT and attempts < AFFILIATION_COUNT * 40:
        attempts += 1
        person = rng.choice(adults)
        organization = rng.choice(organization_keys)
        if (person, organization) in seen_pairs:
            continue
        seen_pairs.add((person, organization))
        former = rng.random() < 0.25
        # The first current affiliation a person gets is their primary one, which
        # is the case rule R-AF3 settles when somebody has several at once.
        primary = not former and person not in people_with_primary
        if primary:
            people_with_primary.add(person)
        affiliations.append(
            {
                "person": person,
                "organization": organization,
                "role": random_choice_weighted(rng, AFFILIATION_ROLES),
                "status": "Former" if former else "Current",
                "isPrimary": primary,
                "startDate": past_date(rng, 22, 6) if former else past_date(rng, 22, 1),
                "endDate": past_date(rng, 4, 1) if former else None,
            }
        )
    return affiliations


# ---------------------------------------------------------------------------
# Giving payload (funds, appeals, commitments, gifts, allocations, soft credits,
# tributes), written as its own static resource in the Giving package so an org
# without Giving never carries it.
#
# Dates here are day offsets from the day the set is loaded, never fixed dates.
# A fixed-date set goes stale: load it eighteen months from now and "Giving This
# Year" is empty, the retention report shows nobody renewing, and the dashboard
# is a wall of zeros. Offsets keep the three-year giving history true whenever
# somebody loads the set.
# ---------------------------------------------------------------------------

GIVING_SEED = 20260908

FUND_SPECS = [
    ("General Fund", "4000", False, "Unrestricted giving: wherever the need is greatest."),
    ("Building Fund", "4100", True, "The capital campaign for the new wing."),
    ("Scholarship Fund", "4200", True, "Named scholarships awarded each August."),
    ("Food Pantry", "4300", True, "Weekly groceries for neighbours who need them."),
    ("Youth Programs", "4400", True, "After-school and summer programmes."),
    ("Emergency Relief", "4500", True, "Rent, utilities and one-off crisis help."),
    ("Endowment", "4600", True, "Permanently restricted: only the income is spent."),
    ("Memorial Fund", "4700", True, "Gifts given in memory of someone."),
]

# Weighted the way a real fund list is: most money is unrestricted, a capital
# campaign takes the next slice, and the small restricted funds share the rest.
FUND_WEIGHTS = [
    ("General Fund", 0.5),
    ("Building Fund", 0.13),
    ("Scholarship Fund", 0.08),
    ("Food Pantry", 0.1),
    ("Youth Programs", 0.07),
    ("Emergency Relief", 0.05),
    ("Endowment", 0.03),
    ("Memorial Fund", 0.04),
]

# (name, parent, goal, cost, days ago it opened, days ago it closed or None, description)
APPEAL_SPECS = [
    (
        "Annual Fund",
        None,
        250000,
        4000,
        1150,
        None,
        "The unrestricted annual giving programme the other appeals roll up into.",
    ),
    (
        "Spring Appeal",
        "Annual Fund",
        40000,
        3200,
        210,
        120,
        "The spring letter, mailed to everyone who gave in the last three years.",
    ),
    (
        "Year-End Appeal",
        "Annual Fund",
        80000,
        6500,
        400,
        300,
        "The December letter and the email series that goes with it.",
    ),
    (
        "Give Local Day",
        "Annual Fund",
        10000,
        500,
        320,
        318,
        "The community giving day, matched by a local business.",
    ),
    ("Spring Gala", None, 60000, 15000, 250, 240, "The ticketed dinner and auction."),
    (
        "Emergency Roof Repair",
        None,
        35000,
        900,
        150,
        60,
        "The emergency appeal after the storm took the roof off the hall.",
    ),
    (
        "Legacy Circle",
        None,
        100000,
        1200,
        900,
        None,
        "Multi-year pledges from long-standing donors.",
    ),
]

GIFT_TYPE_WEIGHTS = [
    ("Check", 0.36),
    ("Card", 0.28),
    ("ACH", 0.14),
    ("Cash", 0.1),
    ("Stock", 0.04),
    ("In-kind", 0.04),
    ("Other", 0.04),
]

IN_KIND_DESCRIPTIONS = [
    "Twelve cases of tinned food for the pantry",
    "A used minibus in working order",
    "Office furniture for the new wing",
    "Printing and postage for the spring letter",
    "Auction lot: a week at a lakeside cabin",
    "Two laptops for the homework club",
]

# Gift sizes as a real list is shaped: many small, a few large.
GIFT_AMOUNT_BANDS = [
    ((25, 100), 0.42),
    ((100, 500), 0.32),
    ((500, 2500), 0.16),
    ((2500, 10000), 0.07),
    ((10000, 50000), 0.03),
]

# How a household gives, which is what the retention and lapsed-donor reports
# are for. The weights are roughly the shape of a small nonprofit's list.
DONOR_PROFILE_WEIGHTS = [
    ("multi_year", 0.24),
    ("lapsed", 0.14),
    ("new", 0.14),
    ("one_time", 0.2),
    ("major", 0.05),
    ("none", 0.23),
]

HISTORY_DAYS = 3 * 365

# Sized so the whole set stays inside the one transaction the remove action runs
# in: see the counts in docs/admin-guide/sample-data.md and the note on limits in
# GivingSampleDataLoader.
RECURRING_COMMITMENT_COUNT = 14
PLEDGE_COMMITMENT_COUNT = 10
MAX_RECURRING_START_DAYS = 480
TRIBUTE_COUNT = 24
RECOGNITION_CREDIT_COUNT = 30
ORGANIZATIONS_THAT_GIVE = 18


def money(rng, low, high):
    """An amount that looks entered rather than generated: round numbers dominate."""
    raw = rng.uniform(low, high)
    if raw < 200:
        return float(int(round(raw / 5.0) * 5))
    if raw < 2000:
        return float(int(round(raw / 25.0) * 25))
    if raw < 10000:
        return float(int(round(raw / 100.0) * 100))
    return float(int(round(raw / 500.0) * 500))


def gift_amount(rng):
    band = random_choice_weighted(rng, GIFT_AMOUNT_BANDS)
    return money(rng, band[0], band[1])


def acknowledgment_for(days_ago, amount):
    """Recent gifts are still waiting to be thanked; older ones have been."""
    if amount < 50:
        return "Not required"
    if days_ago < 21:
        return "To acknowledge"
    return "Acknowledged"


def payment_reference(gift_type, sequence):
    if gift_type == "Check":
        return "Check {0}".format(1000 + sequence)
    if gift_type in ("Card", "ACH"):
        return "TXN-{0:06d}".format(400000 + sequence)
    return None


class GiftBuilder:
    """Builds gifts in file order, numbering each one so it has a stable key."""

    def __init__(self, rng):
        self.rng = rng
        self.gifts = []

    def add(
        self,
        donor,
        days_ago,
        amount,
        appeal=None,
        fund=None,
        gift_type=None,
        status="Received",
        commitment=None,
        split=False,
    ):
        rng = self.rng
        sequence = len(self.gifts) + 1
        if gift_type is None:
            gift_type = random_choice_weighted(rng, GIFT_TYPE_WEIGHTS)
        if fund is None:
            fund = random_choice_weighted(rng, FUND_WEIGHTS)
        gift = {
            "key": "G{0:04d}".format(sequence),
            "donor": donor,
            "daysAgo": days_ago,
            "amount": amount,
            "type": gift_type,
            "status": status,
            "appeal": appeal,
            "acknowledgmentStatus": acknowledgment_for(days_ago, amount),
            "paymentReference": payment_reference(gift_type, sequence),
            "commitment": commitment,
            "allocations": self.allocations(fund, amount, split),
        }
        if gift_type == "In-kind":
            # An in-kind gift is goods rather than money (R-G12, ADR-0029), so the value the
            # profile generated becomes its fair market value and its amount, and the amount of
            # every allocation it carries, is zero. The allocations are still generated above,
            # and still zeroed rather than dropped, so that the random stream, and therefore
            # every other gift in the file, is unchanged by this rule.
            gift["inKindDescription"] = rng.choice(IN_KIND_DESCRIPTIONS)
            gift["fairMarketValue"] = amount
            gift["amount"] = 0.0
            for allocation in gift["allocations"]:
                allocation["amount"] = 0.0
        self.gifts.append(gift)
        return gift

    def allocations(self, fund, amount, split):
        """One allocation, or two where the donor designated the gift twice over."""
        if not split or amount < 200:
            return [{"fund": fund, "amount": amount}]
        second = random_choice_weighted(self.rng, FUND_WEIGHTS)
        if second == fund:
            second = "General Fund" if fund != "General Fund" else "Building Fund"
        first_share = money(self.rng, amount * 0.4, amount * 0.7)
        if first_share <= 0 or first_share >= amount:
            return [{"fund": fund, "amount": amount}]
        return [
            {"fund": fund, "amount": first_share},
            {"fund": second, "amount": round(amount - first_share, 2)},
        ]


def profile_gift_plan(rng, profile):
    """How many gifts a household of this profile gave, and how long ago each was."""
    if profile == "none":
        return []
    if profile == "new":
        return sorted(rng.sample(range(5, 170), rng.randint(1, 2)), reverse=True)
    if profile == "lapsed":
        return sorted(rng.sample(range(520, HISTORY_DAYS), rng.randint(2, 5)), reverse=True)
    if profile == "one_time":
        return [rng.randint(30, HISTORY_DAYS)]
    if profile == "major":
        days = [rng.randint(0, 330), rng.randint(370, 700), rng.randint(740, HISTORY_DAYS)]
        return sorted(days[: rng.randint(2, 3)], reverse=True)
    # multi_year: at least one gift in each of the three years, so the retention
    # report has renewals to count rather than one year of activity.
    days = [rng.randint(10, 330), rng.randint(400, 700), rng.randint(760, HISTORY_DAYS)]
    for _ in range(rng.randint(0, 3)):
        days.append(rng.randint(10, HISTORY_DAYS))
    return sorted(days, reverse=True)


def appeal_for(rng, days_ago):
    """The appeal a gift of that age plausibly came from, or none at all."""
    candidates = []
    for name, _parent, _goal, _cost, opened, closed, _description in APPEAL_SPECS:
        if days_ago > opened:
            continue
        if closed is not None and days_ago < closed - 30:
            continue
        candidates.append(name)
    if not candidates or rng.random() < 0.25:
        return None
    return rng.choice(candidates)


def build_commitments(rng, builder, adults, giving_households, profiles):
    """Pledges and recurring commitments, with the gifts that have paid them so far.

    One recurring commitment is deliberately three months in arrears: its
    payments stop part way along, so the installments it has missed are already
    overdue when the daily job (or the end of the load) next looks at them.
    """
    commitments = []
    candidates = [
        index
        for index in giving_households
        if profiles.get(index) in ("multi_year", "new", "major")
    ]
    rng.shuffle(candidates)
    chosen = candidates[: RECURRING_COMMITMENT_COUNT + PLEDGE_COMMITMENT_COUNT]

    for position, index in enumerate(chosen):
        donor = rng.choice(adults[index])
        key = "C{0:03d}".format(position + 1)
        if position < RECURRING_COMMITMENT_COUNT:
            amount = money(rng, 10, 250)
            start_days_ago = rng.randint(120, MAX_RECURRING_START_DAYS)
            months_elapsed = max(start_days_ago // 30, 1)
            status = "Active"
            end_days_ago = None
            paid_months = months_elapsed
            if position == 0:
                # The lapsed monthly donor: three payments missed and counting.
                paid_months = max(months_elapsed - 3, 1)
            elif position == 1:
                status = "Paused"
                paid_months = max(months_elapsed - 2, 1)
            elif position == 2:
                status = "Cancelled"
                end_days_ago = 30
                paid_months = max(months_elapsed - 1, 1)
            commitments.append(
                {
                    "key": key,
                    "donor": donor,
                    "type": "Recurring",
                    "frequency": "Monthly",
                    "amount": amount,
                    "expectedTotal": None,
                    "installmentsPlanned": None,
                    "startDaysAgo": start_days_ago,
                    "endDaysAgo": end_days_ago,
                    "dayOfMonth": rng.choice([1, 5, 10, 15, 20, 28]),
                    "status": status,
                    "fund": random_choice_weighted(rng, FUND_WEIGHTS),
                    "appeal": None,
                }
            )
            for payment in range(paid_months):
                builder.add(
                    donor,
                    start_days_ago - payment * 30,
                    amount,
                    gift_type=rng.choice(["ACH", "Card"]),
                    commitment=key,
                )
        else:
            installment_amount = money(rng, 250, 2500)
            planned = rng.choice([4, 6, 8, 12])
            frequency = rng.choice(["Quarterly", "Monthly"])
            step = 90 if frequency == "Quarterly" else 30
            start_days_ago = rng.randint(step * 2, step * planned)
            paid = min(planned, max(1, start_days_ago // step))
            commitments.append(
                {
                    "key": key,
                    "donor": donor,
                    "type": "Pledge",
                    "frequency": frequency,
                    "amount": installment_amount,
                    "expectedTotal": installment_amount * planned,
                    "installmentsPlanned": planned,
                    "startDaysAgo": start_days_ago,
                    "endDaysAgo": None,
                    "dayOfMonth": rng.choice([1, 15]),
                    "status": "Completed" if paid >= planned else "Active",
                    "fund": random_choice_weighted(rng, FUND_WEIGHTS),
                    "appeal": "Legacy Circle",
                }
            )
            for payment in range(paid):
                builder.add(
                    donor,
                    start_days_ago - payment * step,
                    installment_amount,
                    appeal="Legacy Circle",
                    gift_type="Check",
                    commitment=key,
                )
    return commitments


def reversal_of(builder, original, reason, days_ago):
    """The negative gift that reverses one original, with its allocations mirrored."""
    return {
        "key": "G{0:04d}".format(len(builder.gifts) + 1),
        "donor": original["donor"],
        "daysAgo": days_ago,
        "amount": -original["amount"],
        "type": original["type"],
        "status": "Received",
        "appeal": original["appeal"],
        "acknowledgmentStatus": "Not required",
        "paymentReference": None,
        "commitment": None,
        "originalGift": original["key"],
        "refundReason": reason,
        "allocations": [
            {"fund": allocation["fund"], "amount": -allocation["amount"]}
            for allocation in original["allocations"]
        ],
    }


def build_pending_and_reversed(rng, builder, adults, giving_households):
    """Gifts that are not simply money in the bank: pending, refunded, written off.

    The refunds and the write-off are recorded the way G-04 records them: the
    original keeps its own amount and takes a reversed status, and a linked
    negative gift carries the money back out, so the ADR-0022 rollup behaviour (a
    gift given once and refunded in full reads as one gift and a total of zero)
    is visible in the set rather than only in a test.
    """
    donors = [rng.choice(adults[index]) for index in rng.sample(giving_households, 9)]

    for donor in donors[:6]:
        builder.add(donor, rng.randint(3, 45), gift_amount(rng), status="Pending")

    reasons = [
        "Card charged twice at the gala: the second charge was returned.",
        "Donor asked for the gift back after a change in circumstances.",
    ]
    for position, donor in enumerate(donors[6:8]):
        original = builder.add(
            donor, rng.randint(60, 200), money(rng, 250, 1500), status="Refunded"
        )
        builder.gifts.append(
            reversal_of(builder, original, reasons[position], rng.randint(5, 50))
        )

    original = builder.add(
        donors[8], rng.randint(200, 400), money(rng, 500, 2500), status="Written off"
    )
    builder.gifts.append(
        reversal_of(
            builder,
            original,
            "Pledged at the gala and never collected: written off at year end.",
            rng.randint(10, 90),
        )
    )


def build_tributes(rng, builder, households):
    """Memorials and gifts in honour of someone, attached to gifts already built.

    A memorial names the person who died and notifies somebody else: notifying
    the honoree is what rule R-TR6 refuses, so the set never asks for it.
    """
    deceased = []
    for household in households:
        for member in household["members"]:
            if not member.get("deceased"):
                continue
            others = [
                other["key"] for other in household["members"] if other["key"] != member["key"]
            ]
            if others:
                deceased.append((member, others[0]))

    living_adults = [
        member
        for household in households
        for member in household["members"]
        if member["householdRole"] != "Child" and not member.get("deceased")
    ]

    eligible = [
        gift
        for gift in builder.gifts
        if gift["status"] == "Received"
        and gift["amount"] > 0
        and gift.get("commitment") is None
        and gift.get("originalGift") is None
    ]
    chosen = rng.sample(eligible, min(TRIBUTE_COUNT, len(eligible)))

    tributes = []
    for position, gift in enumerate(chosen):
        if position % 2 == 0 and deceased:
            honoree, recipient = deceased[position % len(deceased)]
            tributes.append(
                {
                    "gift": gift["key"],
                    "type": "In memory of",
                    "honoreePerson": honoree["key"],
                    "recipientPerson": recipient,
                    "message": "Given in loving memory of {0} {1}.".format(
                        honoree["firstName"], honoree["lastName"]
                    ),
                }
            )
        else:
            honoree = living_adults[position % len(living_adults)]
            tributes.append(
                {
                    "gift": gift["key"],
                    "type": "In honor of",
                    "honoreePerson": honoree["key"],
                    "recipientPerson": None,
                    "message": "In honour of {0} {1}, with thanks.".format(
                        honoree["firstName"], honoree["lastName"]
                    ),
                }
            )
    return tributes


def build_soft_credits(rng, builder, adults, giving_households):
    """The recognition credits staff enter by hand: the solicitor, the influencer.

    Household member credits are deliberately not here. Those are written by the
    automatic soft credit rule as each gift is inserted, so putting them in the
    file would only duplicate what the product already does, and would leave two
    credits behind where the rule expects one.
    """
    solicitors = [rng.choice(adults[index]) for index in rng.sample(giving_households, 6)]
    large_gifts = [
        gift for gift in builder.gifts if gift["amount"] >= 1000 and gift["status"] == "Received"
    ]
    chosen = rng.sample(large_gifts, min(RECOGNITION_CREDIT_COUNT, len(large_gifts)))
    credits = []
    for position, gift in enumerate(chosen):
        solicitor = solicitors[position % len(solicitors)]
        if solicitor == gift["donor"]:
            continue
        credits.append(
            {
                "gift": gift["key"],
                "person": solicitor,
                "role": "Solicitor" if position % 3 else "Influencer",
                "amount": gift["amount"],
            }
        )
    return credits


def build_giving(rng, households, organizations):
    """The whole Giving payload, built against the households the Core set creates."""
    funds = [
        {
            "key": name,
            "name": name,
            "accountingCode": code,
            "restricted": restricted,
            "active": True,
            "description": description,
        }
        for name, code, restricted, description in FUND_SPECS
    ]
    appeals = [
        {
            "key": name,
            "name": name,
            "parent": parent,
            "goal": goal,
            "cost": cost,
            "startDaysAgo": opened,
            "endDaysAgo": closed,
            "active": closed is None,
            "description": description,
        }
        for name, parent, goal, cost, opened, closed, description in APPEAL_SPECS
    ]

    adults = adult_keys_by_household(households)
    giving_households = [index for index, keys in enumerate(adults) if keys]
    builder = GiftBuilder(rng)

    profiles = {}
    for index in giving_households:
        profiles[index] = random_choice_weighted(rng, DONOR_PROFILE_WEIGHTS)
    # The walkthrough household gives across all three years, so the admin guide
    # can send a reader to one household and know what they will find there.
    profiles[0] = "multi_year"

    for index in giving_households:
        donor = rng.choice(adults[index])
        profile = profiles[index]
        for days_ago in profile_gift_plan(rng, profile):
            amount = money(rng, 5000, 50000) if profile == "major" else gift_amount(rng)
            builder.add(
                donor,
                days_ago,
                amount,
                appeal=appeal_for(rng, days_ago),
                split=rng.random() < 0.12,
            )

    # Organizations: grants, sponsorships and business gifts, which is what makes
    # the organization half of the dashboard worth looking at.
    for organization in organizations[:ORGANIZATIONS_THAT_GIVE]:
        for _ in range(rng.randint(1, 3)):
            days_ago = rng.randint(20, HISTORY_DAYS)
            builder.add(
                organization["key"],
                days_ago,
                money(rng, 2500, 40000),
                appeal=appeal_for(rng, days_ago),
                gift_type=random_choice_weighted(
                    rng, [("Grant", 0.5), ("Check", 0.35), ("Stock", 0.15)]
                ),
                split=rng.random() < 0.2,
            )

    commitments = build_commitments(rng, builder, adults, giving_households, profiles)
    build_pending_and_reversed(rng, builder, adults, giving_households)
    tributes = build_tributes(rng, builder, households)
    soft_credits = build_soft_credits(rng, builder, adults, giving_households)

    return {
        "funds": funds,
        "appeals": appeals,
        "commitments": commitments,
        "gifts": builder.gifts,
        "tributes": tributes,
        "softCredits": soft_credits,
    }


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=None, separators=(",", ":"), sort_keys=False)
        handle.write("\n")
    return path.stat().st_size


def main():
    households = build_households(RNG)
    organizations = build_organizations(RNG)
    assign_member_keys(households)
    relationships = build_relationships(RNG, households)
    affiliations = build_affiliations(RNG, households, organizations)

    total_members = sum(len(h["members"]) for h in households)

    core = {
        "households": households,
        "organizations": organizations,
        "relationships": relationships,
        "affiliations": affiliations,
    }
    giving = build_giving(random.Random(GIVING_SEED), households, organizations)

    core_size = write_json(OUTPUT_PATH, core)
    giving_size = write_json(GIVING_OUTPUT_PATH, giving)

    allocations = sum(len(gift["allocations"]) for gift in giving["gifts"])
    print("Wrote {0}".format(OUTPUT_PATH))
    print("Households: {0}".format(len(households)))
    print("Contacts: {0}".format(total_members))
    print("Organizations: {0}".format(len(organizations)))
    print("Relationships: {0}".format(len(relationships)))
    print("Affiliations: {0}".format(len(affiliations)))
    print("File size: {0} bytes ({1:.1f} KB)".format(core_size, core_size / 1024.0))
    print("Wrote {0}".format(GIVING_OUTPUT_PATH))
    print("Funds: {0}".format(len(giving["funds"])))
    print("Appeals: {0}".format(len(giving["appeals"])))
    print("Commitments: {0}".format(len(giving["commitments"])))
    print("Gifts: {0}".format(len(giving["gifts"])))
    print("Gift allocations: {0}".format(allocations))
    print("Tributes: {0}".format(len(giving["tributes"])))
    print("Soft credits: {0}".format(len(giving["softCredits"])))
    print("File size: {0} bytes ({1:.1f} KB)".format(giving_size, giving_size / 1024.0))


if __name__ == "__main__":
    main()
