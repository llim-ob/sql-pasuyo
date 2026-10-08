"""Turn a Teamwork task into a GitHub SQL-request issue."""

from __future__ import annotations

import argparse
import html
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from html.parser import HTMLParser
from pathlib import Path

from tw_auth import QWEN_API_KEY, qwen_chat, teamwork_get

BASE_DIR = Path(__file__).parent
TEMPLATE_DIR = BASE_DIR / "template"
GITHUB_API = "https://api.github.com"
GITHUB_OWNER = os.getenv("GITHUB_OWNER", "objectbrightph")
GITHUB_REPO = os.getenv("GITHUB_REPO", "sql-requests")


class TaskTextParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data: str) -> None:
        self.parts.append(data)


def parse_teamwork_link(link: str) -> dict[str, str]:
    path_parts = urllib.parse.urlsplit(link).path.split("/")
    task_id = next(
        (
            path_parts[index + 1]
            for index, part in enumerate(path_parts[:-1])
            if part == "tasks" and path_parts[index + 1].isdigit()
        ),
        "",
    )
    if not task_id:
        raise ValueError("Could not extract a task ID from the Teamwork URL")
    return {"task_id": task_id, "link": link}


def text_value(value) -> str:
    if value is None:
        return ""
    if not isinstance(value, str):
        value = json.dumps(value)
    parser = TaskTextParser()
    parser.feed(value)
    parser.close()
    return " ".join(html.unescape(" ".join(parser.parts)).split())


def first_value(data: dict, *keys):
    for key in keys:
        value = data.get(key)
        if value not in (None, "", []):
            return value
    return None


def text_tokens(text: str) -> list[str]:
    tokens = []
    word = []
    for char in text:
        if char.isalnum() or char == "_":
            word.append(char)
        else:
            if word:
                tokens.append("".join(word))
                word = []
            if not char.isspace():
                tokens.append(char)
    if word:
        tokens.append("".join(word))
    return tokens


def numeric_after(tokens: list[str], index: int, *, allow_id: bool = False, allow_for: bool = False) -> str:
    index += 1
    if allow_id and index < len(tokens) and tokens[index].lower() == "id":
        index += 1
    if allow_for and index < len(tokens) and tokens[index].lower() == "for":
        index += 1
    while index < len(tokens) and tokens[index] in {":", "#", "-", "("}:
        index += 1
    return tokens[index] if index < len(tokens) and tokens[index].isdigit() else ""


def filename_after(text: str, label: str) -> str:
    parts = text.split()
    for index, part in enumerate(parts):
        prefix, separator, value = part.partition(":")
        if separator and prefix.lower() == label:
            if not value and index + 1 < len(parts):
                value = parts[index + 1]
            value = value.lstrip("\"'")
            filename = []
            for char in value:
                if not (char.isalnum() or char in "_.-"):
                    break
                filename.append(char)
            return "".join(filename)
    return ""


def extract_task(task_id: str, payload: dict) -> dict:
    data = payload.get("task", payload)
    if not isinstance(data, dict):
        raise RuntimeError("Teamwork task response did not contain a task")

    title = text_value(first_value(data, "name", "title"))
    description = text_value(first_value(data, "description", "content", "body"))
    source_text = f"{title}\n{description}"

    feed_id = first_value(data, "feedId", "feedID")
    adapter_id = first_value(data, "adapterId", "adapterID")

    raw_file_ids = first_value(data, "fileIds", "fileIDs") or []
    if isinstance(raw_file_ids, (str, int)):
        raw_file_ids = [raw_file_ids]
    file_ids = [str(value) for value in raw_file_ids if value]
    tokens = text_tokens(source_text)
    for index, token in enumerate(tokens):
        label = token.lower()
        if label in {"feed", "feedid"}:
            feed_id = numeric_after(tokens, index, allow_id=label == "feed") or feed_id
        elif label in {"adapter", "adapterid"}:
            adapter_id = numeric_after(tokens, index, allow_id=label == "adapter") or adapter_id
        elif label in {"file", "fileid"}:
            file_id = numeric_after(tokens, index, allow_id=label == "file")
            if file_id:
                file_ids.append(file_id)
        elif label == "blob":
            file_id = numeric_after(tokens, index, allow_for=True)
            if file_id:
                file_ids.append(file_id)
        elif label == "for":
            file_id = numeric_after(tokens, index)
            if file_id:
                file_ids.append(file_id)
        if token.isdigit() and len(tokens) >= index + 7:
            separator, month, slash1, day, slash2, year = tokens[index + 1:index + 7]
            if (
                (separator, slash1, slash2) == ("-", "/", "/")
                and month.isdigit() and day.isdigit() and year.isdigit()
                and 1 <= len(month) <= 2 and 1 <= len(day) <= 2 and len(year) == 4
            ):
                file_ids.append(token)

    # Fallback: scan the entire source text for any standalone 7-digit numbers
    # that haven't already been captured, treating them as file IDs.
    for match in re.finditer(r'(?<!\d)(\d{7})(?!\d)', source_text):
        candidate = match.group(1)
        if candidate not in file_ids:
            file_ids.append(candidate)

    return {
        "task_id": task_id,
        "title": title,
        "description": description,
        "feed_id": str(feed_id) if feed_id else "",
        "adapter_id": str(adapter_id) if adapter_id else "",
        "file_ids": list(dict.fromkeys(file_ids)),
        "rename_from": filename_after(source_text, "from"),
        "rename_to": filename_after(source_text, "to"),
    }


