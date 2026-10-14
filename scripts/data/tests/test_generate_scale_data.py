"""Unit tests for scripts/data/generate-scale-data.py (small volumes, no org)."""

import csv
import importlib.util
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "generate-scale-data.py"
spec = importlib.util.spec_from_file_location("generate_scale_data", SCRIPT)
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)


def read(path):
    with open(path, newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def run_tier1(out, households=400, contacts=1000, gifts=3000, no_default_fund=False):
    gen.generate_tier1(
        Namespace(
            out_dir=str(out), households=households, contacts=contacts, gifts=gifts,
            no_default_fund=no_default_fund,
        )
    )


class Tier1Tests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = Path(cls.tmp.name)
        run_tier1(cls.out)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_shape(self):
        self.assertEqual(len(read(self.out / "households.csv")), 400)
        self.assertEqual(len(read(self.out / "contacts.csv")), 1000)
        self.assertEqual(len(read(self.out / "gifts.csv")), 3000)
        sizes = {}
        for row in read(self.out / "contacts.csv"):
            sizes[row["Household_Key"]] = sizes.get(row["Household_Key"], 0) + 1
        self.assertEqual(max(sizes.values()), 30)

    def test_household_addresses_unique(self):
        streets = [r["BillingStreet"] for r in read(self.out / "households.csv")]
        self.assertEqual(len(streets), len(set(streets)))
        numbers = [s.split(" ", 1)[0] for s in streets]
        self.assertEqual(len(numbers), len(set(numbers)))

    def test_contact_identity_unique(self):
        rows = read(self.out / "contacts.csv")
        for column in ("Email", "Phone"):
            values = [r[column] for r in rows]
            self.assertEqual(len(values), len(set(values)), column)
        names = [(r["FirstName"], r["LastName"]) for r in rows]
        self.assertEqual(len(names), len(set(names)))

    def test_phone_unique_across_blocks(self):
        phones = {gen.contact_phone(i) for i in range(25000)}
        self.assertEqual(len(phones), 25000)

    def test_default_fund_flag(self):
        funds = read(self.out / "funds.csv")
        defaults = [f for f in funds if f["Is_Default__c"] == "true"]
        self.assertEqual([f["Name"] for f in defaults], ["Scale test General"])
        self.assertTrue(all(f["Active__c"] == "true" for f in funds))
        with tempfile.TemporaryDirectory() as other:
            run_tier1(Path(other), no_default_fund=True)
            funds = read(Path(other) / "funds.csv")
            self.assertTrue(all(f["Is_Default__c"] == "false" for f in funds))

    def test_no_allocations_file(self):
        self.assertFalse((self.out / "allocations.csv").exists())

    def test_splits_and_chunks(self):
        splits = read(self.out / "splits.csv")
        self.assertEqual(len(splits), round(3000 * gen.SPLIT_SHARE))
        gift_ids = {r["External_Id__c"] for r in read(self.out / "gifts.csv")}
        for row in splits:
            self.assertIn(row["Gift_External_Id"], gift_ids)
            self.assertNotEqual(row["Second_Fund_Code"], gen.FUND_CODES[0])
        scripts = sorted((self.out / "split-apex").glob("split-*.apex"))
        self.assertEqual(len(scripts), -(-len(splits) // gen.SPLIT_CHUNK))
        text = "\n".join(p.read_text(encoding="utf-8") for p in scripts)
        for row in splits:
            self.assertIn("'%s' => '%s'" % (row["Gift_External_Id"], row["Second_Fund_Code"]), text)

    def test_apex_keeps_the_gift_whole(self):
        apex = gen.render_split_apex([["SCALE-G-0000001", "SCALE-PROG"]])
        self.assertIn("AutomationControl.bypass('Gift_Allocation_Totals')", apex)
        self.assertIn("GiftService.validateAllocations(splitGiftIds)", apex)
        self.assertIn("Database.rollback(sp)", apex)
        self.assertIn("g.Amount__c - primary", apex)  # the second row is the remainder
        self.assertIn("* 70 / 100", apex)
        self.assertNotIn("%", apex.replace("%s", ""))  # no unformatted placeholder left

    def test_chunking(self):
        rows = [["G%d" % i, "F"] for i in range(450)]
        chunks = gen.split_rows_to_chunks(rows)
        self.assertEqual([len(c) for c in chunks], [200, 200, 50])


class ResolveTests(unittest.TestCase):
    def write(self, path, header, rows):
        gen.write_csv(path, header, rows)

    def test_drops_counted_and_filtered(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = Path(tmp)
            self.write(tmp / "soft.csv", ["Gift__r.External_Id__c", "Contact_Key", "Amount__c"],
                       [["G1", "C1", "1"], ["G2", "C1", "2"], ["G3", "C9", "3"], ["G1", "C2", "4"]])
            self.write(tmp / "contacts.csv", ["Id", "Sample_Data_Key__c"], [["003A", "C1"]])
            self.write(tmp / "gifts.csv", ["External_Id__c"], [["G1"], ["G3"]])
            args = Namespace(
                resolve=str(tmp / "soft.csv"), out=str(tmp / "out.csv"), map=str(tmp / "contacts.csv"),
                key_col="Contact_Key", id_col="Contact__c", const=[],
                only_col="Gift__r.External_Id__c", only_from=str(tmp / "gifts.csv"),
            )
            kept, missing, not_loaded = gen.resolve(args)
            self.assertEqual((kept, missing, not_loaded), (1, 2, 1))
            self.assertEqual(len(read(tmp / "out.csv")), 1)


if __name__ == "__main__":
    unittest.main()
