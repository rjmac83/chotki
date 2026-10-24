#!/usr/bin/env python3
"""Exercise the real Swift core boundary without writing the human review record."""

from datetime import date, datetime, timedelta
import json
import math
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import uuid


def long_date(day: date) -> str:
    weekdays = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    months = ["January", "February", "March", "April", "May", "June",
              "July", "August", "September", "October", "November", "December"]
    return f"{weekdays[day.weekday()]} {day.day} {months[day.month - 1]}"


def conversation(helper: str, mode: str, environment=None):
    process = subprocess.Popen(
        [helper, mode], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, env=environment,
    )
    next_id = 0

    def ask(operation, **fields):
        nonlocal next_id
        next_id += 1
        request = {"v": 1, "id": next_id, "op": operation, **fields}
        process.stdin.write(json.dumps(request) + "\n")
        process.stdin.flush()
        line = process.stdout.readline()
        assert line, f"helper ended during {operation}: {process.stderr.read()}"
        response = json.loads(line)
        assert response["v"] == 1 and response["id"] == next_id, response
        return response

    return process, ask


def close(process):
    process.stdin.close()
    assert process.wait(timeout=5) == 0, process.stderr.read()


def occurrence_count(directory):
    connection = sqlite3.connect(Path(directory) / "chotki.sqlite")
    count = connection.execute("select count(*) from occurrence").fetchone()[0]
    connection.close()
    return count


def occurrence_status(directory, rule_id, date):
    connection = sqlite3.connect(Path(directory) / "chotki.sqlite")
    row = connection.execute(
        "select status, completed_at from occurrence where rule_id = ? and date = ?",
        (rule_id, date),
    ).fetchone()
    connection.close()
    return None if row is None else row


def insert_skipped(directory, rule_id, date):
    connection = sqlite3.connect(Path(directory) / "chotki.sqlite")
    connection.execute(
        "insert into occurrence (id, rule_id, date, status, completed_at, moved_to) "
        "values (?, ?, ?, 'skipped', null, null)",
        (str(uuid.uuid4()), rule_id, date),
    )
    connection.commit()
    connection.close()


def completed_at(directory, rule_id):
    connection = sqlite3.connect(Path(directory) / "chotki.sqlite")
    row = connection.execute(
        "select completed_at from occurrence where rule_id = ? and status = 'completed'",
        (rule_id,),
    ).fetchone()
    connection.close()
    return None if row is None else row[0]


