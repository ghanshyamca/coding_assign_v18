import { render, screen, waitFor } from '@testing-library/react';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import App from './App.jsx';

describe('App', () => {
  beforeEach(() => {
    global.fetch = vi.fn(() =>
      Promise.resolve({
        ok: true,
        json: () => Promise.resolve({ message: 'Hello from test backend' }),
      })
    );
  });

  it('renders the message fetched from the backend', async () => {
    render(<App />);
    // getByText throws if the element is absent, so truthiness is sufficient
    // (avoids needing the @testing-library/jest-dom matcher setup).
    await waitFor(() =>
      expect(screen.getByText('Hello from test backend')).toBeTruthy()
    );
  });
});
