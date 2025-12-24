import { useMemo, useState } from "react";

type Occasion = "new_year" | "birthday";
type Tone = "motivational" | "funny" | "formal";

export default function Home() {
  const [name, setName] = useState("Radhe");
  const [dob, setDob] = useState("1995-01-10");
  const [occasion, setOccasion] = useState<Occasion>("new_year");
  const [tone, setTone] = useState<Tone>("motivational");

  const [loading, setLoading] = useState(false);
  const [resp, setResp] = useState<any>(null);
  const [err, setErr] = useState<string>("");

  const apiBase = useMemo(() => {
    // Recommended in K8s: leave empty => same host, relative routes (/api/greet)
    return process.env.NEXT_PUBLIC_API_BASE_URL || "";
  }, []);

  async function onSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setErr("");
    setResp(null);

    try {
      const r = await fetch(`${apiBase}/api/greet`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ name, dob, occasion, tone })
      });

      const data = await r.json();
      if (!r.ok) throw new Error(data?.detail || `HTTP ${r.status}`);
      setResp(data);
    } catch (ex: any) {
      setErr(ex?.message || "Failed");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main style={{ maxWidth: 820, margin: "40px auto", fontFamily: "system-ui", padding: 16 }}>
      <h1 style={{ marginBottom: 6 }}>GreetFlow</h1>
      <p style={{ marginTop: 0, opacity: 0.8 }}>
        New Year + Birthday greetings (Dev→Prod on EKS). UI → <code>/api/greet</code>
      </p>

      <form onSubmit={onSubmit} style={{ display: "grid", gap: 12, padding: 16, border: "1px solid #ddd", borderRadius: 12 }}>
        <label>
          Name
          <input value={name} onChange={(e) => setName(e.target.value)} style={{ display: "block", width: "100%", padding: 10, marginTop: 6 }} />
        </label>

        <label>
          Date of Birth (YYYY-MM-DD)
          <input value={dob} onChange={(e) => setDob(e.target.value)} style={{ display: "block", width: "100%", padding: 10, marginTop: 6 }} />
        </label>

        <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 12 }}>
          <label>
            Occasion
            <select value={occasion} onChange={(e) => setOccasion(e.target.value as Occasion)} style={{ display: "block", width: "100%", padding: 10, marginTop: 6 }}>
              <option value="new_year">new_year</option>
              <option value="birthday">birthday</option>
            </select>
          </label>

          <label>
            Tone
            <select value={tone} onChange={(e) => setTone(e.target.value as Tone)} style={{ display: "block", width: "100%", padding: 10, marginTop: 6 }}>
              <option value="motivational">motivational</option>
              <option value="funny">funny</option>
              <option value="formal">formal</option>
            </select>
          </label>
        </div>

        <button disabled={loading} style={{ padding: 12, borderRadius: 10, border: "1px solid #333", cursor: "pointer" }}>
          {loading ? "Generating..." : "Generate Greeting"}
        </button>
      </form>

      {err && <p style={{ color: "crimson" }}>Error: {err}</p>}

      {resp && (
        <section style={{ marginTop: 18, padding: 16, border: "1px solid #ddd", borderRadius: 12 }}>
          <h3 style={{ marginTop: 0 }}>Result</h3>
          <p style={{ fontSize: 18 }}>{resp.message}</p>
          <p style={{ opacity: 0.75, marginBottom: 0 }}>
            Provider: <b>{resp.source}</b> | Env: <b>{resp.env}</b>
          </p>
        </section>
      )}
    </main>
  );
}