def main():
    helper = sys.argv[1]
    human_review = Path.home() / ".cache" / "chotki-linux-review" / "chotki.sqlite"
    human_before = human_review.stat().st_mtime_ns if human_review.exists() else None

    with tempfile.TemporaryDirectory(prefix="chotki-review-check-") as review_dir:
        environment = os.environ.copy()
        environment["CHOTKI_LINUX_REVIEW_DIR"] = review_dir
        review, ask = conversation(helper, "--review", environment)
        assert ask("hello")["mode"] == "review"
        first = ask("snapshot")
        assert first["ok"] and first["psalmOneVerses"] == 6
        assert first["entries"] and len(first["week"]) == 57
        assert first["week"][28]["date"] == first["selectedDate"]
        assert first["week"][28]["selected"]
        assert first["selectedDate"] == first["today"]
        assert "todayLink" not in first
        assert len(first["month"]) == 42
        inside = [day for day in first["month"] if day["inMonth"]]
        assert 28 <= len(inside) <= 31
        prefix = inside[0]["date"][:7]
        assert all(day["date"].startswith(prefix) for day in inside)
        assert all(not day["fast"] for day in first["month"] if day["weekday"] == 1)
        assert first["monthTitle"].endswith(prefix[:4])
        shown = ask("setMonthShown", shown=True)
        assert shown["ok"] and shown["monthTitle"] == first["monthTitle"]
        assert shown["selectedDate"] == first["selectedDate"]
        assert "todayLink" not in shown
        shifted = ask("shiftMonth", direction=1)
        assert shifted["ok"] and shifted["monthTitle"] != first["monthTitle"]
        assert shifted["selectedDate"] == first["selectedDate"]
        assert 28 <= len([day for day in shifted["month"] if day["inMonth"]]) <= 31
        assert "todayLink" in shifted
        restored = ask("shiftMonth", direction=-1)
        assert restored["monthTitle"] == first["monthTitle"]
        assert restored["selectedDate"] == first["selectedDate"]
        assert "todayLink" not in restored
        pan = ask("noteSayingPan", name="sayings/01.jpg")
        assert isinstance(pan["sayingPanStart"], float)
        assert not (Path(review_dir) / "saying-pan").exists()
        again = ask("noteSayingPan", name="sayings/01.jpg")
        assert again["sayingPanStart"] == pan["sayingPanStart"]
        by_title = {item["title"]: item for item in first["entries"]}
        assert by_title["Morning prayers"]["destination"] == "prayers"
        assert by_title["Morning prayers"]["selection"] == "morning"
        assert by_title["Morning prayers"]["action"] == "Read the Prayers"
        assert by_title["Morning prayers"]["stoodDown"] is False
        assert by_title["Evening prayers"]["destination"] == "prayers"
        assert by_title["Evening prayers"]["selection"] == "evening"
        assert by_title["The Jesus Prayer"]["destination"] == "rope"
        assert by_title["The Jesus Prayer"]["selection"] == "jesus-prayer"
        assert by_title["The Jesus Prayer"]["action"] == "Go to the Rope"
        assert by_title["Morning prayers"]["glossarySlug"] == "prayer-rule"
        assert by_title["The Jesus Prayer"]["glossarySlug"] == "jesus-prayer"
        assert by_title["The day's Gospel"]["glossarySlug"] == "gospel"
        assert by_title["The day's Gospel"]["destination"] == "reading"
        assert by_title["The day's Gospel"]["band"] == 0
        assert by_title["The day's Gospel"]["action"] == "Read the Day\u2019s Readings"
        assert by_title["The life of the day's saint"]["destination"] == "reading"
        assert by_title["The life of the day's saint"]["band"] == 4
        assert by_title["The life of the day's saint"]["action"] == "Read the Saint\u2019s Life"
        assert by_title["A kathisma of the Psalter"]["destination"] == "psalter"
        assert by_title["A kathisma of the Psalter"]["action"] == "Read Today\u2019s Kathisma"
        paged = ask("shiftWeek", direction=1)
        assert paged["selectedDate"] == first["today"]
        assert "todayLink" not in paged
        ask("shiftWeek", direction=-1)
        entry = next(item for item in first["entries"] if not item["dispensed"])
        changed = ask("toggleKept", ruleID=entry["id"])
        changed_entry = next(item for item in changed["entries"] if item["id"] == entry["id"])
        assert changed_entry["kept"] != entry["kept"]
        if changed_entry["kept"]:
            assert completed_at(review_dir, entry["id"])
        restored = ask("toggleKept", ruleID=entry["id"])
        restored_entry = next(item for item in restored["entries"] if item["id"] == entry["id"])
        assert restored_entry["kept"] == entry["kept"]
        if restored_entry["kept"]:
            assert completed_at(review_dir, entry["id"])
        wednesday = ask("selectDate", date="2026-10-07")
        fasting = next(item for item in wednesday["entries"]
                       if item["title"] == "The Wednesday and Friday fast")
        assert fasting["destination"] == "fast" and fasting["dispensed"] is False
        assert fasting["back"] == (
            "The ordinary weekly fast, kept most Wednesdays and Fridays of the year."
        )
        if wednesday["today"] == "2026-10-07":
            assert "todayLink" not in wednesday
        elif "2026-10-07" > wednesday["today"]:
            assert wednesday["todayLink"] == "\u2190 Today"
        else:
            assert wednesday["todayLink"] == "Today \u2192"
        thursday = ask("selectDate", date="2026-10-08")
        evening = next(item for item in thursday["entries"] if item["title"] == "Evening prayers")
        late = ask("markKeptLate", ruleID=evening["id"])
        assert late["ok"] and "thanksgiving" not in late
        late_row = next(item for item in late["entries"] if item["id"] == evening["id"])
        assert late_row["kept"] is True and late_row["stoodDown"] is False
        late_status, late_at = occurrence_status(review_dir, evening["id"], "2026-10-08")
        assert late_status == "completedLate" and late_at
        stood_down = ask("standDownDay", ruleID=evening["id"])
        assert "thanksgiving" not in stood_down
        stood_row = next(item for item in stood_down["entries"] if item["id"] == evening["id"])
        assert stood_row["kept"] is False and stood_row["stoodDown"] is True
        stood_status, stood_at = occurrence_status(review_dir, evening["id"], "2026-10-08")
        assert stood_status == "skipped" and stood_at is None
        ask("toggleKept", ruleID=evening["id"])
        cleared = ask("toggleKept", ruleID=evening["id"])
        assert cleared["ok"]
        assert occurrence_status(review_dir, evening["id"], "2026-10-08") is None
        cleared_row = next(item for item in cleared["entries"] if item["id"] == evening["id"])
        assert cleared_row["kept"] is False and cleared_row["stoodDown"] is False
        unknown_day = ask("standDownDay", ruleID="00000000-0000-0000-0000-000000000000")
        assert not unknown_day["ok"] and "not on the selected day" in unknown_day["error"]
        calendar_day = ask("selectDate", date="2026-10-06")
        assert calendar_day["dayTitle"] and calendar_day["observedDate"]
        assert all("fast" in day and "feast" in day and "settled" in day
                   for day in calendar_day["week"])
        bright_week = ask("selectDate", date="2027-05-05")
        fast = next(item for item in bright_week["entries"]
                    if item["title"] == "The Wednesday and Friday fast")
        assert fast["dispensed"]
        refused = ask("toggleKept", ruleID=fast["id"])
        assert not refused["ok"]
        assert "asked" in refused["error"]
        refused_late = ask("markKeptLate", ruleID=fast["id"])
        assert not refused_late["ok"] and "asked" in refused_late["error"]
        refused_down = ask("standDownDay", ruleID=fast["id"])
        assert not refused_down["ok"] and "asked" in refused_down["error"]
        assert fast["destination"] == "fast"
        assert fast["back"] == "Not observed during Bright Week."
        missing = ask("toggleKept", ruleID="00000000-0000-0000-0000-000000000000")
        assert not missing["ok"]
        assert "not on the selected day" in missing["error"]
        shifted = ask("shiftWeek", direction=1)
        assert shifted["selectedDate"] == bright_week["selectedDate"]
        assert shifted["week"][0]["date"] != bright_week["week"][0]["date"]
        if shifted["selectedDate"] == shifted["today"]:
            assert "todayLink" not in shifted
        else:
            expected_link = ("\u2190 Today" if shifted["selectedDate"] > shifted["today"]
                             else "Today \u2192")
            assert shifted["todayLink"] == expected_link
        assert not ask("selectDate", date="not-a-date")["ok"]

        before_prayer = occurrence_count(review_dir)
        prayer = ask("prayer", diameter=240)["prayer"]
        assert prayer["selection"] == "jesus-prayer"
        assert prayer["ropeAlone"] is False
        assert prayer["count"] == 0 and prayer["target"] == 33
        assert prayer["showsRope"] is True and prayer["complete"] is False
        assert prayer["words"][0]["paragraphs"] == [
            "Lord Jesus Christ, Son of God, have mercy on me, a sinner."
        ]
        assert prayer["words"][0]["centred"] is True
        assert len(prayer["knots"]) == 33 and len(prayer["beads"]) == 4
        assert prayer["knots"][0]["mark"] == "next"
        assert prayer["beads"][0]["passed"] is True
        assert prayer["beads"][1]["passed"] is False
        assert 0 < prayer["dot"] <= 11
        assert abs(prayer["bead"] - prayer["dot"] * 1.4) < 1e-6
        assert all(0 <= knot["x"] <= 240 and 0 <= knot["y"] <= 240 for knot in prayer["knots"])
        smaller = ask("prayer", diameter=100)["prayer"]
        assert smaller["dot"] < prayer["dot"]

        base = 1_700_000_000
        sounds = []
        for step in range(33):
            counted = ask("advancePrayer", now=base + step)["prayer"]
            assert counted["count"] == step + 1
            assert counted["advanced"] is True
            sounds.append(counted["sound"])
        assert sounds[0] == "tick"
        assert sounds[9] == "tock" and sounds[19] == "tock" and sounds[29] == "tock"
        assert sounds[32] == "bell"
        assert counted["complete"] is True and counted["cue"] == "bell"
        assert counted["knots"][0]["mark"] == "counted"
        assert "next" not in {knot["mark"] for knot in counted["knots"]}
        held = ask("advancePrayer", now=base + 100)["prayer"]
        assert held["count"] == 33 and held["advanced"] is False and "sound" not in held
        returned = ask("prayer")["prayer"]
        assert returned["count"] == 33

        ask("startAgain")
        first = ask("advancePrayer", now=base)["prayer"]
        refused = ask("advancePrayer", now=base + 0.2)["prayer"]
        assert first["count"] == 1 and first["sound"] == "tick"
        assert refused["count"] == 1 and refused["advanced"] is False and "sound" not in refused
        assert ask("prayer")["prayer"]["count"] == 1

        alone = ask("choosePrayer", selection=None)["prayer"]
        assert alone["ropeAlone"] is True and alone["selection"] == ""
        assert alone["showsRope"] is True and alone["words"] == [] and alone["count"] == 1
        morning = ask("choosePrayer", selection="morning")["prayer"]
        assert morning["showsRope"] is False and morning["count"] == 1
        assert len(morning["words"]) == 11
        assert morning["words"][0]["title"] == "The Opening Prayer"
        assert morning["words"][0]["centred"] is False
        assert ask("showRope", shown=True)["prayer"]["showsRope"] is True
        jesus = ask("choosePrayer", selection="jesus-prayer")["prayer"]
        assert jesus["showsRope"] is True and jesus["selection"] == "jesus-prayer"
        aimed = ask("aimPrayer", target=100)["prayer"]
        assert aimed["target"] == 100 and aimed["count"] == 0 and len(aimed["beads"]) == 10
        assert not ask("aimPrayer", target=12)["ok"]
        unknown = ask("choosePrayer", selection="not-a-prayer")
        assert not unknown["ok"] and "not in the book" in unknown["error"]

        opening = ask("opening")["opening"]
        assert len(opening["knots"]) == 11 and opening["knotSlots"] == 12
        assert abs(opening["knotRadius"] - 0.042) < 1e-9
        assert abs(opening["build"] - 1.8) < 1e-9
        assert abs(opening["hold"] - 1.5) < 1e-9
        assert abs(opening["fade"] - 0.4) < 1e-9
        assert abs(opening["knotFade"] - 0.16) < 1e-9
        assert abs(opening["staggerLead"] - 0.2) < 1e-9
        angle = math.pi / 2 + (1 / 12) * 2 * math.pi
        assert abs(opening["knots"][0]["x"] - (0.5 + 0.30 * math.cos(angle))) < 1e-6
        assert abs(opening["knots"][0]["y"] - (0.36 + 0.30 * math.sin(angle))) < 1e-6
        assert len(opening["bars"]) == 3
        assert abs(opening["footrest"]["leadingX"] - 0.209) < 1e-9
        assert abs(opening["box"]["height"] - 0.34) < 1e-9
        tones = ask("tones")["tones"]
        for name in ("tick", "tock", "bell"):
            assert Path(tones[name]).read_bytes()[:4] == b"RIFF"
        assert ask("tones")["tones"] == tones
        assert occurrence_count(review_dir) == before_prayer

        day = ask("selectDate", date="2026-10-06")
        gospel = next(item for item in day["entries"] if item["title"] == "The day's Gospel")
        epistle = next(item for item in day["entries"] if item["title"] == "The day's Epistle")
        life_rule = next(item for item in day["entries"] if item["title"] == "The life of the day's saint")
        psalter_rule = next(item for item in day["entries"] if item["title"] == "A kathisma of the Psalter")
        assert not gospel["kept"] and not epistle["kept"] and not life_rule["kept"]
        closed = ask("reading")["reading"]
        assert closed["marked"] == []
        assert all(not section["open"] for section in closed["sections"])
        titles = [section["title"] for section in closed["sections"]]
        for title in ("The day's Gospel", "The day's Epistle", "Vespers", "Matins",
                      "The life of the day's saint"):
            assert title in titles, titles
        assert "¶" not in json.dumps(closed)
        before_reading = occurrence_count(review_dir)
        texts = []
        for band in (0, 1, 2, 3, 4):
            opened = ask("openReading", band=band)["reading"]
            assert opened["marked"] == []
            assert [section["band"] for section in opened["sections"] if section["open"]] == [band]
            section = next(item for item in opened["sections"] if item["band"] == band)
            if band == 4:
                life = section["life"]
                assert life["available"] is True
                assert "/" in life["dates"]
                assert life["license"] == "CC BY-SA 4.0"
                assert "unchanged" in life["licenseNote"]
                assert life["sections"]
            else:
                assert section["passages"]
                for passage in section["passages"]:
                    assert passage["text"] and "¶" not in passage["text"]
                    texts.append(passage["text"])
        assert any("\n\n" in text for text in texts)
        assert occurrence_count(review_dir) == before_reading
        both = ask("toggleReading", band=0)["reading"]
        assert sorted(section["band"] for section in both["sections"] if section["open"]) == [0, 4]

        finished = ask("finishReading", band=0)
        assert gospel["id"] in finished["reading"]["marked"]
        assert epistle["id"] not in finished["reading"]["marked"]
        assert next(item for item in finished["entries"] if item["id"] == gospel["id"])["kept"]
        assert not next(item for item in finished["entries"] if item["id"] == epistle["id"])["kept"]
        assert completed_at(review_dir, gospel["id"])
        insert_skipped(review_dir, epistle["id"], "2026-10-06")
        stood = ask("finishReading", band=1)
        assert epistle["id"] not in stood["reading"]["marked"]
        assert occurrence_status(review_dir, epistle["id"], "2026-10-06") == ("skipped", None)
        kept_life = ask("finishReading", band=4)
        assert life_rule["id"] in kept_life["reading"]["marked"]
        assert next(item for item in kept_life["entries"] if item["id"] == life_rule["id"])["kept"]

        bright = ask("selectDate", date="2027-05-05")
        fast = next(item for item in bright["entries"] if item["title"] == "The Wednesday and Friday fast")
        assert fast["dispensed"] and not fast["kept"]
        dispensed = ask("finishReading", band=0)
        assert fast["id"] not in dispensed["reading"]["marked"]
        fast_after = next(item for item in dispensed["entries"] if item["id"] == fast["id"])
        assert fast_after["dispensed"] and not fast_after["kept"]
        assert occurrence_status(review_dir, fast["id"], "2027-05-05") is None
        assert next(item for item in dispensed["entries"] if item["title"] == "The day's Gospel")["kept"]
        bright_psalter = ask("psalter")["psalter"]
        assert bright_psalter["season"] == "brightWeek" and bright_psalter["appointed"] == []
        assert "Bright Week" in bright_psalter["note"]
        manual = ask("openKathisma", kathisma=20, manual=True)["psalter"]
        assert manual["marked"] == [] and manual["manual"] == 20
        numbers = [psalm["number"] for psalm in manual["manualKathisma"]["psalms"]]
        assert numbers[0] == 143 and numbers[-1] == 150 and 151 not in numbers

        ask("selectDate", date="2026-10-06")
        kathisma = ask("openKathisma", kathisma=1, manual=True)["psalter"]
        assert kathisma["marked"] == []
        assert [psalm["number"] for psalm in kathisma["manualKathisma"]["psalms"]] == list(range(1, 9))
        assert occurrence_status(review_dir, psalter_rule["id"], "2026-10-06") is None
        kept_psalter = ask("finishPsalter")
        assert psalter_rule["id"] in kept_psalter["psalter"]["marked"]
        assert next(item for item in kept_psalter["entries"] if item["id"] == psalter_rule["id"])["kept"]

        leap = ask("selectDate", date="2028-02-29")
        missing_life = ask("openReading", band=4)["reading"]
        leap_life = next(item for item in missing_life["sections"] if item["band"] == 4)["life"]
        assert leap_life["available"] is False
        assert leap_life["unavailable"] == "No life is stored for this day."
        assert missing_life["marked"] == []

        glossary = ask("glossary")
        assert glossary["ok"] is True
        for key in ("entries", "week", "selectedDate", "displayName", "today",
                    "thanksgiving", "prayer", "reading", "progress"):
            assert key not in glossary, glossary
        listed = glossary["glossary"]
        assert "introductory" in listed["note"].lower()
        assert "not a ruling" in listed["note"].lower()
        assert "entry" not in listed
        categories = {cat["name"]: cat["terms"] for cat in listed["categories"]}
        assert "Prayer" in categories
        amen = next(term for term in categories["Prayer"] if term["slug"] == "amen")
        assert amen["term"] == "Amen" and "so be it" in amen["short"]

        detail = ask("glossary", slug="amen")
        assert "entries" not in detail
        entry = detail["glossary"]["entry"]
        assert entry["term"] == "Amen" and entry["pronunciation"] == "AH-meen"
        assert "Amen is not punctuation" in entry["full"]
        related = {item["slug"]: item["term"] for item in entry["related"]}
        assert related["prayer-rule"] == "Prayer rule"
        chained = ask("glossary", slug="prayer-rule")
        assert "entries" not in chained
        assert chained["glossary"]["entry"]["term"] == "Prayer rule"
        missing = ask("glossary", slug="not-a-term")
        assert missing["ok"] is False and "not in the glossary" in missing["error"]
        searched = ask("glossary", query="Amen")["glossary"]
        found = [term["slug"] for cat in searched["categories"] for term in cat["terms"]]
        assert "amen" in found and searched["query"] == "Amen"
        assert ask("glossary", query="zzzz-not-a-term")["glossary"]["categories"] == []

        begun = ask("choosePrayer", selection="beginning")["prayer"]
        assert begun["words"][0]["paragraphs"][0].startswith("In the name of the Father")
        assert begun["words"][0]["html"][0].count('href="amen"') == 1
        jesus = ask("choosePrayer", selection="jesus-prayer")["prayer"]
        assert jesus["words"][0]["paragraphs"] == [
            "Lord Jesus Christ, Son of God, have mercy on me, a sinner."
        ]
        assert "href=" not in jesus["words"][0]["html"][0]
        morning = ask("choosePrayer", selection="morning")["prayer"]
        amen_links = sum(
            line.count('href="amen"') for block in morning["words"] for line in block["html"]
        )
        assert amen_links == 1
        page = ask("reading")["reading"]
        assert page["summary"] and page["summaryHtml"]
        assert page["summary"].split()[0] in page["summaryHtml"]
        for section in page["sections"]:
            for passage in section.get("passages") or []:
                assert "href=" not in passage["text"]
        close(review)
        assert (Path(review_dir) / "chotki.sqlite").is_file()

    human_after = human_review.stat().st_mtime_ns if human_review.exists() else None
    assert human_before == human_after

    relative = os.environ.copy()
    relative["CHOTKI_LINUX_REVIEW_DIR"] = "not-absolute"
    rejected = subprocess.run(
        [helper, "--review"], input='{"v":1,"id":1,"op":"hello"}\n',
        text=True, capture_output=True, env=relative, timeout=5,
    )
    assert rejected.returncode != 0
    assert "absolute path" in rejected.stdout

    with tempfile.TemporaryDirectory(prefix="chotki-normal-check-") as directory:
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = directory
        normal, ask = conversation(helper, "--normal", environment)
        assert ask("hello")["mode"] == "normal"
        snapshot = ask("snapshot")
        assert snapshot["entries"] == []
        noted = ask("noteSayingPan", name="sayings/03.jpg")
        assert isinstance(noted["sayingPanStart"], float)
        repeated = ask("noteSayingPan", name="sayings/03.jpg")
        assert repeated["sayingPanStart"] == noted["sayingPanStart"]
        stored = Path(directory) / "Chotki" / "saying-pan"
        assert stored.is_file()
        assert stored.read_text().splitlines()[0].endswith("sayings/03.jpg")
        assert not ask("setReviewName", name="Must fail")["ok"]

        catalog = ask("library", query="")["library"]
        order = ["Services", "Prayer", "Reading", "Fasting", "Life"]
        names = [group["category"] for group in catalog["groups"]]
        assert names == [name for name in order if name in names]
        assert names.index("Services") < names.index("Prayer") < names.index("Fasting")
        morning_row = next(
            row for group in catalog["groups"] for row in group["templates"]
            if row["title"] == "Morning prayers"
        )
        assert morning_row["taken"] is False
        assert morning_row["terms"][0] == {"slug": "prayer-rule", "term": "Prayer rule"}

        found = ask("library", query="Morning")["library"]
        found_titles = [row["title"] for group in found["groups"] for row in group["templates"]]
        assert "Morning prayers" in found_titles
        assert "Evening prayers" not in found_titles
        assert all("morning" in title.lower() for title in found_titles)

        prepared = ask("prepareTemplate", template="morning-prayers")
        assert prepared["editor"]["open"] is True
        assert prepared["editor"]["isNew"] is True
        assert "entries" not in prepared
        assert ask("snapshot")["entries"] == []

        saved = ask("saveRule", hasTime=True, hour=7, minute=0)
        assert saved["editor"]["open"] is False
        morning = next(item for item in saved["entries"] if item["title"] == "Morning prayers")
        assert morning["time"] == "07:00"
        morning_id = morning["id"]

        ask("prepareTemplate", template="evening-prayers")
        both = ask("saveRule")
        assert {item["title"] for item in both["entries"]} == {"Morning prayers", "Evening prayers"}
        evening_id = next(item["id"] for item in both["entries"] if item["title"] == "Evening prayers")

        opened = ask("openEditor", ruleID=morning_id)
        assert opened["editor"]["open"] is True
        assert ask("dismissEditor")["editor"]["open"] is False
        ask("openEditor", ruleID=morning_id)
        edited = ask("saveRule", hasTime=True, hour=8, minute=0, scope="wholeSeries")
        morning = next(item for item in edited["entries"] if item["id"] == morning_id)
        assert morning["time"] == "08:00"
        assert next(item["id"] for item in edited["entries"] if item["title"] == "Evening prayers") == evening_id

        paused = ask("pauseRule", ruleID=morning_id)
        # The day a rule is paused still counts. The next day shows only what is left running.
        today = paused["today"]
        assert {item["title"] for item in paused["entries"]} == {"Morning prayers", "Evening prayers"}
        tomorrow = (date.fromisoformat(today) + timedelta(days=1)).isoformat()
        later = ask("selectDate", date=tomorrow)
        assert [item["title"] for item in later["entries"]] == ["Evening prayers"], later["entries"]
        ask("selectDate", date=today)
        resumed = ask("prepareTemplate", template="morning-prayers")
        assert resumed["editor"]["open"] is False
        assert next(item["id"] for item in resumed["entries"] if item["title"] == "Morning prayers") == morning_id
        ask("pauseRule", ruleID=morning_id)

        ask("setSpiritualFather", name="Father Seraphim")
        ask("openEditor", ruleID=evening_id)
        attributed = ask("saveRule", givenByPriest=True)
        evening_id = next(item["id"] for item in attributed["entries"] if item["title"] == "Evening prayers")
        recorded = ask("openEditor", ruleID=evening_id)["editor"]
        assert recorded["givenByPriest"] is True
        assert recorded["source"] == "Father Seraphim"
        ask("saveRule", givenByPriest=True, source="Father Seraphim")
        cleared = ask("setSpiritualFather", name="")
        assert cleared["library"]["fatherName"] == ""
        preserved = ask("openEditor", ruleID=evening_id)["editor"]
        assert preserved["fatherName"] == ""
        assert preserved["source"] == "Father Seraphim"
        assert preserved["givenByPriest"] is True

        scoped = ask("saveRule", scope="thisAndFuture", note="Quietly")
        successor = next(item["id"] for item in scoped["entries"] if item["title"] == "Evening prayers")
        assert successor != evening_id

        removed = ask("removeRule", ruleID=morning_id, scope="wholeSeries")
        assert all(item["title"] != "Morning prayers" for item in removed["entries"])
        listed = ask("library", query="Morning")["library"]
        morning_row = next(
            row for group in listed["groups"] for row in group["templates"]
            if row["id"] == "morning-prayers"
        )
        assert morning_row["taken"] is False

        caution = ask("openEditor")
        assert caution["editor"]["caution"] is True
        assert caution["editor"]["open"] is False
        assert "manufacture your own Orthodoxy" in caution["editor"]["cautionText"]
        ask("acknowledgeCaution", hideCaution=True)
        own = ask("saveRule", title="A walk", kind="Every day", hasTime=False)
        assert any(item["title"] == "A walk" for item in own["entries"])
        walk_id = next(item["id"] for item in own["entries"] if item["title"] == "A walk")
        aside = ask("setAside", ruleID=walk_id)
        assert all(item["id"] != walk_id for item in aside["library"]["custom"])
        assert any(item["title"] == "A walk" for item in aside["entries"])

        close(normal)
        assert (Path(directory) / "Chotki" / "chotki.sqlite").is_file()

    with tempfile.TemporaryDirectory(prefix="chotki-thanks-") as directory:
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = directory
        thanked, ask = conversation(helper, "--normal", environment)
        assert ask("hello")["mode"] == "normal"
        ask("prepareTemplate", template="morning-prayers")
        ask("saveRule")
        ask("prepareTemplate", template="evening-prayers")
        saved = ask("saveRule")
        morning_id = next(item["id"] for item in saved["entries"] if item["title"] == "Morning prayers")
        evening_id = next(item["id"] for item in saved["entries"] if item["title"] == "Evening prayers")
        one = ask("toggleKept", ruleID=morning_id)
        assert "thanksgiving" not in one
        selected = one["selectedDate"]
        assert not next(day["settled"] for day in one["week"] if day["date"] == selected)
        two = ask("toggleKept", ruleID=evening_id)
        assert two["thanksgiving"] == "Glory to God for all things."
        assert next(day["settled"] for day in two["week"] if day["date"] == selected)
        quiet = ask("snapshot")
        assert "thanksgiving" not in quiet
        assert next(day["settled"] for day in quiet["week"] if day["date"] == selected)
        down_morning = ask("standDownDay", ruleID=morning_id)
        assert "thanksgiving" not in down_morning
        assert next(day["settled"] for day in down_morning["week"] if day["date"] == selected)
        down_evening = ask("standDownDay", ruleID=evening_id)
        assert "thanksgiving" not in down_evening
        assert not next(day["settled"] for day in down_evening["week"] if day["date"] == selected)
        late_only = ask("markKeptLate", ruleID=morning_id)
        assert "thanksgiving" not in late_only
        assert next(day["settled"] for day in late_only["week"] if day["date"] == selected)
        close(thanked)

    with tempfile.TemporaryDirectory(prefix="chotki-progress-") as directory:
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = directory
        progress, ask = conversation(helper, "--normal", environment)
        assert ask("hello")["mode"] == "normal"
        today = date.fromisoformat(ask("snapshot")["today"])
        kept_day = (today - timedelta(days=3)).isoformat()
        stood_day = (today - timedelta(days=1)).isoformat()
        ask("prepareTemplate", template="morning-prayers")
        saved = ask("saveRule", **{"from": kept_day})
        rule_id = next(item["id"] for item in saved["entries"] if item["title"] == "Morning prayers")
        ask("selectDate", date=kept_day)
        kept = ask("toggleKept", ruleID=rule_id)
        assert next(item["kept"] for item in kept["entries"] if item["id"] == rule_id) is True
        ask("selectDate", date=stood_day)
        down = ask("standDownDay", ruleID=rule_id)
        assert next(item["stoodDown"] for item in down["entries"] if item["id"] == rule_id) is True
        report = ask("progress")
        assert report["ok"] is True
        for home_key in ("entries", "week", "selectedDate", "displayName", "today", "thanksgiving"):
            assert home_key not in report, report
        body = report["progress"]
        assert body["through"] == stood_day
        assert body["heading"] == f"Your progress up to {long_date(today - timedelta(days=1))}"
        assert "Morning prayers slipped once." in body["summary"]
        assert "One day was stood down and is not counted either way." in body["summary"]
        assert all("failed" not in line.lower() for line in body["summary"])
        assert body["rules"] == [{
            "id": rule_id, "title": "Morning prayers", "count": "1 of 2",
        }]
        assert "streak" not in body["rules"][0]
        assert body["figure"] == 50
        assert body["figureNote"] == "Kept, over the 30 days to then"
        close(progress)

    with tempfile.TemporaryDirectory(prefix="chotki-settings-a-") as first, \
            tempfile.TemporaryDirectory(prefix="chotki-settings-b-") as second:
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = first
        origin, ask = conversation(helper, "--normal", environment)
        opened = ask("snapshot")
        assert opened["needsWelcome"] is True
        assert opened["reducedMotion"] is False
        fresh = ask("settings")
        for home_key in ("entries", "week", "selectedDate", "displayName", "today"):
            assert home_key not in fresh, fresh
        page = fresh["settings"]
        assert page["church"] == "" and page["followed"] == "Orthodox Church in America"
        assert page["noChurch"] == "I don't have a church affiliation yet."
        assert "Romanian Orthodox Church" in page["churches"]
        assert page["welcomeTitle"] == "Welcome"
        assert page["beginLabel"] == "Continue"
        assert any("not a substitute for a priest" in "".join(span["text"] for span in paragraph["spans"])
                   for paragraph in page["welcomeParagraphs"])
        assert page["fasting"] == "shown" and page["feasts"] == "shown"
        assert page["version"] == "Linux alpha 0.1.0~alpha2"
        assert page["backupDirectory"].endswith("/Chotki/backups")
        saved = ask("saveSettings", name="Helen", church="Romanian Orthodox Church", welcome=True)
        assert saved["displayName"] == "Helen" and saved["needsWelcome"] is False
        assert "Orthodox Church in America" in saved["settings"]["akathistNote"]
        assert saved["settings"]["church"] == "Romanian Orthodox Church"
        ask("prepareTemplate", template="morning-prayers")
        made = ask("saveRule")
        assert any(item["title"] == "Morning prayers" for item in made["entries"])
        again = ask("snapshot")
        assert again["needsWelcome"] is False
        backup = str(Path(first) / "helen.json")
        exported = ask("exportBackup", path=backup)
        assert "entries" not in exported and "week" not in exported
        assert exported["settings"]["notice"] == "Backup written to helen.json."
        assert Path(backup).is_file()
        quiet = ask("saveSettings", motion=True)
        assert quiet["reducedMotion"] is True and quiet["settings"]["reducedMotion"] is True
        close(origin)

        reopened, ask = conversation(helper, "--normal", environment)
        remembered = ask("settings")["settings"]
        assert remembered["reducedMotion"] is True
        assert remembered["displayName"] == "Helen"
        assert remembered["church"] == "Romanian Orthodox Church"
        close(reopened)
        copies = list((Path(first) / "Chotki" / "backups").glob("chotki-*.json"))
        assert copies, "a day with rules keeps one backup beside the record"

        other = os.environ.copy()
        other["XDG_DATA_HOME"] = second
        restored, ask = conversation(helper, "--normal", other)
        assert ask("snapshot")["needsWelcome"] is True
        merged = ask("importBackup", path=backup)
        titles = [item["title"] for item in merged["entries"]]
        assert titles.count("Morning prayers") == 1
        assert merged["displayName"] == "Helen"
        assert merged["settings"]["church"] == "Romanian Orthodox Church"
        assert merged["needsWelcome"] is False
        ask("prepareTemplate", template="evening-prayers")
        ask("saveRule")
        kept = ask("importBackup", path=backup)
        titles = [item["title"] for item in kept["entries"]]
        assert "Morning prayers" in titles and "Evening prayers" in titles
        refused = ask("exportBackup", path="relative.json")
        assert refused["ok"] is False
        close(restored)

    with tempfile.TemporaryDirectory(prefix="chotki-reminders-") as directory:
        config = str(Path(directory) / "config")
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = directory
        environment["XDG_CONFIG_HOME"] = config
        session, ask = conversation(helper, "--normal", environment)
        assert ask("hello")["mode"] == "normal"
        moment = datetime.now()
        when = moment - timedelta(seconds=30)
        if when.date() != moment.date():
            when = moment
        ask("acknowledgeCaution", hideCaution=True)
        saved = ask(
            "saveRule", title="A timed reminder", kind="Every day", hasTime=True,
            hour=when.hour, minute=when.minute, reminders=True, leads=[0],
        )
        assert saved["ok"] is True, saved
        rule_id = next(item["id"] for item in saved["entries"] if item["title"] == "A timed reminder")
        fired = ask("tickReminders")
        assert fired["ok"] is True, fired
        for home_key in ("entries", "week", "selectedDate", "displayName", "today"):
            assert home_key not in fired, fired
        notices = fired["reminders"]["show"]
        assert len(notices) == 1, fired
        notice = notices[0]
        assert notice["title"] == "A timed reminder"
        assert notice["id"].startswith(rule_id + ":") and notice["id"].endswith(":lead0")
        assert notice["body"].startswith("At ")
        assert {action["id"]: action["title"] for action in notice["actions"]} == {
            "complete": "Mark complete",
            "snooze": "Snooze an hour",
        }
        date_in_id = notice["id"].split(":")[1]
        kept = ask("notificationAction", name=notice["id"], selection="complete")
        assert kept["ok"] is True, kept
        assert any(item["id"] == rule_id and item["kept"] for item in kept["entries"])
        assert notice["id"] in kept["reminders"]["withdraw"]
        record = str(Path(directory) / "Chotki")
        status = occurrence_status(record, rule_id, date_in_id)
        assert status is not None and status[0] == "completed" and status[1]
        stamped = status[1]
        quiet = ask("tickReminders")
        assert all(item["id"] != notice["id"] for item in quiet["reminders"]["show"])
        assert notice["id"] not in quiet["reminders"]["withdraw"]
        again = ask("notificationAction", name=notice["id"], selection="complete")
        assert again["ok"] is True, again
        assert occurrence_status(record, rule_id, date_in_id)[1] == stamped
        unknown = ask(
            "notificationAction",
            name=f"{uuid.uuid4()}:{date_in_id}:lead0",
            selection="complete",
        )
        assert unknown["ok"] is False
        assert unknown["error"] == "That rule is not on the selected day."

        ask("acknowledgeCaution", hideCaution=True)
        windowed = ask(
            "saveRule", title="A window reminder", kind="Every day", hasTime=True,
            hour=when.hour, minute=when.minute, reminders=True, leads=[0],
        )
        window_rule = next(item["id"] for item in windowed["entries"] if item["title"] == "A window reminder")
        banner = ask("tickReminders")
        window_notice = next(
            item for item in banner["reminders"]["show"] if item["id"].startswith(window_rule + ":")
        )
        ask("toggleKept", ruleID=window_rule)
        taken_back = ask("tickReminders")
        assert window_notice["id"] in taken_back["reminders"]["withdraw"]
        assert occurrence_status(record, window_rule, date_in_id)[0] == "completed"

        due = datetime.now() + timedelta(minutes=8)
        if due.date() == datetime.now().date():
            ask("acknowledgeCaution", hideCaution=True)
            later = ask(
                "saveRule", title="A later reminder", kind="Every day", hasTime=True,
                hour=due.hour, minute=due.minute, reminders=True, leads=[0, 10],
            )
            assert later["ok"] is True, later
            later_id = next(item["id"] for item in later["entries"] if item["title"] == "A later reminder")
            upcoming = ask("tickReminders")
            shown = [item for item in upcoming["reminders"]["show"] if item["id"].startswith(later_id + ":")]
            assert len(shown) == 1 and shown[0]["id"].endswith(":lead10"), upcoming
            snoozed = ask("notificationAction", name=shown[0]["id"], selection="snooze")
            assert snoozed["ok"] is True, snoozed
            assert "entries" not in snoozed, snoozed
            assert shown[0]["id"] in snoozed["reminders"]["withdraw"]
            held = ask("tickReminders")
            assert all(
                not item["id"].startswith(later_id + ":") for item in held["reminders"]["show"]
            ), held

        page = ask("settings")["settings"]
        assert page["launchAtLogin"] is False
        desktop = Path(config) / "autostart" / "org.chotki.Chotki.desktop"
        executable = "/usr/bin/chotki-linux"
        ask("syncAutostart", executable=executable)
        assert not desktop.exists()
        turned = ask("saveSettings", launchAtLogin=True, executable=executable)
        assert turned["settings"]["launchAtLogin"] is True
        text = desktop.read_text()
        assert "Type=Application" in text
        assert "Name=Chotki" in text
        assert f"Exec={executable}\n" in text
        assert "Icon=org.chotki.Chotki" in text
        assert "X-GNOME-Autostart-enabled=true" in text
        off = ask("saveSettings", launchAtLogin=False)
        assert off["settings"]["launchAtLogin"] is False
        assert not desktop.exists()
        close(session)

    with tempfile.TemporaryDirectory(prefix="chotki-autostart-relative-") as directory:
        environment = os.environ.copy()
        environment["XDG_DATA_HOME"] = directory
        environment["XDG_CONFIG_HOME"] = "relative-config"
        relative, ask = conversation(helper, "--normal", environment)
        ask("saveSettings", launchAtLogin=True, executable="/usr/bin/chotki-linux")
        assert not Path("relative-config/autostart/org.chotki.Chotki.desktop").exists()
        close(relative)

    with tempfile.TemporaryDirectory(prefix="chotki-review-reminders-") as review_dir, \
            tempfile.TemporaryDirectory(prefix="chotki-review-autostart-") as config_dir:
        environment = os.environ.copy()
        environment["CHOTKI_LINUX_REVIEW_DIR"] = review_dir
        environment["XDG_CONFIG_HOME"] = config_dir
        review, ask = conversation(helper, "--review", environment)
        tick = ask("tickReminders")
        assert tick["ok"] is True
        assert tick["reminders"] == {"show": [], "withdraw": []}
        for home_key in ("entries", "week", "selectedDate", "displayName", "today"):
            assert home_key not in tick, tick
        ask("saveSettings", launchAtLogin=True, executable="/usr/bin/chotki-linux")
        assert not (Path(config_dir) / "autostart" / "org.chotki.Chotki.desktop").exists()
        bright = ask("selectDate", date="2027-05-05")
        fast = next(item for item in bright["entries"] if item["title"] == "The Wednesday and Friday fast")
        assert fast["dispensed"]
        before = occurrence_count(review_dir)
        refused = ask(
            "notificationAction",
            name=f"{fast['id']}:2027-05-05:lead0",
            selection="complete",
        )
        assert refused["ok"] is False
        assert refused["error"] == "Nothing was asked on this day."
        assert occurrence_count(review_dir) == before
        close(review)

    human_after = human_review.stat().st_mtime_ns if human_review.exists() else None
    assert human_before == human_after

    print("Swift bridge review actions and normal-data isolation passed")


if __name__ == "__main__":
    main()