def fetch_task(task_id: str) -> dict:
    """Fetch task data directly through the Teamwork API, without browser login."""
    return extract_task(
        task_id,
        teamwork_get(f"/projects/api/v3/tasks/{task_id}.json"),
    )


def analyze_task_hardcoded(task: dict) -> dict:
    """Classify supported operations without an external model."""
    title_words = [token.lower() for token in text_tokens(task["title"])]
    description_words = [token.lower() for token in text_tokens(task["description"])]
    has_rename_pair = bool(task["rename_from"] and task["rename_to"])

    def has_phrase(words: list[str], phrase: tuple[str, ...]) -> bool:
        phrase_words = list(phrase)
        return any(words[index:index + len(phrase)] == phrase_words for index in range(len(words)))

    def has_any(words: list[str], choices: set[str]) -> bool:
        return any(word in choices for word in words)

    def has_reload(words: list[str]) -> bool:
        return has_any(words, {"reload", "reprocess", "retry", "rerun"}) or has_phrase(words, ("re", "-", "run"))

    if has_any(title_words, {"delete", "deletion", "remove"}):
        operation = "delete"
    elif has_any(title_words, {"rename", "renamed"}) or has_phrase(title_words, ("change", "filename")):
        operation = "rename"
    elif has_phrase(title_words, ("replace", "blob")) and has_rename_pair:
        operation = "rename"
    elif has_reload(title_words):
        operation = "reload"
    elif has_any(description_words, {"rename", "renamed"}) or has_phrase(description_words, ("change", "filename")):
        operation = "rename"
    elif has_phrase(description_words, ("replace", "blob")) and has_rename_pair:
        operation = "rename"
    elif any(
        description_words[index] in {"delete", "deletion", "remove"}
        and description_words[index + 1] in {"the", "this", "file", "blob", "record"}
        for index in range(len(description_words) - 1)
    ):
        operation = "delete"
    elif has_reload(description_words):
        operation = "reload"
    else:
        operation = "reload"

    return {
        "operation": operation,
        "rename_to": task["rename_to"] if operation == "rename" else "",
        "request_details": "For Reload" if operation == "reload" else "",
        "rationale": "Matched local COMREC operation rules.",
        "analyzer": "hardcoded",
    }


def analyze_task(task: dict, operation: str | None = None) -> dict:
    """Select an explicit operation or analyze the Teamwork task."""
    if operation:
        return {
            "operation": "reload" if operation == "replace-blob" else operation,
            "rename_to": task["rename_to"] if operation == "rename" else "",
            "request_details": (
                "For Reload / BLOB Update"
                if operation == "replace-blob"
                else "For Reload" if operation == "reload" else ""
            ),
            "rationale": (
                "Explicit operation flag selected "
                f"{operation.replace('-', ' ')}."
            ),
            "analyzer": "explicit flag",
        }

    # Fall back to configured model analysis, then local deterministic rules.
    if not QWEN_API_KEY:
        return analyze_task_hardcoded(task)

    prompt = {
        "title": task["title"],
        "description": task["description"],
        "rename_from": task["rename_from"],
        "rename_to": task["rename_to"],
        "feed_id": task["feed_id"],
        "adapter_id": task["adapter_id"],
        "file_ids": task["file_ids"],
    }
    content = qwen_chat(
        [
            {
                "role": "system",
                "content": (
                    "Classify a COMREC Teamwork task. Return JSON only with keys "
                    "operation, rename_to, rationale. operation must be exactly "
                    "reload, rename, or delete. Use rename only for a filename change. "
                    "Use delete only when the task asks to remove/delete data. "
                    "Use reload for replacing/reprocessing a blob without deletion or "
                    "filename change. rename_to must be an empty string unless operation "
                    "is rename. Do not invent IDs or filenames."
                ),
            },
            {"role": "user", "content": json.dumps(prompt, ensure_ascii=True)},
        ]
    )
    try:
        result = json.loads(content)
    except json.JSONDecodeError as exc:
        start = content.find("```")
        end = content.find("```", start + 3) if start != -1 else -1
        fenced = content[start + 3:end].strip() if end != -1 else ""
        if fenced.startswith("json"):
            fenced = fenced[4:].strip()
        if not (fenced.startswith("{") and fenced.endswith("}")):
            raise RuntimeError("Qwen returned invalid task-analysis JSON") from exc
        result = json.loads(fenced)

    operation = result.get("operation")
    if operation not in {"reload", "rename", "delete"}:
        raise RuntimeError("Qwen returned an unsupported operation")
    rename_to = str(result.get("rename_to") or "").strip()
    if operation == "rename" and not rename_to:
        raise RuntimeError("Qwen classified task as rename but returned no destination filename")
    if operation != "rename":
        rename_to = ""
    return {
        "operation": operation,
        "rename_to": rename_to,
        "request_details": "For Reload" if operation == "reload" else "",
        "rationale": str(result.get("rationale") or ""),
        "analyzer": "qwen",
    }


