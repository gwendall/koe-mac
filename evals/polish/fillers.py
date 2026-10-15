# Fillers taken out before the model, by rule: no latency, no surprise.
# Always: sounds that are a word in no language Koe hears. Only before a
# comma: sounds that are also words ("um" is German for "at", "eh" ends a
# Canadian question, "ben" is a name).
import re
ALWAYS = ["uh", "uhm", "uhh", "euh", "heu", "ähm", "äh", "ehm", "erm", "hmm", "mmh"]
COMMA = ["um", "umm", "eh", "hum", "ben", "er"]
_always = re.compile(r"(?i)(?<![\w'’])(?:" + "|".join(ALWAYS) + r")(?![\w'’])[,.…]?\s*")
_comma = re.compile(r"(?i)(?<![\w'’])(?:" + "|".join(COMMA) + r"),\s*")

_between = re.compile(r"(?i),\s*(?:" + "|".join(ALWAYS + COMMA) + r"),\s*")

def strip(text):
    out = _between.sub(" ", text)                       # "before, uh, Friday" -> "before Friday"
    out = _comma.sub("", _always.sub("", out))
    out = re.sub(r"\s+([,.?!…])", r"\1", out)          # no space before the punctuation left behind
    out = re.sub(r",\s*([,.?!])", r"\1", out)           # ", ," or ", ?" left behind
    out = re.sub(r"^[,\s]+", "", out).strip()
    out = re.sub(r"([.?!…]\s+|^)([¿¡]?)([a-zà-ÿ])", lambda m: m.group(1) + m.group(2) + m.group(3).upper(), out)
    return out if out else text

if __name__ == "__main__":
    for t in ["Um, can you send me the the report before, uh, Friday?", "Wir treffen uns um zehn.", "Euh, je serai là, euh, vers 19h.",
              "So uh I think we should, uh, ship on Monday.", "Ehm, ci vediamo domani.", "Eh, ¿puedes revisar el informe?", "Okay, eh?",
              "Bon ben du coup on se voit demain.", "Hum, você pode?", "Er kommt morgen."]:
        print(repr(t), "->", repr(strip(t)))
