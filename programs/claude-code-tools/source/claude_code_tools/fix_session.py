#!/usr/bin/env python3
"""
Fix orphan parentUuid references in Claude Code session files.

This addresses the bug described in:
https://github.com/anthropics/claude-code/issues/22107

The bug causes broken parent chain references when
progress/subagent UUIDs contaminate the conversation chain,
resulting in lost context on session resume.

Usage as CLI:
    # Analyze only (dry run) - accepts partial session ID
    fix-session f8ddc

    # Fix in place (creates .bak backup)
    fix-session f8ddc --fix --in-place

    # Fix and write to new file
    fix-session f8ddc --fix --output fixed.jsonl

Usage as library:
    from claude_code_tools.fix_session import check_and_fix_session
    needed_fix = check_and_fix_session(Path("session.jsonl"))
"""

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Optional

from claude_code_tools.session_utils import resolve_session_path

# Entry types that form the actual conversation chain
CONVERSATION_TYPES = {"user", "assistant", "system", "summary"}


def load_session(filepath: str | Path) -> list[dict]:
    """Load all entries from a session JSONL file."""
    entries = []
    with open(filepath) as f:
        for line in f:
            line = line.strip()
            if line:
                entries.append(json.loads(line))
    return entries


def is_conversation_entry(entry: dict) -> bool:
    """Check if entry is part of the conversation chain."""
    return entry.get("type") in CONVERSATION_TYPES


def analyze_session(entries: list[dict]) -> dict:
    """Analyze session for chain breaks.

    Returns comprehensive analysis including:

    - All entries and conversation entries
    - UUID mappings
    - Chain analysis from the end
    - Orphan detection
    """
    # Separate conversation entries
    conv_entries = [
        (i, e)
        for i, e in enumerate(entries)
        if is_conversation_entry(e)
    ]

    # Build UUID maps
    all_uuid_to_entry = {
        e["uuid"]: e for e in entries if "uuid" in e
    }
    conv_uuid_to_entry = {
        e["uuid"]: e for i, e in conv_entries if "uuid" in e
    }
    conv_uuid_to_idx = {
        e["uuid"]: idx
        for idx, e in conv_entries
        if "uuid" in e
    }

    # Find conversation entries with orphan parents
    orphan_conv_entries = []
    for file_idx, entry in conv_entries:
        parent = entry.get("parentUuid")
        if parent and parent not in conv_uuid_to_entry:
            parent_entry = all_uuid_to_entry.get(parent)
            parent_type = (
                parent_entry.get("type")
                if parent_entry
                else "MISSING"
            )
            orphan_conv_entries.append(
                {
                    "file_idx": file_idx,
                    "entry": entry,
                    "orphan_parent": parent,
                    "parent_type": parent_type,
                }
            )

    # Walk conversation chain from end
    chain_length = 0
    chain_break = None
    if conv_entries:
        _, last_conv = conv_entries[-1]
        current = last_conv
        while current:
            chain_length += 1
            parent = current.get("parentUuid")
            if not parent:
                break  # Reached root
            if parent not in conv_uuid_to_entry:
                parent_entry = all_uuid_to_entry.get(parent)
                chain_break = {
                    "after_length": chain_length,
                    "orphan_parent": parent,
                    "parent_type": (
                        parent_entry.get("type")
                        if parent_entry
                        else "MISSING"
                    ),
                    "current_entry_type": current.get("type"),
                }
                break
            current = conv_uuid_to_entry[parent]
            if chain_length > 10000:
                break

    return {
        "entries": entries,
        "conv_entries": conv_entries,
        "all_uuid_to_entry": all_uuid_to_entry,
        "conv_uuid_to_entry": conv_uuid_to_entry,
        "conv_uuid_to_idx": conv_uuid_to_idx,
        "orphan_conv_entries": orphan_conv_entries,
        "chain_length": chain_length,
        "chain_break": chain_break,
        "stats": {
            "total_entries": len(entries),
            "conversation_entries": len(conv_entries),
            "orphan_count": len(orphan_conv_entries),
            "chain_length": chain_length,
        },
    }