def validate_task(task: dict, analysis: dict) -> dict:
    task = dict(task)
    task.update(analysis)
    missing = [
        name
        for name, value in (
            ("feed ID", task["feed_id"]),
            ("adapter ID", task["adapter_id"]),
            ("file ID", task["file_ids"]),
            ("title", task["title"]),
        )
        if not value
    ]
    if missing:
        raise ValueError(f"Task is missing required {', '.join(missing)}")
    if task["operation"] == "rename" and not task["rename_to"]:
        raise ValueError("Rename task is missing the destination filename (To: ...)")
    return task


def choose_delete_mode() -> str:
    while True:
        choice = input("Delete mode: choose 1 (delete1.txt) or 2 (delete2.txt): ").strip()
        if choice in {"1", "2"}:
            return choice
        print("Invalid choice. Enter 1 for delete1.txt or 2 for delete2.txt.")


def render_reference_template(task: dict) -> str:
    template_name = (
        f"delete{choose_delete_mode()}.txt" if task["operation"] == "delete" else f"{task['operation']}.txt"
    )
    template = (TEMPLATE_DIR / template_name).read_text(encoding="utf-8")
    replacements = {
        "{feed_id}": task["feed_id"],
        "{adapter_id}": task["adapter_id"],
        "{fileids}": ",".join(task["file_ids"]),
        "{filename}": task["rename_to"],
        "{request_details}": task.get("request_details", "For Reload"),
    }
    for placeholder, value in replacements.items():
        template = template.replace(placeholder, value)
    return template


def render_issue_body(task: dict, request_text: str) -> str:
    template = (BASE_DIR / "sql_request.txt").read_text(encoding="utf-8")
    return template.replace("{teamwork_link}", task["link"]).replace(
        "{the sql generated from python script}", request_text
    )


def github_request(method: str, path: str, token: str, payload: dict) -> dict:
    request = urllib.request.Request(
        f"{GITHUB_API}{path}",
        data=json.dumps(payload).encode(),
        method=method,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read().decode())
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode(errors="replace")[:500]
        raise RuntimeError(f"GitHub API failed ({exc.code}): {detail}") from exc


def create_github_issue(task: dict, request_text: str) -> str:
    token = os.getenv("GITHUB_TOKEN", "")
    if not token:
        raise RuntimeError("GITHUB_TOKEN is required")
    issue = github_request(
        "POST",
        f"/repos/{GITHUB_OWNER}/{GITHUB_REPO}/issues",
        token,
        {
            "title": task["title"],
            "body": render_issue_body(task, request_text),
            "labels": [os.getenv("GITHUB_LABEL", "sql-request")],
        },
    )
    return issue["html_url"]


def main() -> int:
    parser = argparse.ArgumentParser(description="Create a GitHub issue from a Teamwork COMREC task")
    parser.add_argument("teamwork_link", help="Teamwork task URL")
    operation_group = parser.add_mutually_exclusive_group()
    operation_group.add_argument(
        "--operation",
        choices=("reload", "delete", "rename", "replace-blob"),
        help="Use this operation instead of analyzing the Teamwork task",
    )
    operation_group.add_argument(
        "--reload",
        dest="operation",
        action="store_const",
        const="reload",
        help="Force reload operation",
    )
    operation_group.add_argument(
        "--delete",
        dest="operation",
        action="store_const",
        const="delete",
        help="Force delete operation",
    )
    operation_group.add_argument(
        "--rename",
        dest="operation",
        action="store_const",
        const="rename",
        help="Force rename operation",
    )
    operation_group.add_argument(
        "--replace-blob",
        dest="operation",
        action="store_const",
        const="replace-blob",
        help="Force replace-blob operation using the reload template",
    )
    args = parser.parse_args()

    try:
        task = {**parse_teamwork_link(args.teamwork_link)}
        task.update(fetch_task(task["task_id"]))
        analysis = analyze_task(task, args.operation)
        task = validate_task(task, analysis)
        request_text = render_reference_template(task)
        print(f"Operation: {task['operation']}")
        print(f"Analyzer: {task['analyzer']}")
        print(f"Analysis rationale: {task['rationale']}")
        print(f"Feed ID: {task['feed_id']}")
        print(f"Adapter ID: {task['adapter_id']}")
        print(f"File IDs: {', '.join(task['file_ids'])}")
        print(f"Issue created: {create_github_issue(task, request_text)}")
        return 0
    except (ValueError, RuntimeError, OSError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
