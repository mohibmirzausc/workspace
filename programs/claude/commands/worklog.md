---
name: worklog
description: Update the Release Engineering work log page in Notion with today's session summary
disable-model-invocation: true
---

Find the Release Engineering work log page for today in Notion and update it with a summary of the work done in this session.

Steps:
1. Search Notion for "Worklog" with today's date (YYYY-MM-DD format) in the RelEng Team Calendar
   - Look for the page titled "Worklog" (not "Work Log @Today")
   - Verify it has the date:Date:start property set to today's date
   - If multiple pages exist, choose the one with content from other team members
2. Fetch the current content of the work log page using the page ID
3. **CRITICAL: Verify and set the Date property**
   - Check if the page has `date:Date:start` property set to today's date (YYYY-MM-DD)
   - If the Date property is missing or incorrect, update it using update_properties:
     ```json
     {"date:Date:start": "YYYY-MM-DD", "date:Date:is_datetime": 0}
     ```
   - This ensures the page appears correctly in the calendar view
4. Analyze the conversation history to identify:
   - What tasks were worked on
   - What problems were solved
   - What files were modified
   - What decisions were made
   - Any PRs created or branches pushed
5. Generate a concise summary in the work log format (bullet points under H3 headings)
6. Append to the end of the page using insert_content_after:
   - Find a unique pattern at the very end of the existing content (typically the last line before <empty-block/>)
   - Add a new section: "## Zoe Gagnon" (or appropriate user name)
   - Add subsections with H3 headings for each major work item
   - IMPORTANT: Use insert_content_after, not replace_content
7. If the append fails due to pattern matching, try using a different unique end pattern

Format the summary as:
- Brief, action-oriented bullet points
- Include links to PRs, branches, or relevant resources using full URLs
- Group related work together under descriptive H3 headings
- Highlight key decisions or blockers with **bold** for emphasis
- Use code blocks for technical details like commands or file paths