def find_previous_conversation_uuid(
    conv_entries: list[tuple[int, dict]],
    file_idx: int,
) -> Optional[str]:
    """Find the UUID of the previous conversation entry.

    Args:
        conv_entries: List of (file_idx, entry) tuples for
            conversation entries.
        file_idx: Current entry's index in the full file.

    Returns:
        UUID of the previous conversation entry, or None if
        this is the first.
    """
    prev_uuid = None
    for idx, entry in conv_entries:
        if idx >= file_idx:
            break
        if "uuid" in entry:
            prev_uuid = entry["uuid"]
    return prev_uuid


def fix_conversation_chain(
    analysis: dict,
) -> tuple[list[dict], int]:
    """Fix the conversation chain by relinking orphan parents.

    For each conversation entry whose parentUuid points to a
    non-conversation entry, relink it to the previous
    conversation entry in file order.
    """
    entries = analysis["entries"]
    conv_entries = analysis["conv_entries"]
    fixed = [e.copy() for e in entries]

    fixes_made = 0
    for orphan_info in analysis["orphan_conv_entries"]:
        file_idx = orphan_info["file_idx"]
        prev_conv_uuid = find_previous_conversation_uuid(
            conv_entries, file_idx
        )

        if prev_conv_uuid:
            fixed[file_idx]["parentUuid"] = prev_conv_uuid
        else:
            # This is the first conversation entry
            fixed[file_idx]["parentUuid"] = None
        fixes_made += 1

    return fixed, fixes_made


def write_session(entries: list[dict], filepath: str | Path) -> None:
    """Write entries to a JSONL file."""
    with open(filepath, "w") as f:
        for e in entries:
            f.write(json.dumps(e, separators=(",", ":")) + "\n")


def print_analysis(
    analysis: dict, verbose: bool = False
) -> None:
    """Print analysis results."""
    stats = analysis["stats"]

    print("Session Analysis:")
    print(f"  Total entries: {stats['total_entries']}")
    print(
        f"  Conversation entries: "
        f"{stats['conversation_entries']}"
    )
    print(
        f"  Orphan parents in conversation: "
        f"{stats['orphan_count']}"
    )
    print(
        f"  Chain length from end: {stats['chain_length']}"
    )

    if analysis["chain_break"]:
        cb = analysis["chain_break"]
        print(f"\n  CHAIN BREAK detected:")
        print(f"  Breaks after {cb['after_length']} entries")
        print(f"  Orphan parent type: {cb['parent_type']}")
        print(
            f"  Current entry type: "
            f"{cb['current_entry_type']}"
        )
        print(
            f"  Orphan parent UUID: "
            f"{cb['orphan_parent'][:20]}..."
        )

    if stats["orphan_count"] == 0:
        print(
            "\n  No orphan references in conversation "
            "chain - session is healthy!"
        )
        return

    if verbose:
        print(f"\nOrphan entries (showing first 10):")
        for info in analysis["orphan_conv_entries"][:10]:
            entry = info["entry"]
            print(
                f"\n  Line {info['file_idx']}: "
                f"type={entry.get('type')}"
            )
            print(
                f"    uuid: "
                f"{entry.get('uuid', 'none')[:20]}..."
            )
            print(
                f"    orphan parent: "
                f"{info['orphan_parent'][:20]}..."
            )
            print(
                f"    parent type: {info['parent_type']}"
            )


