#!/usr/bin/env python3
"""Deterministic GitHub Cloud record and issue operations through the gh CLI."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Any, Callable

RECORD_CONTRACT = Path(__file__).resolve().parents[1] / "record-store"
if str(RECORD_CONTRACT) not in sys.path:
    sys.path.insert(0, str(RECORD_CONTRACT))
from contract import (  # noqa: E402
    IssueRecord,
    IssueRequest,
    IssueResponse,
    RecordError,
    RecordReference,
    RecordRequest,
    RecordResponse,
    StoredRecord,
    revision_token,
)
from urllib.parse import quote


ISSUE_KINDS = {
    "initiative": {
        "color": "5319E7",
        "description": "Parent map for a bounded initiative",
    },
    "bug": {
        "color": "D73A4A",
        "description": "Accepted defect with observable incorrect behavior",
    },
    "implementation": {
        "color": "0075CA",
        "description": "Executable vertical delivery slice",
    },
    "clarification": {
        "color": "FBCA04",
        "description": "Question requiring a human decision",
    },
    "research": {
        "color": "0E8A16",
        "description": "Focused external fact-finding question",
    },
    "prototype": {
        "color": "D4C5F9",
        "description": "Question answered through a disposable concrete artifact",
    },
    "prerequisite": {
        "color": "BFDADC",
        "description": "Enabling action that does not implement the destination",
    },
}
RECORD_TYPES = {
    "issues",
    "domain",
    "arps",
    "rfcs",
    "specs",
    "meetings",
    "research",
    "questionnaires",
    "technical_baselines",
    "problem_framing",
    "prototypes",
    "handoffs",
}
RECORD_COLORS = {
    "issues": "5319E7",
    "domain": "1D76DB",
    "arps": "0052CC",
    "rfcs": "006B75",
    "specs": "0E8A16",
    "meetings": "C5DEF5",
    "research": "BFD4F2",
    "questionnaires": "D4C5F9",
    "technical_baselines": "0366D6",
    "problem_framing": "FBCA04",
    "prototypes": "F9D0C4",
    "handoffs": "BFDADC",
}
LABELS = {
    **{
        f"workflow:record:{record_type}": {
            "color": RECORD_COLORS[record_type],
            "description": f"Agent Workflows {record_type} record",
        }
        for record_type in RECORD_TYPES
    },
    **{
        f"workflow:issue:{kind}": settings
        for kind, settings in ISSUE_KINDS.items()
    },
}
MANAGED_LABELS = set(LABELS)
ISSUE_MANAGED_LABELS = {f"workflow:issue:{kind}" for kind in ISSUE_KINDS}
RECORD_MANAGED_LABELS = {f"workflow:record:{kind}" for kind in RECORD_TYPES}
WRITE_PERMISSIONS = {"ADMIN", "MAINTAIN", "WRITE"}
Runner = Callable[[list[str], str | None], str]


class BackendError(RuntimeError):
    """A safe, user-facing backend failure."""


@dataclass(frozen=True)
class Repository:
    name: str
    url: str
    permission: str
    issues_enabled: bool


class GhClient:
    def __init__(
        self,
        repository: str | None = None,
        login: str | None = None,
        runner: Runner | None = None,
    ):
        self.requested_repository = repository
        self.requested_login = login
        self._runner = runner or self._run
        self._repository: Repository | None = None
        self._current_login: str | None = None
        self._accounts: list[dict[str, Any]] | None = None

    @staticmethod
    def _run(arguments: list[str], input_text: str | None = None) -> str:
        try:
            completed = subprocess.run(
                ["gh", *arguments],
                input=input_text,
                text=True,
                capture_output=True,
                check=False,
            )
        except FileNotFoundError as error:
            raise BackendError("gh is not installed or is not on PATH") from error
        if completed.returncode:
            detail = completed.stderr.strip() or completed.stdout.strip()
            raise BackendError(detail or f"gh exited with status {completed.returncode}")
        return completed.stdout

    def repository(self) -> Repository:
        if self._repository is not None:
            return self._repository
        arguments = ["repo", "view"]
        if self.requested_repository:
            arguments.append(self.requested_repository)
        arguments.extend(
            ("--json", "nameWithOwner,url,viewerPermission,hasIssuesEnabled")
        )
        try:
            data = json.loads(self._runner(arguments, None))
        except json.JSONDecodeError as error:
            raise BackendError("gh repo view returned invalid JSON") from error
        self._repository = Repository(
            name=data.get("nameWithOwner", ""),
            url=data.get("url", ""),
            permission=data.get("viewerPermission", ""),
            issues_enabled=data.get("hasIssuesEnabled") is True,
        )
        return self._repository

    def auth_accounts(self) -> list[dict[str, Any]]:
        if self._accounts is None:
            try:
                data = json.loads(
                    self._runner(
                        [
                            "auth",
                            "status",
                            "--hostname",
                            "github.com",
                            "--json",
                            "hosts",
                        ],
                        None,
                    )
                )
            except json.JSONDecodeError as error:
                raise BackendError("gh auth status returned invalid JSON") from error
            accounts = data.get("hosts", {}).get("github.com", [])
            self._accounts = [
                {
                    "active": account.get("active") is True,
                    "login": account.get("login", ""),
                    "state": account.get("state", ""),
                }
                for account in accounts
                if account.get("login")
            ]
        return self._accounts

    def require_login(self) -> str:
        if not self.requested_login:
            raise BackendError("--login is required to select an authenticated GitHub account")
        accounts = self.auth_accounts()
        selected = next(
            (account for account in accounts if account["login"] == self.requested_login),
            None,
        )
        if selected is None:
            raise BackendError(
                f"GitHub account {self.requested_login} is not authenticated on github.com"
            )
        if selected["state"] != "success":
            raise BackendError(
                f"GitHub authentication for {self.requested_login} is not valid"
            )
        if not selected["active"]:
            raise BackendError(
                f"GitHub account {self.requested_login} is not active; run "
                f"gh auth switch --hostname github.com --user {self.requested_login} and retry"
            )
        return self.requested_login

    def preflight(self) -> dict[str, Any]:
        login = self.current_user()
        repository = self.repository()
        errors = []
        if not repository.name or not repository.url.startswith("https://github.com/"):
            errors.append("the GitHub backend requires a github.com repository")
        if not repository.issues_enabled:
            errors.append("GitHub Issues is disabled for the repository")
        if repository.permission not in WRITE_PERMISSIONS:
            errors.append(
                "repository write permission is required for issues, relationships, and labels"
            )
        if errors:
            raise BackendError("; ".join(errors))
        return {
            "capabilities": {
                "issue_contract": "complete",
                "issue_dependencies": "native",
                "record_contract": "complete",
                "record_types": sorted(RECORD_TYPES),
                "sub_issues": "native",
            },
            "authenticated_accounts": [account["login"] for account in self.auth_accounts()],
            "issues_enabled": True,
            "login": login,
            "permission": repository.permission,
            "repository": repository.name,
        }

    def api(
        self,
        endpoint: str,
        *,
        method: str = "GET",
        payload: dict[str, Any] | None = None,
        paginate: bool = False,
    ) -> Any:
        arguments = ["api", "--method", method, endpoint]
        if paginate:
            arguments.extend(("--paginate", "--slurp"))
        input_text = None
        if payload is not None:
            arguments.extend(("--input", "-"))
            input_text = json.dumps(payload, separators=(",", ":"))
        output = self._runner(arguments, input_text)
        if not output.strip():
            return None
        try:
            data = json.loads(output)
        except json.JSONDecodeError as error:
            raise BackendError(f"gh api returned invalid JSON for {endpoint}") from error
        if paginate:
            if not isinstance(data, list):
                raise BackendError(f"paginated response is not a list for {endpoint}")
            flattened = []
            for page in data:
                if not isinstance(page, list):
                    raise BackendError(f"paginated response contains a non-list page for {endpoint}")
                flattened.extend(page)
            return flattened
        return data

    def current_user(self) -> str:
        if self._current_login is not None:
            return self._current_login
        login = self.require_login()
        data = self.api("/user")
        actual = data.get("login") if isinstance(data, dict) else None
        if actual != login:
            raise BackendError(
                f"gh api authenticated as {actual or 'unknown'}, expected {login}"
            )
        self._current_login = login
        return login


class GitHubBackend:
    def __init__(self, client: GhClient):
        self.client = client

    @property
    def repository(self) -> str:
        return self.client.repository().name

    def _endpoint(self, suffix: str = "") -> str:
        return f"/repos/{self.repository}{suffix}"

    @staticmethod
    def _label_name(kind: str) -> str:
        if kind not in ISSUE_KINDS:
            raise BackendError(f"unknown workflow kind: {kind}")
        return f"workflow:issue:{kind}"

    @staticmethod
    def _record_label(record_type: str) -> str:
        if record_type not in RECORD_TYPES:
            raise BackendError(f"unknown workflow record type: {record_type}")
        return f"workflow:record:{record_type}"

    @staticmethod
    def _label_names(issue: dict[str, Any]) -> list[str]:
        result = []
        for label in issue.get("labels", []):
            result.append(label if isinstance(label, str) else label.get("name", ""))
        return [name for name in result if name]

    def _issue(self, number: int) -> dict[str, Any]:
        issue = self.client.api(self._endpoint(f"/issues/{number}"))
        if not isinstance(issue, dict) or "pull_request" in issue:
            raise BackendError(f"#{number} is not a repository issue")
        return issue

    def _many(self, suffix: str) -> list[dict[str, Any]]:
        separator = "&" if "?" in suffix else "?"
        result = self.client.api(
            self._endpoint(f"{suffix}{separator}per_page=100"), paginate=True
        )
        if not isinstance(result, list):
            raise BackendError(f"expected a list from {suffix}")
        return result

    def preflight(self) -> dict[str, Any]:
        return self.client.preflight()

    def label_plan(self) -> dict[str, Any]:
        current = {
            label["name"]: {
                "color": label.get("color", "").upper(),
                "description": label.get("description") or "",
            }
            for label in self._many("/labels")
        }
        changes = []
        for name, settings in sorted(LABELS.items()):
            desired = {
                "color": settings["color"].upper(),
                "description": settings["description"],
            }
            existing = current.get(name)
            action = "create" if existing is None else "unchanged" if existing == desired else "update"
            changes.append(
                {
                    "action": action,
                    "desired": desired,
                    "expected": existing,
                    "name": name,
                }
            )
        return {"changes": changes, "repository": self.repository, "schema": 2}

    def apply_label_plan(self, plan: dict[str, Any]) -> dict[str, Any]:
        if plan.get("schema") != 2 or plan.get("repository") != self.repository:
            raise BackendError("label plan does not match this repository")
        current_plan = self.label_plan()
        if current_plan != plan:
            raise BackendError("label state changed after the reviewed plan; generate a new plan")
        applied = []
        for change in plan["changes"]:
            if change["action"] == "unchanged":
                continue
            payload = {"name": change["name"], **change["desired"]}
            if change["action"] == "create":
                self.client.api(self._endpoint("/labels"), method="POST", payload=payload)
            elif change["action"] == "update":
                encoded = quote(change["name"], safe="")
                self.client.api(
                    self._endpoint(f"/labels/{encoded}"), method="PATCH", payload=payload
                )
            else:
                raise BackendError(f"unknown label-plan action: {change['action']}")
            applied.append(change["name"])
        return {"applied": applied, "repository": self.repository}

    def _require_repository_label(self, name: str) -> str:
        encoded = quote(name, safe="")
        try:
            existing = self.client.api(self._endpoint(f"/labels/{encoded}"))
        except BackendError as error:
            raise BackendError(f"required label {name} is unavailable") from error
        if not isinstance(existing, dict) or existing.get("name") != name:
            raise BackendError(f"required label {name} is unavailable")
        return name

    def _require_label(self, kind: str) -> str:
        name = self._label_name(kind)
        try:
            return self._require_repository_label(name)
        except BackendError as error:
            raise BackendError(
                f"required label {name} is unavailable; review and apply a label plan first"
            ) from error

    def _extra_labels(self, labels: list[str]) -> list[str]:
        result = []
        for name in labels:
            if name.startswith("workflow:"):
                raise BackendError("set semantic kind with --kind, not an extra workflow label")
            result.append(self._require_repository_label(name))
        return result

    def create(
        self, title: str, body: str, kind: str, labels: list[str] | None = None
    ) -> dict[str, Any]:
        issue_labels = [
            self._require_repository_label(self._record_label("issues")),
            self._require_label(kind),
            *self._extra_labels(labels or []),
        ]
        return self.client.api(
            self._endpoint("/issues"),
            method="POST",
            payload={"body": body, "labels": issue_labels, "title": title},
        )

    def read(self, number: int) -> dict[str, Any]:
        return {
            "blocked_by": self._many(f"/issues/{number}/dependencies/blocked_by"),
            "comments": self._many(f"/issues/{number}/comments"),
            "issue": self._issue(number),
            "sub_issues": self._many(f"/issues/{number}/sub_issues"),
        }

    def list(
        self,
        *,
        state: str = "open",
        kind: str | None = None,
        labels: list[str] | None = None,
        assignee: str | None = None,
        parent: int | None = None,
    ) -> list[dict[str, Any]]:
        if state not in {"open", "closed", "all"}:
            raise BackendError(f"invalid issue state: {state}")
        issues = (
            self._many(f"/issues/{parent}/sub_issues")
            if parent is not None
            else self._many(f"/issues?state={state}")
        )
        issues = [
            issue
            for issue in issues
            if "pull_request" not in issue
            and "workflow:record:issues" in self._label_names(issue)
        ]
        if parent is not None and state != "all":
            issues = [issue for issue in issues if issue.get("state") == state]
        if kind:
            label = self._label_name(kind)
            issues = [issue for issue in issues if label in self._label_names(issue)]
        for label in labels or []:
            issues = [issue for issue in issues if label in self._label_names(issue)]
        if assignee:
            login = self.client.current_user() if assignee == "@me" else assignee
            issues = [
                issue
                for issue in issues
                if any(item.get("login") == login for item in issue.get("assignees", []))
            ]
        return sorted(issues, key=lambda issue: issue["number"])

    def update(
        self,
        number: int,
        *,
        title: str | None = None,
        body: str | None = None,
        kind: str | None = None,
        add_labels: list[str] | None = None,
        remove_labels: list[str] | None = None,
        state: str | None = None,
    ) -> dict[str, Any]:
        payload: dict[str, Any] = {}
        if title is not None:
            payload["title"] = title
        if body is not None:
            payload["body"] = body
        add_labels = add_labels or []
        remove_labels = remove_labels or []
        if kind is not None or add_labels or remove_labels:
            issue = self._issue(number)
            labels = self._label_names(issue)
            if kind is not None:
                labels = [name for name in labels if name not in ISSUE_MANAGED_LABELS]
                labels.append(self._require_label(kind))
            for name in self._extra_labels(add_labels):
                if name not in labels:
                    labels.append(name)
            for name in remove_labels:
                if name.startswith("workflow:"):
                    raise BackendError("change semantic kind with --kind; do not remove it")
                labels = [existing for existing in labels if existing != name]
            payload["labels"] = sorted(labels)
        if state is not None:
            if state != "open":
                raise BackendError("use resolve or cancel to close an issue")
            payload.update({"state": "open", "state_reason": "reopened"})
        if not payload:
            raise BackendError("update requires a title, body, kind, label change, or state")
        return self.client.api(
            self._endpoint(f"/issues/{number}"), method="PATCH", payload=payload
        )

    def comment(self, number: int, body: str) -> dict[str, Any]:
        return self.client.api(
            self._endpoint(f"/issues/{number}/comments"),
            method="POST",
            payload={"body": body},
        )

    def claim(self, number: int, assignee: str = "@me") -> dict[str, Any]:
        login = self.client.current_user() if assignee == "@me" else assignee
        issue = self._issue(number)
        if issue.get("state") != "open":
            raise BackendError(f"issue #{number} is not open and cannot be claimed")
        current = sorted(item["login"] for item in issue.get("assignees", []))
        if current == [login]:
            return {"assignee": login, "changed": False, "number": number}
        if current:
            raise BackendError(f"issue #{number} is already claimed by {', '.join(current)}")
        self.client.api(
            self._endpoint(f"/issues/{number}/assignees"),
            method="POST",
            payload={"assignees": [login]},
        )
        return {"assignee": login, "changed": True, "number": number}

    def _close(self, number: int, body: str, reason: str) -> dict[str, Any]:
        if self._issue(number).get("state") != "open":
            raise BackendError(f"issue #{number} is already closed")
        self.comment(number, body)
        issue = self.client.api(
            self._endpoint(f"/issues/{number}"),
            method="PATCH",
            payload={"state": "closed", "state_reason": reason},
        )
        return {"issue": issue, "resolution_comment_added": True}

    def resolve(self, number: int, body: str) -> dict[str, Any]:
        return self._close(number, body, "completed")

    def cancel(self, number: int, body: str) -> dict[str, Any]:
        return self._close(number, body, "not_planned")

    def add_parent(self, parent: int, child: int) -> dict[str, Any]:
        if parent == child:
            raise BackendError("an issue cannot be its own parent")
        child_issue = self._issue(child)
        children = self._many(f"/issues/{parent}/sub_issues")
        if any(item.get("id") == child_issue.get("id") for item in children):
            return {"changed": False, "child": child, "parent": parent}
        self.client.api(
            self._endpoint(f"/issues/{parent}/sub_issues"),
            method="POST",
            payload={"sub_issue_id": child_issue["id"]},
        )
        return {"changed": True, "child": child, "parent": parent}

    def remove_parent(self, parent: int, child: int) -> dict[str, Any]:
        child_issue = self._issue(child)
        children = self._many(f"/issues/{parent}/sub_issues")
        if not any(item.get("id") == child_issue.get("id") for item in children):
            return {"changed": False, "child": child, "parent": parent}
        self.client.api(
            self._endpoint(f"/issues/{parent}/sub_issue"),
            method="DELETE",
            payload={"sub_issue_id": child_issue["id"]},
        )
        return {"changed": True, "child": child, "parent": parent}

    def add_blocker(self, issue_number: int, blocker_number: int) -> dict[str, Any]:
        if issue_number == blocker_number:
            raise BackendError("an issue cannot block itself")
        blocker = self._issue(blocker_number)
        existing = self._many(f"/issues/{issue_number}/dependencies/blocked_by")
        if any(item.get("id") == blocker.get("id") for item in existing):
            return {"blocked": issue_number, "blocker": blocker_number, "changed": False}
        self.client.api(
            self._endpoint(f"/issues/{issue_number}/dependencies/blocked_by"),
            method="POST",
            payload={"issue_id": blocker["id"]},
        )
        return {"blocked": issue_number, "blocker": blocker_number, "changed": True}

    def remove_blocker(self, issue_number: int, blocker_number: int) -> dict[str, Any]:
        blocker = self._issue(blocker_number)
        existing = self._many(f"/issues/{issue_number}/dependencies/blocked_by")
        if not any(item.get("id") == blocker.get("id") for item in existing):
            return {"blocked": issue_number, "blocker": blocker_number, "changed": False}
        self.client.api(
            self._endpoint(
                f"/issues/{issue_number}/dependencies/blocked_by/{blocker['id']}"
            ),
            method="DELETE",
        )
        return {"blocked": issue_number, "blocker": blocker_number, "changed": True}

    def frontier(self, parent: int) -> list[dict[str, Any]]:
        candidates = [
            issue
            for issue in self._many(f"/issues/{parent}/sub_issues")
            if issue.get("state") == "open" and not issue.get("assignees")
        ]
        frontier = []
        for issue in candidates:
            blockers = self._many(
                f"/issues/{issue['number']}/dependencies/blocked_by"
            )
            if all(
                blocker.get("state") == "closed"
                and blocker.get("state_reason") == "completed"
                for blocker in blockers
            ):
                frontier.append(issue)
        return sorted(frontier, key=lambda issue: issue["number"])


RECORD_METADATA = re.compile(r"^<!-- agent-workflows-record:(\{[^\n]*\}) -->\n")
ISSUE_ID = re.compile(r"ISSUE-([0-9]+)")


class GitHubRecordAdapter:
    """Portable record and issue contracts backed by managed GitHub issues."""

    def __init__(self, client: GhClient, backend: str = "github"):
        self.client = client
        self.github = GitHubBackend(client)
        self.backend = backend

    @staticmethod
    def _slug(title: str) -> str:
        value = re.sub(r"[^a-z0-9]+", "-", title.lower()).strip("-")
        if not value:
            raise RecordError("invalid_id", "title cannot produce a semantic identifier")
        return value

    @staticmethod
    def _revision(value: Any) -> str:
        return revision_token(
            json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        )

    @staticmethod
    def _labels(issue: dict[str, Any]) -> list[str]:
        return GitHubBackend._label_names(issue)

    @staticmethod
    def _metadata_body(metadata: dict[str, Any], content: str) -> str:
        encoded = json.dumps(metadata, sort_keys=True, separators=(",", ":"))
        return f"<!-- agent-workflows-record:{encoded} -->\n{content}"

    @staticmethod
    def _parse_body(issue: dict[str, Any]) -> tuple[dict[str, Any], str]:
        body = issue.get("body") or ""
        match = RECORD_METADATA.match(body)
        if not match:
            raise RecordError("malformed_record", "managed GitHub record metadata is missing")
        try:
            metadata = json.loads(match.group(1))
        except json.JSONDecodeError as error:
            raise RecordError("malformed_record", "managed GitHub record metadata is invalid") from error
        if set(metadata) != {"archived", "id", "record_type"}:
            raise RecordError("malformed_record", "managed GitHub record metadata has invalid fields")
        if (
            not isinstance(metadata["archived"], bool)
            or not isinstance(metadata["id"], str)
            or not metadata["id"]
            or not isinstance(metadata["record_type"], str)
            or metadata["record_type"] not in RECORD_TYPES - {"issues"}
        ):
            raise RecordError("malformed_record", "managed GitHub record metadata is invalid")
        return metadata, body[match.end():]

    def _destination(self, destination: dict[str, Any], record_type: str) -> str:
        if set(destination) != {"label"} or not isinstance(destination.get("label"), str):
            raise RecordError("invalid_destination", "GitHub destination requires only label")
        expected = f"workflow:record:{record_type}"
        if destination["label"] != expected:
            raise RecordError("invalid_destination", f"GitHub destination label must be {expected}")
        return expected

    def _all(self) -> list[dict[str, Any]]:
        return self.github._many("/issues?state=all")

    def _managed_records(self, record_type: str) -> list[StoredRecord]:
        label = f"workflow:record:{record_type}"
        records = []
        for issue in self._all():
            if "pull_request" in issue or label not in self._labels(issue):
                continue
            records.append(self._stored(issue, record_type))
        return sorted(records, key=lambda record: (record.id, record.reference.id))

    def _record_revision(self, issue: dict[str, Any]) -> str:
        return self._revision(
            {
                "body": issue.get("body") or "",
                "labels": sorted(self._labels(issue)),
                "state": issue.get("state"),
                "state_reason": issue.get("state_reason"),
                "title": issue.get("title") or "",
                "updated_at": issue.get("updated_at"),
            }
        )

    def _stored(self, issue: dict[str, Any], record_type: str) -> StoredRecord:
        if "pull_request" in issue:
            raise RecordError("not_found", "pull requests are not managed records")
        labels = self._labels(issue)
        expected = f"workflow:record:{record_type}"
        managed = sorted(set(labels) & RECORD_MANAGED_LABELS)
        if managed != [expected]:
            raise RecordError("malformed_record", "record must have exactly one matching route label")
        metadata, content = self._parse_body(issue)
        if metadata["record_type"] != record_type:
            raise RecordError("malformed_record", "record metadata and route label disagree")
        number = int(issue["number"])
        href = issue.get("html_url") or f"https://github.com/{self.github.repository}/issues/{number}"
        return StoredRecord(
            record_type=record_type,
            id=metadata["id"],
            title=issue.get("title") or "",
            content=content,
            revision=self._record_revision(issue),
            reference=RecordReference(self.backend, str(number), issue.get("title") or "", href),
            metadata={
                "archived": metadata["archived"],
                "github_state": issue.get("state"),
                "github_state_reason": issue.get("state_reason"),
            },
        )

    def _record_by_id(self, record_type: str, record_id: str) -> StoredRecord:
        matches = [record for record in self._managed_records(record_type) if record.id == record_id]
        if not matches:
            raise RecordError("not_found", f"record does not exist: {record_id}")
        if len(matches) > 1:
            raise RecordError("duplicate_id", f"record id has several owners: {record_id}")
        return matches[0]

    def _native_issue(self, record: StoredRecord) -> dict[str, Any]:
        return self.github._issue(int(record.reference.id))

    def render_reference(self, reference: RecordReference) -> str:
        title = reference.title.replace("\\", "\\\\").replace("[", "\\[").replace("]", "\\]")
        if reference.href is None:
            return title
        href = reference.href.replace("<", "%3C").replace(">", "%3E")
        return f"[{title}](<{href}>)"

    def execute(self, request: RecordRequest) -> RecordResponse:
        request.validate()
        if request.backend != self.backend:
            raise RecordError("backend_mismatch", f"adapter serves {self.backend}")
        if request.record_type not in RECORD_TYPES - {"issues"}:
            raise RecordError("unsupported_record_type", request.record_type)
        label = self._destination(request.destination, request.record_type)
        try:
            if request.operation == "create":
                records = self._managed_records(request.record_type)
                existing = {record.id for record in records}
                if request.semantic_id:
                    record_id = request.semantic_id
                    if record_id in existing:
                        raise RecordError("duplicate_id", f"record id already exists: {record_id}")
                else:
                    base = self._slug(request.title or "")
                    record_id = base
                    suffix = 2
                    while record_id in existing:
                        record_id = f"{base}-{suffix}"
                        suffix += 1
                self.github._require_repository_label(label)
                if record_id in {record.id for record in self._managed_records(request.record_type)}:
                    raise RecordError("duplicate_id", f"record id already exists: {record_id}")
                metadata = {
                    "archived": False,
                    "id": record_id,
                    "record_type": request.record_type,
                }
                created = self.client.api(
                    self.github._endpoint("/issues"),
                    method="POST",
                    payload={
                        "body": self._metadata_body(metadata, request.content or ""),
                        "labels": [label],
                        "title": request.title,
                    },
                )
                number = int(created["number"])
                self.client.api(
                    self.github._endpoint(f"/issues/{number}"),
                    method="PATCH",
                    payload={"state": "closed", "state_reason": "completed"},
                )
                return RecordResponse(record=self._stored(self.github._issue(number), request.record_type))
            if request.operation == "list":
                records = [
                    record
                    for record in self._managed_records(request.record_type)
                    if not record.metadata["archived"]
                ]
                if request.id:
                    records = [record for record in records if record.id == request.id]
                if request.query:
                    query = request.query.casefold()
                    records = [
                        record
                        for record in records
                        if query in record.id.casefold()
                        or query in record.title.casefold()
                        or query in record.content.casefold()
                    ]
                return RecordResponse(records=tuple(records))
            current = self._record_by_id(request.record_type, request.id or "")
            if request.operation == "read":
                return RecordResponse(record=current)
            if current.revision != request.expected_revision:
                raise RecordError("stale_revision", f"record changed since read: {current.id}")
            native = self._native_issue(current)
            if self._record_revision(native) != request.expected_revision:
                raise RecordError("stale_revision", f"record changed since read: {current.id}")
            metadata, content = self._parse_body(native)
            if request.operation == "archive":
                metadata["archived"] = True
            payload = {
                "body": self._metadata_body(metadata, request.content if request.content is not None else content),
            }
            if request.title is not None:
                payload["title"] = request.title
            changed = self.client.api(
                self.github._endpoint(f"/issues/{native['number']}"),
                method="PATCH",
                payload=payload,
            )
            if not isinstance(changed, dict):
                raise RecordError("io_error", "GitHub update returned no record")
            return RecordResponse(record=self._stored(self.github._issue(int(native["number"])), request.record_type))
        except RecordError:
            raise
        except BackendError as error:
            message = str(error)
            code = (
                "not_found"
                if "404" in message or "not found" in message.lower()
                else "invalid_destination"
                if "required label" in message
                else "io_error"
            )
            raise RecordError(code, message) from error

    @staticmethod
    def _number(issue_id: str) -> int:
        match = ISSUE_ID.fullmatch(issue_id)
        if not match:
            raise RecordError("invalid_id", f"invalid GitHub issue id: {issue_id}")
        return int(match.group(1))

    def _parent(self, number: int) -> dict[str, Any] | None:
        try:
            value = self.client.api(self.github._endpoint(f"/issues/{number}/parent"))
        except BackendError as error:
            if "404" in str(error) or "not found" in str(error).lower():
                return None
            raise
        return value if isinstance(value, dict) else None

    def _issue_snapshot(self, number: int) -> tuple[dict[str, Any], list[dict[str, Any]], list[dict[str, Any]], dict[str, Any] | None]:
        issue = self.github._issue(number)
        comments = self.github._many(f"/issues/{number}/comments")
        blockers = self.github._many(f"/issues/{number}/dependencies/blocked_by")
        parent = self._parent(number)
        return issue, comments, blockers, parent

    def _issue_record(self, number: int) -> IssueRecord:
        issue, comments, blockers, parent = self._issue_snapshot(number)
        labels = self._labels(issue)
        if sorted(set(labels) & RECORD_MANAGED_LABELS) != ["workflow:record:issues"]:
            raise RecordError("malformed_record", "issue must have the issues record label")
        kind_labels = sorted(set(labels) & ISSUE_MANAGED_LABELS)
        if len(kind_labels) != 1:
            raise RecordError("malformed_record", "issue must have exactly one issue-kind label")
        kind = kind_labels[0].removeprefix("workflow:issue:")
        body = issue.get("body") or ""
        if comments:
            body += "\n\n## Comments\n\n" + "\n\n".join(
                comment.get("body") or "" for comment in comments
            )
        state = issue.get("state")
        reason = issue.get("state_reason")
        assignees = sorted(item.get("login", "") for item in issue.get("assignees", []) if item.get("login"))
        status = (
            "resolved"
            if state == "closed" and reason == "completed"
            else "cancelled"
            if state == "closed"
            else "claimed"
            if assignees
            else "open"
        )
        snapshot = {
            "assignees": assignees,
            "blocked_by": [item.get("number") for item in blockers],
            "body": issue.get("body") or "",
            "comments": comments,
            "labels": sorted(labels),
            "parent": parent.get("number") if parent else None,
            "state": state,
            "state_reason": reason,
            "title": issue.get("title") or "",
            "updated_at": issue.get("updated_at"),
        }
        href = issue.get("html_url") or f"https://github.com/{self.github.repository}/issues/{number}"
        return IssueRecord(
            id=f"ISSUE-{number:04d}",
            title=issue.get("title") or "",
            body=body,
            kind=kind,
            status=status,
            created=(issue.get("created_at") or "").split("T", 1)[0],
            assignee=assignees[0] if len(assignees) == 1 else None,
            parent=f"ISSUE-{int(parent['number']):04d}" if parent else None,
            blocked_by=tuple(f"ISSUE-{int(item['number']):04d}" for item in blockers),
            labels=tuple(sorted(set(labels) - MANAGED_LABELS)),
            revision=self._revision(snapshot),
            reference=RecordReference(self.backend, str(number), issue.get("title") or "", href),
        )

    def _check_issue_revision(self, request: IssueRequest, issue: IssueRecord) -> None:
        if issue.revision != request.expected_revision:
            raise RecordError("stale_revision", f"issue changed since read: {issue.id}")

    def execute_issue(self, request: IssueRequest) -> IssueResponse:
        request.validate()
        if request.backend != self.backend:
            raise RecordError("backend_mismatch", f"adapter serves {self.backend}")
        self._destination(request.destination, "issues")
        try:
            if request.operation == "create":
                created = self.github.create(
                    request.title or "", request.body or "", request.kind or "", list(request.labels or ())
                )
                return IssueResponse(issue=self._issue_record(int(created["number"])))
            if request.operation == "list":
                raw = self.github.list(state="all")
                records = [
                    self._issue_record(int(item["number"]))
                    for item in raw
                    if "workflow:record:issues" in self._labels(item)
                ]
                if request.state not in {None, "all"}:
                    records = [record for record in records if record.status == request.state]
                if request.kind:
                    records = [record for record in records if record.kind == request.kind]
                if request.labels:
                    records = [record for record in records if set(request.labels).issubset(record.labels)]
                if request.assignee:
                    records = [record for record in records if record.assignee == request.assignee]
                if request.parent_id:
                    records = [record for record in records if record.parent == request.parent_id]
                if request.query:
                    query = request.query.casefold()
                    records = [record for record in records if query in record.title.casefold() or query in record.body.casefold()]
                return IssueResponse(issues=tuple(sorted(records, key=lambda item: self._number(item.id))))
            if request.operation == "frontier":
                parent_number = self._number(request.id or "")
                self._issue_record(parent_number)
                values = self.github.frontier(parent_number)
                return IssueResponse(
                    issues=tuple(self._issue_record(int(item["number"])) for item in values)
                )
            number = self._number(request.id or "")
            current = self._issue_record(number)
            if request.operation == "read":
                return IssueResponse(issue=current)
            self._check_issue_revision(request, current)
            self._check_issue_revision(request, self._issue_record(number))
            if request.operation == "update":
                desired = set(request.labels if request.labels is not None else current.labels)
                existing = set(current.labels)
                self.github.update(
                    number,
                    title=request.title,
                    body=request.body,
                    kind=request.kind,
                    add_labels=sorted(desired - existing),
                    remove_labels=sorted(existing - desired),
                )
            elif request.operation == "comment":
                author = request.assignee or self.client.current_user()
                self.github.comment(number, f"**{author}:**\n\n{request.body}")
            elif request.operation == "claim":
                self.github.claim(number, request.assignee or "@me")
            elif request.operation == "resolve":
                self.github.resolve(number, request.body or "")
            elif request.operation == "cancel":
                self.github.cancel(number, request.body or "")
            elif request.operation == "parent":
                if request.remove:
                    if current.parent:
                        self.github.remove_parent(self._number(current.parent), number)
                else:
                    parent_number = self._number(request.parent_id or "")
                    self._issue_record(parent_number)
                    self.github.add_parent(parent_number, number)
            elif request.operation == "block":
                blocker = self._number(request.blocker_id or "")
                self._issue_record(blocker)
                if request.remove:
                    self.github.remove_blocker(number, blocker)
                else:
                    self.github.add_blocker(number, blocker)
            return IssueResponse(issue=self._issue_record(number))
        except RecordError:
            raise
        except BackendError as error:
            message = str(error)
            code = (
                "claim_conflict"
                if "claimed" in message
                else "invalid_relationship"
                if "itself" in message or "cycle" in message.lower()
                else "not_found"
                if "404" in message or "not found" in message.lower()
                else "invalid_destination"
                if "required label" in message
                else "io_error"
            )
            raise RecordError(code, message) from error


def _read_body(path: str) -> str:
    if path == "-":
        return sys.stdin.read()
    return Path(path).read_text()


def _write_json(value: Any, output: str | None = None) -> None:
    text = json.dumps(value, indent=2, sort_keys=True) + "\n"
    if output:
        Path(output).write_text(text)
    else:
        sys.stdout.write(text)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="OWNER/REPO; defaults to the current repository")
    parser.add_argument(
        "--login", required=True, help="configured github.com account login"
    )
    parser.add_argument("--backend", default="github", help="configured backend instance name")
    parser.add_argument("--destination-label", help="complete workflow:record:* route label")
    commands = parser.add_subparsers(dest="command", required=True)
    commands.add_parser("preflight")

    plan = commands.add_parser("labels-plan")
    plan.add_argument("--output")
    apply = commands.add_parser("labels-apply")
    apply.add_argument("--plan-file", required=True)
    apply.add_argument("--yes", action="store_true")

    create = commands.add_parser("create")
    create.add_argument("--title", required=True)
    create.add_argument("--body-file", required=True)
    create.add_argument("--kind", choices=sorted(ISSUE_KINDS), required=True)
    create.add_argument("--label", action="append", default=[])

    read = commands.add_parser("read")
    read.add_argument("number", type=int)
    listing = commands.add_parser("list")
    listing.add_argument("--state", choices=("open", "closed", "all"), default="open")
    listing.add_argument("--kind", choices=sorted(ISSUE_KINDS))
    listing.add_argument("--label", action="append", default=[])
    listing.add_argument("--assignee")
    listing.add_argument("--parent", type=int)

    update = commands.add_parser("update")
    update.add_argument("number", type=int)
    update.add_argument("--title")
    update.add_argument("--body-file")
    update.add_argument("--kind", choices=sorted(ISSUE_KINDS))
    update.add_argument("--add-label", action="append", default=[])
    update.add_argument("--remove-label", action="append", default=[])
    update.add_argument("--state", choices=("open",))

    for name in ("comment", "resolve", "cancel"):
        command = commands.add_parser(name)
        command.add_argument("number", type=int)
        command.add_argument("--body-file", required=True)

    claim = commands.add_parser("claim")
    claim.add_argument("number", type=int)
    claim.add_argument("--assignee", default="@me")

    for name in ("parent-add", "parent-remove"):
        command = commands.add_parser(name)
        command.add_argument("parent", type=int)
        command.add_argument("child", type=int)
    for name in ("block-add", "block-remove"):
        command = commands.add_parser(name)
        command.add_argument("issue", type=int)
        command.add_argument("blocker", type=int)
    frontier = commands.add_parser("frontier")
    frontier.add_argument("parent", type=int)

    record_create = commands.add_parser("record-create")
    record_create.add_argument("--record-type", choices=sorted(RECORD_TYPES - {"issues"}), required=True)
    record_create.add_argument("--title", required=True)
    record_create.add_argument("--content-file", required=True)
    record_create.add_argument("--semantic-id")
    for name in ("record-read", "record-update", "record-archive"):
        command = commands.add_parser(name)
        command.add_argument("id")
        command.add_argument("--record-type", choices=sorted(RECORD_TYPES - {"issues"}), required=True)
        if name != "record-read":
            command.add_argument("--expected-revision", required=True)
        if name == "record-update":
            command.add_argument("--title")
            command.add_argument("--content-file")
    record_list = commands.add_parser("record-list")
    record_list.add_argument("--record-type", choices=sorted(RECORD_TYPES - {"issues"}), required=True)
    record_list.add_argument("--query")
    render = commands.add_parser("render-reference")
    render.add_argument("--reference-file", required=True)

    issue_create = commands.add_parser("issue-create")
    issue_create.add_argument("--title", required=True)
    issue_create.add_argument("--body-file", required=True)
    issue_create.add_argument("--kind", choices=sorted(ISSUE_KINDS), required=True)
    issue_create.add_argument("--label", action="append")
    issue_read = commands.add_parser("issue-read")
    issue_read.add_argument("id")
    issue_list = commands.add_parser("issue-list")
    issue_list.add_argument("--state", choices=("open", "claimed", "resolved", "cancelled", "all"))
    issue_list.add_argument("--kind", choices=sorted(ISSUE_KINDS))
    issue_list.add_argument("--label", action="append")
    issue_list.add_argument("--assignee")
    issue_list.add_argument("--parent-id")
    issue_list.add_argument("--query")
    issue_update = commands.add_parser("issue-update")
    issue_update.add_argument("id")
    issue_update.add_argument("--expected-revision", required=True)
    issue_update.add_argument("--title")
    issue_update.add_argument("--body-file")
    issue_update.add_argument("--kind", choices=sorted(ISSUE_KINDS))
    issue_update.add_argument("--label", action="append")
    for name in ("issue-comment", "issue-resolve", "issue-cancel"):
        command = commands.add_parser(name)
        command.add_argument("id")
        command.add_argument("--expected-revision", required=True)
        command.add_argument("--body-file", required=True)
        if name == "issue-comment":
            command.add_argument("--author")
    issue_claim = commands.add_parser("issue-claim")
    issue_claim.add_argument("id")
    issue_claim.add_argument("--expected-revision", required=True)
    issue_claim.add_argument("--assignee", required=True)
    issue_parent = commands.add_parser("issue-parent")
    issue_parent.add_argument("id")
    issue_parent.add_argument("--expected-revision", required=True)
    issue_parent.add_argument("--parent-id")
    issue_parent.add_argument("--remove", action="store_true")
    issue_block = commands.add_parser("issue-block")
    issue_block.add_argument("id")
    issue_block.add_argument("--expected-revision", required=True)
    issue_block.add_argument("--blocker-id", required=True)
    issue_block.add_argument("--remove", action="store_true")
    issue_frontier = commands.add_parser("issue-frontier")
    issue_frontier.add_argument("id")
    return parser


def main(arguments: list[str] | None = None) -> int:
    args = build_parser().parse_args(arguments)
    client = GhClient(args.repo, args.login)
    backend = GitHubBackend(client)
    portable = GitHubRecordAdapter(client, args.backend)
    try:
        if args.command == "render-reference":
            reference = RecordReference.from_dict(json.loads(Path(args.reference_file).read_text()))
            result = {"rendered": portable.render_reference(reference)}
        else:
            client.current_user()
        if args.command == "render-reference":
            pass
        elif args.command.startswith("record-"):
            if not args.destination_label:
                raise RecordError("invalid_destination", "--destination-label is required")
            operation = args.command.removeprefix("record-")
            request = RecordRequest(
                operation=operation,
                backend=args.backend,
                record_type=args.record_type,
                destination={"label": args.destination_label},
                id=getattr(args, "id", None),
                title=getattr(args, "title", None),
                content=(
                    _read_body(args.content_file)
                    if getattr(args, "content_file", None) is not None
                    else None
                ),
                expected_revision=getattr(args, "expected_revision", None),
                semantic_id=getattr(args, "semantic_id", None),
                query=getattr(args, "query", None),
            )
            result = portable.execute(request).as_dict()
        elif args.command.startswith("issue-"):
            if not args.destination_label:
                raise RecordError("invalid_destination", "--destination-label is required")
            operation = args.command.removeprefix("issue-")
            labels = getattr(args, "label", None)
            request = IssueRequest(
                operation=operation,
                backend=args.backend,
                destination={"label": args.destination_label},
                id=getattr(args, "id", None),
                title=getattr(args, "title", None),
                body=(
                    _read_body(args.body_file)
                    if getattr(args, "body_file", None) is not None
                    else None
                ),
                kind=getattr(args, "kind", None),
                labels=tuple(labels) if labels is not None else None,
                expected_revision=getattr(args, "expected_revision", None),
                assignee=getattr(args, "assignee", None) or getattr(args, "author", None),
                parent_id=getattr(args, "parent_id", None),
                blocker_id=getattr(args, "blocker_id", None),
                remove=getattr(args, "remove", False),
                state=getattr(args, "state", None),
                query=getattr(args, "query", None),
            )
            result = portable.execute_issue(request).as_dict()
        elif args.command == "preflight":
            result = backend.preflight()
        elif args.command == "labels-plan":
            result = backend.label_plan()
            _write_json(result, args.output)
            return 0
        elif args.command == "labels-apply":
            if not args.yes:
                raise BackendError("labels-apply requires --yes after reviewing the plan")
            result = backend.apply_label_plan(json.loads(Path(args.plan_file).read_text()))
        elif args.command == "create":
            result = backend.create(
                args.title, _read_body(args.body_file), args.kind, args.label
            )
        elif args.command == "read":
            result = backend.read(args.number)
        elif args.command == "list":
            result = backend.list(
                state=args.state,
                kind=args.kind,
                labels=args.label,
                assignee=args.assignee,
                parent=args.parent,
            )
        elif args.command == "update":
            result = backend.update(
                args.number,
                title=args.title,
                body=_read_body(args.body_file) if args.body_file else None,
                kind=args.kind,
                add_labels=args.add_label,
                remove_labels=args.remove_label,
                state=args.state,
            )
        elif args.command == "comment":
            result = backend.comment(args.number, _read_body(args.body_file))
        elif args.command == "claim":
            result = backend.claim(args.number, args.assignee)
        elif args.command == "resolve":
            result = backend.resolve(args.number, _read_body(args.body_file))
        elif args.command == "cancel":
            result = backend.cancel(args.number, _read_body(args.body_file))
        elif args.command == "parent-add":
            result = backend.add_parent(args.parent, args.child)
        elif args.command == "parent-remove":
            result = backend.remove_parent(args.parent, args.child)
        elif args.command == "block-add":
            result = backend.add_blocker(args.issue, args.blocker)
        elif args.command == "block-remove":
            result = backend.remove_blocker(args.issue, args.blocker)
        elif args.command == "frontier":
            result = backend.frontier(args.parent)
        else:  # pragma: no cover
            raise BackendError(f"unknown command: {args.command}")
    except RecordError as error:
        print(json.dumps({"error": error.as_dict(), "ok": False}, sort_keys=True), file=sys.stderr)
        return 1
    except (BackendError, OSError, json.JSONDecodeError) as error:
        print(f"github record backend: {error}", file=sys.stderr)
        return 1
    _write_json(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
