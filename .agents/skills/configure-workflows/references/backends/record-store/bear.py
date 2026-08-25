#!/usr/bin/env python3
"""Read-only preflight for a scoped Bear MCP record backend."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import select
import subprocess
import sys
from typing import Any
from urllib.parse import quote

from contract import RecordError, RecordReference, RecordRequest, RecordResponse, StoredRecord


PROTOCOL_VERSION = "2025-06-18"
NON_ISSUE_RECORD_TYPES = {
    "arps",
    "domain",
    "handoffs",
    "meetings",
    "problem_framing",
    "prototypes",
    "questionnaires",
    "research",
    "rfcs",
    "specs",
    "technical_baselines",
}
RECORD_OPERATIONS = {"archive", "create", "list", "read", "update"}
REQUIRED_TOOLS = {
    "create_note": {
        "input": {"content", "tags", "title"},
        "output": {"content", "id", "tags", "title"},
        "read_only": False,
    },
    "get_note": {
        "input": {"id", "includeContent"},
        "output": {"metadata"},
        "read_only": True,
    },
    "read_note_content": {
        "input": {"id"},
        "output": {"content", "hash"},
        "read_only": True,
    },
    "list_notes": {
        "input": {"includeContent", "limit", "location", "offset", "tag"},
        "output": {"total"},
        "read_only": True,
    },
    "search_notes": {
        "input": {"includeContent", "limit", "location", "offset", "query"},
        "output": {"total"},
        "read_only": True,
    },
    "overwrite_note": {
        "input": {"baseHash", "content", "id"},
        "output": {"changedMetadata"},
        "required": {"baseHash", "content"},
        "read_only": False,
    },
    "add_tags": {
        "input": {"id", "tags"},
        "output": set(),
        "required": {"tags"},
        "read_only": False,
    },
    "remove_tags": {
        "input": {"id", "tags"},
        "output": set(),
        "required": {"tags"},
        "read_only": False,
    },
}
METADATA = re.compile(r"^<!-- agent-workflows-record:(\{[^\n]*\}) -->\n")
RECORD_ID = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9._-]*[A-Za-z0-9])?")
TAG_MARKER = "<!-- agent-workflows-tags -->"
REVISION_PREFIX = "bear-base-hash:"
PAGE_SIZE = 100
PORTABLE_ERRORS = {
    "archived_record",
    "backend_mismatch",
    "duplicate_id",
    "invalid_destination",
    "invalid_id",
    "invalid_request",
    "invalid_state",
    "io_error",
    "malformed_record",
    "not_found",
    "stale_revision",
    "unsupported_operation",
    "unsupported_record_type",
}


class BearError(RuntimeError):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message

    def as_dict(self) -> dict[str, str]:
        return {"code": self.code, "message": self.message}


def validate_workspace(value: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip():
        raise BearError("invalid_workspace", "workspace must be a non-empty trimmed Bear tag")
    if "#" in value or value.startswith("/") or value.endswith("/"):
        raise BearError("invalid_workspace", "workspace must not contain # or start or end with /")
    if "," in value or "\\" in value or any(ord(character) < 32 for character in value):
        raise BearError("invalid_workspace", "workspace contains unsupported characters")
    if any(not segment or segment in {".", ".."} or segment != segment.strip() for segment in value.split("/")):
        raise BearError("invalid_workspace", "workspace has an invalid tag segment")
    return value


def validate_route_tag(value: str, workspace: str) -> str:
    try:
        tag = validate_workspace(value)
    except BearError as error:
        raise BearError("invalid_destination", error.message.replace("workspace", "route tag")) from error
    if tag == workspace or tag.startswith(workspace + "/"):
        raise BearError("invalid_destination", "route tag must be relative to the workspace")
    return tag


def validate_command(value: str) -> Path:
    path = Path(value)
    if not path.is_absolute():
        raise BearError("invalid_command", "bearcli command must be an absolute path")
    if not path.is_file() or not os.access(path, os.X_OK):
        raise BearError("command_unavailable", f"bearcli command is not executable: {value}")
    return path


class McpClient:
    def __init__(self, command: str, workspace: str, timeout: float = 5.0):
        self.command = validate_command(command)
        self.workspace = validate_workspace(workspace)
        self.timeout = timeout
        self.process: subprocess.Popen[str] | None = None
        self.next_id = 1

    def __enter__(self) -> "McpClient":
        try:
            self.process = subprocess.Popen(
                [str(self.command), "mcp-server", "--only-tags", self.workspace],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
        except OSError as error:
            raise BearError("command_unavailable", f"cannot launch bearcli: {error}") from error
        return self

    def __exit__(self, *_args: Any) -> None:
        if self.process is None:
            return
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=1)
        for stream in (self.process.stdin, self.process.stdout, self.process.stderr):
            if stream is not None:
                stream.close()

    def _write(self, value: dict[str, Any]) -> None:
        if self.process is None or self.process.stdin is None:
            raise BearError("protocol_error", "Bear MCP process is not running")
        try:
            self.process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
            self.process.stdin.flush()
        except (BrokenPipeError, OSError) as error:
            raise BearError("protocol_error", f"cannot write to Bear MCP server: {error}") from error

    def request(self, method: str, params: dict[str, Any]) -> dict[str, Any]:
        request_id = self.next_id
        self.next_id += 1
        self._write({"jsonrpc": "2.0", "id": request_id, "method": method, "params": params})
        while True:
            response = self._read()
            if response.get("id") != request_id:
                continue
            if response.get("jsonrpc") != "2.0":
                raise BearError("protocol_error", "Bear MCP response has an invalid JSON-RPC version")
            if "error" in response:
                error = response["error"]
                message = error.get("message") if isinstance(error, dict) else str(error)
                raise BearError("protocol_error", f"Bear MCP {method} failed: {message}")
            result = response.get("result")
            if not isinstance(result, dict):
                raise BearError("protocol_error", f"Bear MCP {method} returned no result mapping")
            return result

    def notify(self, method: str, params: dict[str, Any]) -> None:
        self._write({"jsonrpc": "2.0", "method": method, "params": params})

    def initialize(self) -> dict[str, Any]:
        initialized = self.request(
            "initialize",
            {
                "protocolVersion": PROTOCOL_VERSION,
                "capabilities": {},
                "clientInfo": {"name": "agent-workflows-bear", "version": "1"},
            },
        )
        if initialized.get("protocolVersion") != PROTOCOL_VERSION:
            raise BearError("protocol_error", "Bear MCP negotiated an unsupported protocol version")
        server = initialized.get("serverInfo")
        if not isinstance(server, dict) or server.get("name") != "bearcli":
            raise BearError("identity_mismatch", "MCP server is not bearcli")
        scope = server.get("scope")
        if not isinstance(scope, dict) or scope.get("onlyTags") != [self.workspace]:
            raise BearError("scope_mismatch", "Bear MCP server did not confirm the configured workspace")
        self.notify("notifications/initialized", {})
        return initialized

    def call_tool(self, name: str, arguments: dict[str, Any]) -> dict[str, Any]:
        result = self.request("tools/call", {"name": name, "arguments": arguments})
        if result.get("isError") is True:
            code = "io_error"
            message = f"Bear tool failed: {name}"
            content = result.get("content")
            if isinstance(content, list):
                for item in content:
                    if not isinstance(item, dict) or not isinstance(item.get("text"), str):
                        continue
                    try:
                        payload = json.loads(item["text"])
                    except json.JSONDecodeError:
                        message = item["text"] or message
                        continue
                    error = payload.get("error") if isinstance(payload, dict) else None
                    if isinstance(error, dict):
                        provider_code = error.get("code")
                        message = str(error.get("message") or message)
                        if provider_code == "note_not_found":
                            code = "not_found"
                        elif provider_code == "out_of_scope":
                            code = "invalid_destination"
                        elif isinstance(provider_code, str) and (
                            "stale" in provider_code or "hash" in provider_code
                        ):
                            code = "stale_revision"
                        elif provider_code in {"locked_note", "note_locked"}:
                            code = "invalid_state"
            raise BearError(code, message)
        structured = result.get("structuredContent")
        if not isinstance(structured, dict):
            raise BearError("protocol_error", f"Bear tool {name} returned no structured content")
        return structured

    def _read(self) -> dict[str, Any]:
        if self.process is None or self.process.stdout is None:
            raise BearError("protocol_error", "Bear MCP process is not running")
        ready, _, _ = select.select([self.process.stdout], [], [], self.timeout)
        if not ready:
            raise BearError("protocol_timeout", "Bear MCP server did not respond in time")
        line = self.process.stdout.readline()
        if not line:
            stderr = ""
            if self.process.stderr is not None and self.process.poll() is not None:
                stderr = self.process.stderr.read().strip()
            suffix = f": {stderr}" if stderr else ""
            raise BearError("protocol_error", f"Bear MCP server closed stdout{suffix}")
        try:
            value = json.loads(line)
        except json.JSONDecodeError as error:
            raise BearError("protocol_error", f"Bear MCP returned malformed JSON: {error}") from error
        if not isinstance(value, dict):
            raise BearError("protocol_error", "Bear MCP response must be a mapping")
        return value


def _schema_properties(tool: dict[str, Any], field: str) -> set[str]:
    schema = tool.get(field)
    properties = schema.get("properties") if isinstance(schema, dict) else None
    return set(properties) if isinstance(properties, dict) else set()


def validate_tools(tools: Any) -> list[str]:
    if not isinstance(tools, list):
        raise BearError("protocol_error", "Bear MCP tools/list returned no tool list")
    by_name = {
        tool.get("name"): tool
        for tool in tools
        if isinstance(tool, dict) and isinstance(tool.get("name"), str)
    }
    problems = []
    for name, expected in sorted(REQUIRED_TOOLS.items()):
        tool = by_name.get(name)
        if tool is None:
            problems.append(f"missing tool {name}")
            continue
        missing_input = expected["input"] - _schema_properties(tool, "inputSchema")
        missing_output = expected["output"] - _schema_properties(tool, "outputSchema")
        required = set(tool.get("inputSchema", {}).get("required", []))
        missing_required = expected.get("required", set()) - required
        annotations = tool.get("annotations")
        read_only = annotations.get("readOnlyHint") if isinstance(annotations, dict) else None
        if missing_input:
            problems.append(f"{name} input missing {', '.join(sorted(missing_input))}")
        if missing_output:
            problems.append(f"{name} output missing {', '.join(sorted(missing_output))}")
        if missing_required:
            problems.append(f"{name} required input missing {', '.join(sorted(missing_required))}")
        if read_only is not expected["read_only"]:
            problems.append(f"{name} has wrong readOnlyHint")
    return problems


class BearRecordAdapter:
    """Portable non-issue record adapter over one scoped Bear MCP client."""

    def __init__(self, client: Any, backend: str, workspace: str):
        self.client = client
        self.backend = backend
        self.workspace = validate_workspace(workspace)

    def _destination(self, destination: dict[str, Any]) -> str:
        if not isinstance(destination, dict) or set(destination) != {"tag"}:
            raise RecordError("invalid_destination", "Bear destination requires exactly tag")
        tag = destination.get("tag")
        if not isinstance(tag, str):
            raise RecordError("invalid_destination", "Bear route tag must be a string")
        try:
            return f"{self.workspace}/{validate_route_tag(tag, self.workspace)}"
        except BearError as error:
            raise RecordError("invalid_destination", error.message) from error

    @staticmethod
    def _hashtag(tag: str) -> str:
        return f"#{tag}#" if any(character.isspace() for character in tag) else f"#{tag}"

    def _tag_footer(self, route_tag: str) -> str:
        return f"{TAG_MARKER}\n{self._hashtag(self.workspace)} {self._hashtag(route_tag)}"

    def _managed_body(
        self,
        metadata: dict[str, Any],
        title: str,
        content: str,
        route_tag: str,
    ) -> str:
        if "\n" in title or "\r" in title:
            raise RecordError("invalid_request", "Bear record title must fit on one line")
        encoded = json.dumps(metadata, sort_keys=True, separators=(",", ":"))
        return (
            f"<!-- agent-workflows-record:{encoded} -->\n"
            f"# {title}\n\n{content}\n\n{self._tag_footer(route_tag)}"
        )

    def _parse_body(
        self,
        body: Any,
        route_tag: str,
    ) -> tuple[dict[str, Any], str, str]:
        if not isinstance(body, str):
            raise RecordError("malformed_record", "Bear managed note has no Markdown content")
        match = METADATA.match(body)
        if not match:
            raise RecordError("malformed_record", "Bear managed metadata is missing")
        try:
            metadata = json.loads(match.group(1))
        except json.JSONDecodeError as error:
            raise RecordError("malformed_record", "Bear managed metadata is invalid") from error
        if set(metadata) != {"archived", "id", "record_type"} or (
            not isinstance(metadata["archived"], bool)
            or not isinstance(metadata["id"], str)
            or not RECORD_ID.fullmatch(metadata["id"])
            or metadata["record_type"] not in NON_ISSUE_RECORD_TYPES
        ):
            raise RecordError("malformed_record", "Bear managed metadata has invalid fields")
        remainder = body[match.end():]
        heading_end = remainder.find("\n\n")
        if heading_end < 0 or not remainder.startswith("# "):
            raise RecordError("malformed_record", "Bear managed title heading is missing")
        title = remainder[2:heading_end]
        if not title or "\n" in title:
            raise RecordError("malformed_record", "Bear managed title is invalid")
        suffix = f"\n\n{self._tag_footer(route_tag)}"
        framed = remainder[heading_end + 2:]
        if not framed.endswith(suffix):
            raise RecordError("malformed_record", "Bear managed tag framing is missing")
        return metadata, title, framed[:-len(suffix)]

    @staticmethod
    def _revision(value: Any) -> str:
        if not isinstance(value, str) or not value:
            raise RecordError("malformed_record", "Bear whole-note hash is missing")
        return REVISION_PREFIX + value

    @staticmethod
    def _native_metadata(value: Any) -> dict[str, Any]:
        if not isinstance(value, dict):
            raise RecordError("malformed_record", "Bear note metadata is missing")
        required = {"id", "tags", "title"}
        if not required.issubset(value) or not isinstance(value["id"], str):
            raise RecordError("malformed_record", "Bear note metadata is incomplete")
        if not isinstance(value["tags"], list) or any(
            not isinstance(tag, str) for tag in value["tags"]
        ):
            raise RecordError("malformed_record", "Bear note tags are invalid")
        return value

    def _read_native(self, native: dict[str, Any], route_tag: str) -> StoredRecord:
        metadata = self._native_metadata(native)
        expected_tags = {self.workspace, route_tag}
        if not expected_tags.issubset(metadata["tags"]):
            raise RecordError("malformed_record", "Bear note is missing managed workspace tags")
        read = self.client.call_tool("read_note_content", {"id": metadata["id"]})
        managed, title, content = self._parse_body(read.get("content"), route_tag)
        revision = self._revision(read.get("hash"))
        note_id = metadata["id"]
        return StoredRecord(
            record_type=managed["record_type"],
            id=managed["id"],
            title=title,
            content=content,
            revision=revision,
            reference=RecordReference(
                backend=self.backend,
                id=note_id,
                title=title,
                href=f"bear://x-callback-url/open-note?id={quote(note_id, safe='')}",
            ),
            metadata={
                "archived": managed["archived"],
                "attachments": list(metadata.get("attachments", [])),
                "location": metadata.get("location", "notes"),
                "modified": metadata.get("modified"),
                "tags": list(metadata["tags"]),
            },
        )

    def _get_native(self, note_id: str) -> dict[str, Any]:
        result = self.client.call_tool("get_note", {"id": note_id, "includeContent": False})
        return self._native_metadata(result.get("metadata"))

    def _all_records(self, record_type: str, route_tag: str) -> list[StoredRecord]:
        records = []
        offset = 0
        while True:
            result = self.client.call_tool(
                "list_notes",
                {
                    "includeContent": False,
                    "limit": PAGE_SIZE,
                    "location": "notes",
                    "offset": offset,
                    "sort": "title:asc",
                    "tag": route_tag,
                },
            )
            notes = result.get("metadata")
            if notes is None:
                notes = [item.get("metadata") for item in result.get("notes", []) if isinstance(item, dict)]
            total = result.get("total")
            if not isinstance(notes, list) or not isinstance(total, int) or total < 0:
                raise RecordError("io_error", "Bear list returned an invalid page")
            for native in notes:
                record = self._read_native(self._native_metadata(native), route_tag)
                if record.record_type != record_type:
                    raise RecordError("malformed_record", "Bear metadata and route type disagree")
                records.append(record)
            offset += len(notes)
            if offset >= total:
                break
            if not notes:
                raise RecordError("io_error", "Bear list pagination made no progress")
        records.sort(key=lambda record: record.id)
        return records

    def _record_by_id(self, record_type: str, record_id: str, route_tag: str) -> StoredRecord:
        matches = [
            record for record in self._all_records(record_type, route_tag)
            if record.id == record_id
        ]
        if not matches:
            raise RecordError("not_found", f"record does not exist: {record_id}")
        if len(matches) > 1:
            raise RecordError("duplicate_id", f"record id has several owners: {record_id}")
        return matches[0]

    @staticmethod
    def _slug(title: str) -> str:
        slug = re.sub(r"[^a-z0-9]+", "-", title.casefold()).strip("-")
        return slug or "record"

    @staticmethod
    def _provider_error(error: BearError) -> RecordError:
        code = error.code if error.code in PORTABLE_ERRORS else "io_error"
        return RecordError(code, error.message)

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
        if request.record_type not in NON_ISSUE_RECORD_TYPES:
            raise RecordError("unsupported_record_type", request.record_type)
        route_tag = self._destination(request.destination)
        try:
            if request.operation == "create":
                records = self._all_records(request.record_type, route_tag)
                existing = {record.id for record in records}
                if request.semantic_id is not None:
                    if not RECORD_ID.fullmatch(request.semantic_id):
                        raise RecordError("invalid_id", f"invalid semantic id: {request.semantic_id}")
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
                if record_id in {
                    record.id for record in self._all_records(request.record_type, route_tag)
                }:
                    raise RecordError("duplicate_id", f"record id already exists: {record_id}")
                managed = {"archived": False, "id": record_id, "record_type": request.record_type}
                created = self.client.call_tool(
                    "create_note",
                    {
                        "content": self._managed_body(
                            managed, request.title or "", request.content or "", route_tag
                        ),
                        "ifNotExists": False,
                        "tags": [self.workspace, route_tag],
                        "title": request.title,
                    },
                )
                note_id = created.get("id")
                if not isinstance(note_id, str) or not note_id:
                    raise RecordError("io_error", "Bear create returned no note id")
                return RecordResponse(record=self._read_native(self._get_native(note_id), route_tag))
            if request.operation == "list":
                records = [
                    record for record in self._all_records(request.record_type, route_tag)
                    if not record.metadata["archived"]
                ]
                if request.id:
                    records = [record for record in records if record.id == request.id]
                if request.query:
                    query = request.query.casefold()
                    records = [
                        record for record in records
                        if query in record.id.casefold()
                        or query in record.title.casefold()
                        or query in record.content.casefold()
                    ]
                return RecordResponse(records=tuple(records))
            current = self._record_by_id(request.record_type, request.id or "", route_tag)
            if request.operation == "read":
                return RecordResponse(record=current)
            if current.revision != request.expected_revision:
                raise RecordError("stale_revision", f"record changed since read: {current.id}")
            if current.metadata["attachments"]:
                raise RecordError("invalid_state", "managed Bear records with attachments cannot be overwritten")
            managed = {
                "archived": request.operation == "archive" or current.metadata["archived"],
                "id": current.id,
                "record_type": current.record_type,
            }
            title = request.title if request.title is not None else current.title
            content = request.content if request.content is not None else current.content
            base_hash = current.revision.removeprefix(REVISION_PREFIX)
            self.client.call_tool(
                "overwrite_note",
                {
                    "baseHash": base_hash,
                    "content": self._managed_body(managed, title, content, route_tag),
                    "expectedRemovedAttachments": [],
                    "id": current.reference.id,
                },
            )
            return RecordResponse(
                record=self._read_native(self._get_native(current.reference.id), route_tag)
            )
        except RecordError:
            raise
        except BearError as error:
            raise self._provider_error(error) from error


def preflight(command: str, workspace: str, timeout: float = 5.0) -> dict[str, Any]:
    with McpClient(command, workspace, timeout) as client:
        initialized = client.initialize()
        server = initialized["serverInfo"]
        listed = client.request("tools/list", {})
        tools = listed.get("tools")
        problems = validate_tools(tools)
        if problems:
            raise BearError("capability_rejection", "; ".join(problems))
        return {
            "backend": "bear",
            "capabilities": {
                "record_contract": "provider-complete",
                "record_operations": sorted(RECORD_OPERATIONS),
                "record_types": sorted(NON_ISSUE_RECORD_TYPES),
                "required_tools": sorted(REQUIRED_TOOLS),
            },
            "command": str(client.command),
            "read_only": True,
            "server": {
                "name": server["name"],
                "version": server.get("version"),
            },
            "workspace": client.workspace,
        }


def _content(path: str) -> str:
    return sys.stdin.read() if path == "-" else Path(path).read_text()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--command", required=True)
    parser.add_argument("--workspace", required=True)
    parser.add_argument("--backend")
    parser.add_argument("--destination-tag")
    parser.add_argument("--timeout", type=float, default=5.0)
    commands = parser.add_subparsers(dest="operation", required=True)
    commands.add_parser("preflight")

    create = commands.add_parser("record-create")
    create.add_argument("--record-type", choices=sorted(NON_ISSUE_RECORD_TYPES), required=True)
    create.add_argument("--title", required=True)
    create.add_argument("--content-file", required=True)
    create.add_argument("--semantic-id")

    read = commands.add_parser("record-read")
    read.add_argument("--record-type", choices=sorted(NON_ISSUE_RECORD_TYPES), required=True)
    read.add_argument("id")

    listed = commands.add_parser("record-list")
    listed.add_argument("--record-type", choices=sorted(NON_ISSUE_RECORD_TYPES), required=True)
    listed.add_argument("--query")

    update = commands.add_parser("record-update")
    update.add_argument("--record-type", choices=sorted(NON_ISSUE_RECORD_TYPES), required=True)
    update.add_argument("id")
    update.add_argument("--expected-revision", required=True)
    update.add_argument("--title")
    update.add_argument("--content-file")

    archive = commands.add_parser("record-archive")
    archive.add_argument("--record-type", choices=sorted(NON_ISSUE_RECORD_TYPES), required=True)
    archive.add_argument("id")
    archive.add_argument("--expected-revision", required=True)

    render = commands.add_parser("render-reference")
    render.add_argument("--reference-file", required=True)
    return parser


def main(arguments: list[str] | None = None) -> int:
    args = build_parser().parse_args(arguments)
    try:
        if args.operation == "preflight":
            result = {"ok": True, **preflight(args.command, args.workspace, args.timeout)}
        elif args.operation == "render-reference":
            if not args.backend:
                raise RecordError("invalid_request", "--backend is required")
            try:
                value = json.loads(Path(args.reference_file).read_text())
            except (OSError, json.JSONDecodeError) as error:
                raise RecordError("malformed_reference", f"cannot read reference: {error}") from error
            adapter = BearRecordAdapter(None, args.backend, args.workspace)
            result = {"rendered": adapter.render_reference(RecordReference.from_dict(value))}
        else:
            if not args.backend or not args.destination_tag:
                raise RecordError(
                    "invalid_request", "--backend and --destination-tag are required"
                )
            operation = args.operation.removeprefix("record-")
            request = RecordRequest(
                operation=operation,
                backend=args.backend,
                record_type=args.record_type,
                destination={"tag": args.destination_tag},
                id=getattr(args, "id", None),
                title=getattr(args, "title", None),
                content=(
                    _content(args.content_file)
                    if getattr(args, "content_file", None) is not None
                    else None
                ),
                expected_revision=getattr(args, "expected_revision", None),
                semantic_id=getattr(args, "semantic_id", None),
                query=getattr(args, "query", None),
            )
            with McpClient(args.command, args.workspace, args.timeout) as client:
                client.initialize()
                result = BearRecordAdapter(
                    client, args.backend, args.workspace
                ).execute(request).as_dict()
    except (BearError, RecordError) as error:
        print(
            json.dumps(
                {"error": {"code": error.code, "message": error.message}, "ok": False},
                sort_keys=True,
            )
        )
        return 1
    except (OSError, json.JSONDecodeError) as error:
        print(
            json.dumps(
                {"error": {"code": "io_error", "message": str(error)}, "ok": False},
                sort_keys=True,
            )
        )
        return 1
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
