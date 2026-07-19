import { useEffect, useState } from 'react';

// API base is configurable at build time. When empty we use a relative
// path (/api) which nginx reverse-proxies to the backend Service in-cluster.
const API_BASE = import.meta.env.VITE_API_BASE || '';

export default function App() {
  const [message, setMessage] = useState('Loading...');
  const [error, setError] = useState(null);

  useEffect(() => {
    fetch(`${API_BASE}/api/message`)
      .then((res) => {
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        return res.json();
      })
      .then((data) => setMessage(data.message))
      .catch((err) => setError(err.message));
  }, []);

  return (
    <main style={{ fontFamily: 'system-ui, sans-serif', padding: '2rem', textAlign: 'center' }}>
      <h1>Full-stack React + Node on EKS</h1>
      <p>Message from backend API:</p>
      {error ? (
        <p style={{ color: 'crimson' }}>Error: {error}</p>
      ) : (
        <p style={{ fontSize: '1.5rem', fontWeight: 600 }}>{message}</p>
      )}
    </main>
  );
}