def check_and_fix_session(session_path: Path) -> bool:
    """Programmatic API: auto-fix a session in place.

    Analyzes the session for orphan parent references. If any
    are found, fixes them in place (creating a .bak backup)
    and prints a brief summary.

    Args:
        session_path: Path to the session JSONL file.

    Returns:
        True if fixes were needed and applied, False if the
        session was already healthy.
    """
    if not session_path.exists():
        return False

    entries = load_session(session_path)
    analysis = analyze_session(entries)

    if analysis["stats"]["orphan_count"] == 0:
        return False

    # Apply fixes
    fixed, fixes_made = fix_conversation_chain(analysis)

    # Verify
    verify = analyze_session(fixed)

    # Create backup and write
    backup = session_path.with_suffix(
        session_path.suffix + ".bak"
    )
    shutil.copy2(session_path, backup)
    write_session(fixed, session_path)

    # Brief summary
    chain_status = (
        "chain complete"
        if not verify["chain_break"]
        else (
            f"chain breaks after "
            f"{verify['chain_break']['after_length']} entries"
        )
    )
    print(
        f"fix-session: Fixed {fixes_made} orphan(s) in "
        f"{session_path.name} ({chain_status})"
    )

    return True


def main() -> None:
    """CLI entry point for fix-session."""
    parser = argparse.ArgumentParser(
        description=(
            "Fix orphan parentUuid references in "
            "Claude Code session files"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  fix-session f8ddc            "
            "  # Analyze session by partial ID\n"
            "  fix-session f8ddc --fix --in-place"
            "  # Fix in place\n"
            "  fix-session f8ddc --fix -o out.jsonl"
            "  # Fix to new file\n"
        ),
    )
    parser.add_argument(
        "session",
        help=(
            "Session identifier: partial ID, full UUID, "
            "or path to .jsonl file"
        ),
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="Apply fixes (default is analyze only)",
    )
    parser.add_argument(
        "--output",
        "-o",
        help="Output file for fixed session (requires --fix)",
    )
    parser.add_argument(
        "--in-place",
        action="store_true",
        help=(
            "Fix in place, creating .bak backup "
            "(requires --fix)"
        ),
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Show more details about orphan entries",
    )

    args = parser.parse_args()

    if args.in_place and args.output:
        print(
            "Error: Cannot use both --in-place and --output",
            file=sys.stderr,
        )
        sys.exit(1)

    if (args.output or args.in_place) and not args.fix:
        print(
            "Error: --output and --in-place require --fix",
            file=sys.stderr,
        )
        sys.exit(1)

    # Resolve session path (supports partial IDs)
    try:
        session_path = resolve_session_path(args.session)
    except (FileNotFoundError, ValueError) as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

    # Load and analyze
    print(f"Loading: {session_path}\n")
    entries = load_session(session_path)
    analysis = analyze_session(entries)

    print_analysis(analysis, verbose=args.verbose)

    if not args.fix:
        if analysis["stats"]["orphan_count"] > 0:
            print(
                "\nRun with --fix to repair the "
                "conversation chain"
            )
        return

    if analysis["stats"]["orphan_count"] == 0:
        print("\nNothing to fix.")
        return

    # Apply fixes
    fixed, fixes_made = fix_conversation_chain(analysis)
    print(f"\nApplied {fixes_made} fixes")

    # Verify fix
    verify = analyze_session(fixed)
    print(f"\nVerification:")
    print(
        f"  Orphans remaining: "
        f"{verify['stats']['orphan_count']}"
    )
    print(
        f"  New chain length: "
        f"{verify['stats']['chain_length']}"
    )

    if verify["chain_break"]:
        print(
            f"  Chain still breaks after "
            f"{verify['chain_break']['after_length']} entries"
        )
    else:
        print(f"  Chain is now complete!")

    # Write output
    if args.in_place:
        backup = str(session_path) + ".bak"
        shutil.copy2(session_path, backup)
        print(f"\nBackup created: {backup}")
        write_session(fixed, session_path)
        print(f"Fixed in place: {session_path}")
    elif args.output:
        write_session(fixed, args.output)
        print(f"\nFixed session written to: {args.output}")
    else:
        print(
            "\nNo output specified. "
            "Use --output or --in-place to save fixes."
        )


if __name__ == "__main__":
    main()
