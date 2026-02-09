#!/usr/bin/env python3
"""
csv2gsheet: Upload CSV files to Google Drive as native Google Sheets.

This tool uses the Google Drive API to upload CSV files with native
conversion to Google Sheets format.

Prerequisites:
- First run: Will open browser for OAuth authentication (one-time setup)
- Credentials stored in .gdoc-credentials.json (local) or ~/.config/md2gdoc/
"""

import argparse
import re
import sys
from pathlib import Path
from typing import Optional

from rich.console import Console
from rich.panel import Panel
from rich.prompt import Prompt
from rich.text import Text

console = Console()

# Import shared utilities from md2gdoc
from claude_code_tools.md2gdoc import (
    check_dependencies,
    get_drive_service,
    find_folder_id,
)


def check_sheet_exists(
    service, folder_id: Optional[str], filename: str
) -> bool:
    """Check if a spreadsheet with this name exists."""
    parent = folder_id if folder_id else "root"
    query = (
        f"name = '{filename}' and "
        f"'{parent}' in parents and "
        f"mimeType = 'application/vnd.google-apps.spreadsheet'"
        f" and trashed = false"
    )
    results = (
        service.files()
        .list(
            q=query,
            fields="files(id, name)",
            pageSize=10,
            supportsAllDrives=True,
            includeItemsFromAllDrives=True,
        )
        .execute()
    )
    return len(results.get("files", [])) > 0


def list_existing_versions(
    service, folder_id: Optional[str], base_name: str
) -> list[str]:
    """List spreadsheets matching the base name pattern."""
    parent = folder_id if folder_id else "root"
    query = (
        f"name contains '{base_name}' and "
        f"'{parent}' in parents and "
        f"mimeType = 'application/vnd.google-apps.spreadsheet'"
        f" and trashed = false"
    )
    results = (
        service.files()
        .list(
            q=query,
            fields="files(id, name)",
            pageSize=100,
            supportsAllDrives=True,
            includeItemsFromAllDrives=True,
        )
        .execute()
    )
    return [f["name"] for f in results.get("files", [])]


def get_next_version_name(
    service, folder_id: Optional[str], base_name: str
) -> str:
    """Get next available version name."""
    existing = list_existing_versions(service, folder_id, base_name)
    if not existing:
        return f"{base_name}-1"

    max_version = 0
    for f in existing:
        match = re.match(rf"^{re.escape(base_name)}-(\d+)$", f)
        if match:
            max_version = max(max_version, int(match.group(1)))
    return f"{base_name}-{max_version + 1}"


def delete_sheet(
    service, folder_id: Optional[str], filename: str
) -> bool:
    """Delete a spreadsheet by name (for overwrite)."""
    parent = folder_id if folder_id else "root"
    query = (
        f"name = '{filename}' and "
        f"'{parent}' in parents and "
        f"mimeType = 'application/vnd.google-apps.spreadsheet'"
        f" and trashed = false"
    )
    results = (
        service.files()
        .list(
            q=query,
            fields="files(id)",
            pageSize=1,
            supportsAllDrives=True,
            includeItemsFromAllDrives=True,
        )
        .execute()
    )
    files = results.get("files", [])
    if files:
        service.files().delete(
            fileId=files[0]["id"],
            supportsAllDrives=True,
        ).execute()
        return True
    return False


def prompt_for_conflict(
    existing_name: str, versioned_name: str
) -> Optional[str]:
    """Prompt user when file already exists."""
    console.print()
    console.print(
        Panel(
            f"[yellow]Spreadsheet already exists:[/yellow] "
            f"[bold]{existing_name}[/bold]",
            title="Conflict Detected",
            border_style="yellow",
        )
    )
    console.print()

    options_text = Text()
    options_text.append("  [Enter] ", style="cyan bold")
    options_text.append("Add version suffix → ", style="dim")
    options_text.append(f"{versioned_name}\n", style="green")
    options_text.append("  [YES]   ", style="red bold")
    options_text.append("Overwrite existing file", style="dim")
    console.print(options_text)
    console.print()

    choice = Prompt.ask("Your choice", default="", show_default=False)
    if choice == "":
        return "version"
    elif choice.upper() == "YES":
        return "overwrite"
    else:
        console.print("[dim]Invalid choice. Cancelling.[/dim]")
        return None


