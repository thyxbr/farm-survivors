"""Escrita dos data/balance/*.json no estilo do projeto: tabs, listas de números numa linha só."""
import json
import re

_NUM = r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"
_ARR = re.compile(r"\[\s*((?:" + _NUM + r",\s*)*" + _NUM + r")\s*\]")


def dumps(data) -> str:
    text = json.dumps(data, ensure_ascii=False, indent="\t")
    # lista sem objeto nem lista dentro: uma linha só ("[0.55, 0.38, 0.2, 1.0]")
    text = _ARR.sub(lambda m: "[" + re.sub(r",\s*", ", ", m.group(1).strip()) + "]", text)
    return text + "\n"


def write(path, data) -> None:
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(dumps(data))
