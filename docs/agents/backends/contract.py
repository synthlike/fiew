"""Portable semantic record request, response, and error shapes."""

from __future__ import annotations

from dataclasses import dataclass, field
import hashlib
from typing import Any, Protocol


OPERATIONS = {"archive", "create", "list", "read", "update"}
ISSUE_OPERATIONS = {
    "block",
    "cancel",
    "claim",
    "comment",
    "create",
    "frontier",
    "list",
    "parent",
    "read",
    "resolve",
    "update",
}


class RecordError(RuntimeError):
    """A portable adapter failure with a stable machine-readable code."""

    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


@dataclass(frozen=True)
class RecordReference:
    backend: str
    id: str
    title: str
    href: str | None = None

    @classmethod
    def from_dict(cls, value: Any) -> "RecordReference":
        required = {"backend", "id", "title"}
        allowed = required | {"href"}
        if (
            not isinstance(value, dict)
            or not required.issubset(value)
            or set(value) - allowed
        ):
            raise RecordError("malformed_reference", "reference has missing or unknown fields")
        if any(
            not isinstance(value[key], str) or not value[key]
            for key in ("backend", "id", "title")
        ):
            raise RecordError("malformed_reference", "reference identity and title are required")
        href = value.get("href")
        if href is not None and not isinstance(href, str):
            raise RecordError("malformed_reference", "reference href must be a string or null")
        return cls(value["backend"], value["id"], value["title"], href)

    def as_dict(self) -> dict[str, str | None]:
        return {
            "backend": self.backend,
            "href": self.href,
            "id": self.id,
            "title": self.title,
        }


@dataclass(frozen=True)
class StoredRecord:
    record_type: str
    id: str
    title: str
    content: str
    revision: str
    reference: RecordReference
    metadata: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "content": self.content,
            "id": self.id,
            "metadata": self.metadata,
            "record_type": self.record_type,
            "reference": self.reference.as_dict(),
            "revision": self.revision,
            "title": self.title,
        }


@dataclass(frozen=True)
class RecordRequest:
    operation: str
    backend: str
    record_type: str
    destination: dict[str, Any]
    id: str | None = None
    title: str | None = None
    content: str | None = None
    expected_revision: str | None = None
    semantic_id: str | None = None
    query: str | None = None

    def validate(self) -> None:
        if self.operation not in OPERATIONS:
            raise RecordError("unsupported_operation", f"unsupported record operation: {self.operation}")
        if not self.backend:
            raise RecordError("invalid_request", "backend instance is required")
        if not self.record_type:
            raise RecordError("invalid_request", "record type is required")
        if not isinstance(self.destination, dict) or not self.destination:
            raise RecordError("invalid_request", "destination must be a non-empty mapping")
        if self.operation == "create":
            if not self.title or self.content is None:
                raise RecordError("invalid_request", "create requires title and content")
        elif self.operation in {"read", "archive"} and not self.id:
            raise RecordError("invalid_request", f"{self.operation} requires record id")
        elif self.operation == "update":
            if not self.id or not self.expected_revision:
                raise RecordError("invalid_request", "update requires record id and expected revision")
            if self.title is None and self.content is None:
                raise RecordError("invalid_request", "update requires title or content")
        if self.operation == "archive" and not self.expected_revision:
            raise RecordError("invalid_request", "archive requires expected revision")


@dataclass(frozen=True)
class RecordResponse:
    record: StoredRecord | None = None
    records: tuple[StoredRecord, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"ok": True}
        if self.record is not None:
            result["record"] = self.record.as_dict()
        if self.records:
            result["records"] = [record.as_dict() for record in self.records]
        elif self.record is None:
            result["records"] = []
        return result


@dataclass(frozen=True)
class IssueRecord:
    id: str
    title: str
    body: str
    kind: str
    status: str
    created: str
    assignee: str | None
    parent: str | None
    blocked_by: tuple[str, ...]
    labels: tuple[str, ...]
    revision: str
    reference: RecordReference

    def as_dict(self) -> dict[str, Any]:
        return {
            "assignee": self.assignee,
            "blocked_by": list(self.blocked_by),
            "body": self.body,
            "created": self.created,
            "id": self.id,
            "kind": self.kind,
            "labels": list(self.labels),
            "parent": self.parent,
            "reference": self.reference.as_dict(),
            "revision": self.revision,
            "status": self.status,
            "title": self.title,
        }