def upload_csv(
    service,
    csv_path: Path,
    folder_id: Optional[str],
    filename: str,
) -> Optional[tuple[str, str]]:
    """Upload CSV to Drive with native conversion to Google Sheets.

    Returns (webViewLink, fileId) or None on failure.
    """
    from googleapiclient.http import MediaFileUpload

    file_metadata: dict = {
        "name": filename,
        "mimeType": "application/vnd.google-apps.spreadsheet",
    }
    if folder_id:
        file_metadata["parents"] = [folder_id]

    media = MediaFileUpload(
        str(csv_path),
        mimetype="text/csv",
        resumable=True,
    )
    try:
        with console.status("[cyan]Uploading to Google Drive...[/cyan]"):
            f = (
                service.files()
                .create(
                    body=file_metadata,
                    media_body=media,
                    fields="id,webViewLink",
                )
                .execute()
            )
        return (f.get("webViewLink"), f.get("id"))
    except Exception as e:
        console.print(f"[red]Upload error:[/red] {e}")
        return None


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Upload CSV files to Google Drive as Google Sheets.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  csv2gsheet data.csv
  csv2gsheet data.csv --folder "Reports/Data"
  csv2gsheet data.csv --name "Q4 Sales Data"
  csv2gsheet data.csv --on-existing overwrite
        """,
    )

    parser.add_argument(
        "csv_file",
        type=Path,
        help="Path to the CSV file to upload",
    )
    parser.add_argument(
        "--folder", "-f",
        type=str,
        default="",
        help="Target folder in Google Drive (e.g., 'Reports/Data')",
    )
    parser.add_argument(
        "--name", "-n",
        type=str,
        default="",
        help="Name for the Google Sheet (default: CSV filename)",
    )
    parser.add_argument(
        "--on-existing",
        type=str,
        default="ask",
        choices=["ask", "version", "overwrite"],
        help="Action when file exists (default: ask)",
    )

    args = parser.parse_args()

    if not check_dependencies():
        sys.exit(1)

    if not args.csv_file.exists():
        console.print(f"[red]Error:[/red] File not found: {args.csv_file}")
        sys.exit(1)

    if args.csv_file.suffix.lower() != ".csv":
        console.print(
            "[yellow]Warning:[/yellow] File doesn't have .csv extension, "
            "proceeding anyway"
        )

    service = get_drive_service()
    if not service:
        sys.exit(1)

    folder_id = None
    if args.folder:
        console.print(f"[dim]Finding folder: {args.folder}[/dim]")
        folder_id = find_folder_id(service, args.folder)

    target_name = args.name if args.name else args.csv_file.stem

    file_exists = check_sheet_exists(service, folder_id, target_name)
    final_name = target_name

    if file_exists:
        versioned_name = get_next_version_name(service, folder_id, target_name)
        on_existing = args.on_existing

        if on_existing == "ask":
            action = prompt_for_conflict(target_name, versioned_name)
            if action is None:
                console.print("[dim]Upload cancelled.[/dim]")
                sys.exit(0)
        else:
            action = on_existing

        if action == "version":
            final_name = versioned_name
            console.print(f"[dim]Using versioned name: {final_name}[/dim]")
        elif action == "overwrite":
            console.print(f"[dim]Deleting existing: {target_name}[/dim]")
            delete_sheet(service, folder_id, target_name)

    console.print(
        f"[cyan]Uploading[/cyan] {args.csv_file.name} → Google Sheets..."
    )
    result = upload_csv(service, args.csv_file, folder_id, final_name)

    if not result:
        sys.exit(1)

    web_link, _sheet_id = result

    location = f"{args.folder}/{final_name}" if args.folder else final_name

    console.print()
    console.print(
        Panel(
            f"[green]Successfully uploaded![/green]\n\n"
            f"[dim]Name:[/dim] {final_name}\n"
            f"[dim]Location:[/dim] {location}\n"
            f"[dim]Link:[/dim] {web_link}",
            title="Done",
            border_style="green",
        )
    )


if __name__ == "__main__":
    main()
