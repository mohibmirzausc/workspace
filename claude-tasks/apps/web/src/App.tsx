import { useEffect, useState } from "react";

type View = "today" | "inbox" | "upcoming" | "doing" | "all";

interface Task {
  id: string;
  title: string;
  status: string;
  priority: number;
  dueAt: number | null;
  remindAt: number | null;
  notes: string;
  spamLevel: number;
}

interface JournalEntry {
  id: string;
  body: string;
  source: string;
  createdAt: number;
}

export function App() {
  const [view, setView] = useState<View>("today");
  const [tasks, setTasks] = useState<Task[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [utterance, setUtterance] = useState("");

  async function refresh() {
    const r = await fetch(`/api/tasks?view=${view}`);
    setTasks(await r.json());
  }

  useEffect(() => { refresh(); }, [view]);

  async function quickAdd(e: React.FormEvent) {
    e.preventDefault();
    if (!utterance.trim()) return;
    await fetch("/api/tasks/quickadd", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ utterance }),
    });
    setUtterance("");
    refresh();
  }

  const selected = tasks.find((t) => t.id === selectedId) ?? null;

  return (
    <div style={{ display: "grid", gridTemplateColumns: "180px 1fr 1fr", height: "100vh", fontFamily: "system-ui" }}>
      <nav style={{ background: "#0f172a", color: "white", padding: 12 }}>
        <h2 style={{ marginTop: 0 }}>tasks</h2>
        {(["today", "inbox", "upcoming", "doing", "all"] as View[]).map((v) => (
          <div key={v}
            onClick={() => setView(v)}
            style={{ padding: 6, cursor: "pointer", background: view === v ? "#1e293b" : "transparent", borderRadius: 4 }}>
            {v}
          </div>
        ))}
      </nav>

      <main style={{ padding: 16, overflow: "auto", borderRight: "1px solid #ddd" }}>
        <form onSubmit={quickAdd} style={{ marginBottom: 16 }}>
          <input
            value={utterance}
            onChange={(e) => setUtterance(e.target.value)}
            placeholder="quick-add: 'tomorrow 3pm call mom !p2'"
            style={{ width: "100%", padding: 8, fontSize: 14 }}
          />
        </form>
        <ul style={{ listStyle: "none", padding: 0 }}>
          {tasks.map((t) => (
            <li key={t.id}
              onClick={() => setSelectedId(t.id)}
              style={{
                padding: 10,
                marginBottom: 4,
                borderRadius: 4,
                cursor: "pointer",
                background: selectedId === t.id ? "#e0e7ff" : "#f8fafc",
              }}>
              <div style={{ display: "flex", justifyContent: "space-between" }}>
                <strong>{t.title}</strong>
                <span style={{ fontSize: 12, color: "#64748b" }}>
                  {t.priority ? `!p${t.priority}` : ""} {t.spamLevel >= 2 ? "🚨" : ""}
                </span>
              </div>
              {t.dueAt && (
                <div style={{ fontSize: 12, color: "#64748b" }}>
                  due {new Date(t.dueAt).toLocaleString()}
                </div>
              )}
            </li>
          ))}
        </ul>
      </main>

      <aside style={{ padding: 16, overflow: "auto" }}>
        {selected ? <Detail task={selected} onChange={refresh} /> : <p style={{ color: "#94a3b8" }}>Select a task</p>}
      </aside>
    </div>
  );
}

function Detail({ task, onChange }: { task: Task; onChange: () => void }) {
  const [journal, setJournal] = useState<JournalEntry[]>([]);
  const [note, setNote] = useState("");
  const [instruction, setInstruction] = useState("");

  useEffect(() => {
    fetch(`/api/tasks/${task.id}/journal`).then((r) => r.json()).then(setJournal);
  }, [task.id]);

  async function addNote() {
    if (!note.trim()) return;
    await fetch(`/api/tasks/${task.id}/note`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ body: note }),
    });
    setNote("");
    fetch(`/api/tasks/${task.id}/journal`).then((r) => r.json()).then(setJournal);
  }

  async function askClaude() {
    if (!instruction.trim()) return;
    await fetch(`/api/tasks/${task.id}/claude`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ instruction }),
    });
    setInstruction("");
  }

  async function done() {
    await fetch(`/api/tasks/${task.id}/done`, { method: "POST" });
    onChange();
  }

  return (
    <div>
      <h2>{task.title}</h2>
      <button onClick={done}>✓ done</button>
      <h3>Journal</h3>
      <ul style={{ listStyle: "none", padding: 0 }}>
        {journal.map((j) => (
          <li key={j.id} style={{ borderLeft: "3px solid #cbd5e1", padding: "4px 8px", margin: "8px 0" }}>
            <div style={{ fontSize: 11, color: "#64748b" }}>
              {new Date(j.createdAt).toLocaleString()} · {j.source}
            </div>
            <div style={{ whiteSpace: "pre-wrap" }}>{j.body}</div>
          </li>
        ))}
      </ul>
      <textarea
        value={note}
        onChange={(e) => setNote(e.target.value)}
        placeholder="Add a journal entry…"
        style={{ width: "100%", minHeight: 60 }}
      />
      <button onClick={addNote}>Add note</button>

      <h3>Ask Claude</h3>
      <textarea
        value={instruction}
        onChange={(e) => setInstruction(e.target.value)}
        placeholder="e.g. 'draft an email to the vendor about the timeline slip'"
        style={{ width: "100%", minHeight: 60 }}
      />
      <button onClick={askClaude}>Queue for Claude</button>
    </div>
  );
}
