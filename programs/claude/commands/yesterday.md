---
name: yesterday
description: Read and summarize yesterday's Release Engineering work log from Notion
disable-model-invocation: true
---

Find and summarize yesterday's Release Engineering work log from Notion, paying close attention to open questions and action items.

**IMPORTANT: Authentication Note**
If Notion tools return a 400 error, it likely needs re-authentication. The user should re-authenticate with Notion using the appropriate MCP authentication flow.

Steps:
1. Calculate yesterday's date (current date - 1 day) in YYYY-MM-DD format
2. Search Notion for the work log from yesterday:
   - Search query: "work log"
   - Use date filters: `{"created_date_range": {"start_date": "YYYY-MM-DD", "end_date": "YYYY-MM-DD"}}`
   - Look for page titled "Work Log @Yesterday" or "Worklog" with yesterday's date
3. Fetch the full content of yesterday's work log page using the page ID
4. Analyze and summarize the work log with the following structure:
   - **Team Activities**: Summarize work by each team member
     - For each person, list their key accomplishments and work items
     - Include relevant story/ticket numbers and links
     - Note completion status and next steps
   - **Open Questions**: Extract and highlight any questions that need answers
     - Pay special attention to sections asking for decisions or clarification
     - Mark these prominently with 🔴 or similar indicators
   - **Action Items**: List any pending work, reviews needed, or follow-ups
     - Include due dates where mentioned
     - Note any blocking issues or critical items

Format the summary as:
- Clear headings and sections using markdown
- Use bullet points for readability
- Include links to PRs, Shortcut stories, and Slack threads when present
- **Bold** important items like open questions, critical CVEs, or items needing attention
- Use emoji indicators (🔴 for urgent/open items, ✅ for completed items) where helpful
- Preserve technical accuracy - include specific version numbers, dates, and technical details