@dataclass(frozen=True)
class IssueRequest:
    operation: str
    backend: str
    destination: dict[str, Any]
    id: str | None = None
    title: str | None = None
    body: str | None = None
    kind: str | None = None
    labels: tuple[str, ...] | None = None
    expected_revision: str | None = None
    assignee: str | None = None
    parent_id: str | None = None
    blocker_id: str | None = None
    remove: bool = False
    state: str | None = None
    query: str | None = None

    def validate(self) -> None:
        if self.operation not in ISSUE_OPERATIONS:
            raise RecordError("unsupported_operation", f"unsupported issue operation: {self.operation}")
        if not self.backend:
            raise RecordError("invalid_request", "backend instance is required")
        if not isinstance(self.destination, dict) or not self.destination:
            raise RecordError("invalid_request", "destination must be a non-empty mapping")
        if self.operation == "create":
            if not self.title or self.body is None or not self.kind:
                raise RecordError("invalid_request", "issue create requires title, body, and kind")
        elif self.operation in {"read", "frontier"}:
            if not self.id:
                raise RecordError("invalid_request", f"{self.operation} requires issue id")
            return
        elif self.operation == "list":
            if self.state not in {None, "all", "open", "claimed", "resolved", "cancelled"}:
                raise RecordError("invalid_request", f"invalid issue state filter: {self.state}")
            if self.labels is not None and not all(
                isinstance(label, str) and label for label in self.labels
            ):
                raise RecordError("invalid_request", "issue labels must be non-empty strings")
            return
        elif not self.id or not self.expected_revision:
            raise RecordError(
                "invalid_request", f"{self.operation} requires issue id and expected revision"
            )
        if self.labels is not None and not all(
            isinstance(label, str) and label for label in self.labels
        ):
            raise RecordError("invalid_request", "issue labels must be non-empty strings")
        if self.operation == "comment" and not self.body:
            raise RecordError("invalid_request", "comment requires body")
        if self.operation in {"resolve", "cancel"} and not self.body:
            raise RecordError("invalid_request", f"{self.operation} requires outcome body")
        if self.operation == "claim" and not self.assignee:
            raise RecordError("invalid_request", "claim requires assignee")
        if self.operation == "parent" and not self.remove and not self.parent_id:
            raise RecordError("invalid_request", "parent add requires parent id")
        if self.operation == "block" and not self.blocker_id:
            raise RecordError("invalid_request", "block operation requires blocker id")
        if self.operation == "update" and all(
            value is None for value in (self.title, self.body, self.kind)
        ) and self.labels is None:
            raise RecordError("invalid_request", "issue update requires changed fields")


@dataclass(frozen=True)
class IssueResponse:
    issue: IssueRecord | None = None
    issues: tuple[IssueRecord, ...] = ()

    def as_dict(self) -> dict[str, Any]:
        result: dict[str, Any] = {"ok": True}
        if self.issue is not None:
            result["issue"] = self.issue.as_dict()
        if self.issues:
            result["issues"] = [issue.as_dict() for issue in self.issues]
        elif self.issue is None:
            result["issues"] = []
        return result


class RecordAdapter(Protocol):
    def execute(self, request: RecordRequest) -> RecordResponse:
        """Execute one validated portable operation or raise RecordError."""

    def render_reference(self, reference: RecordReference) -> str:
        """Render one opaque reference for content owned by this adapter."""


class IssueAdapter(Protocol):
    def execute_issue(self, request: IssueRequest) -> IssueResponse:
        """Execute one validated issue operation or raise RecordError."""


def revision_token(data: bytes) -> str:
    """Return an opaque revision for exact persisted bytes."""

    return "sha256:" + hashlib.sha256(data).hexdigest()
