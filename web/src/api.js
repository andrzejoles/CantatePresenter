// @ts-check
// Komunikacja z prywatnym serwerem: dane (songs, plans, settings, extraFiles) i sesja.
// Każde żądanie zmieniające dane ma nagłówek X-Cantate-Request (ochrona przed CSRF).

const HEADERS = { "X-Cantate-Request": "1", "Content-Type": "application/json" };

export class UnauthorizedError extends Error {}

export function goToLogin() {
  location.href = "/login.html";
}

/** @param {string} path @param {RequestInit} [options] */
export async function request(path, options = {}) {
  const response = await fetch(path, { credentials: "same-origin", ...options, headers: { ...HEADERS, ...(options.headers ?? {}) } });
  if (response.status === 401) throw new UnauthorizedError();
  return response;
}

/** @returns {Promise<{data: Record<string, any>, revisions: Record<string, number>, locked: string[], canUndoRestore: boolean}>} */
export async function fetchData() {
  const response = await request("/api/data");
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return response.json();
}

export async function fetchSession() {
  const response = await request("/api/session");
  return /** @type {{user: string}} */ (await response.json());
}

/**
 * Zapis z opóźnieniem; numer wersji pliku chroni przed nadpisaniem zmian z innego urządzenia.
 * @param {Record<string, number>} revisions
 * @param {{onConflict: (kind: string) => void, onError: (kind: string, error: unknown) => void}} handlers
 */
export function createSaver(revisions, handlers) {
  /** @type {Map<string, {timer: ReturnType<typeof setTimeout>, value: unknown}>} */
  const pending = new Map();
  /** @type {Promise<unknown>} */
  let queue = Promise.resolve();

  const send = (/** @type {string} */ kind, /** @type {unknown} */ value) => {
    queue = queue.then(async () => {
      try {
        const response = await request(`/api/data/${kind}`, {
          method: "PUT", body: JSON.stringify(value), headers: { "If-Match": String(revisions[kind] ?? 0) },
        });
        if (response.status === 409) return handlers.onConflict(kind);
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        revisions[kind] = (await response.json()).revision;
      } catch (error) {
        if (error instanceof UnauthorizedError) goToLogin();
        else handlers.onError(kind, error);
      }
    });
    return queue;
  };

  const flush = (/** @type {string} */ kind) => {
    const entry = pending.get(kind);
    if (!entry) return Promise.resolve();
    pending.delete(kind);
    clearTimeout(entry.timer);
    return send(kind, entry.value);
  };

  return {
    /** @param {string} kind @param {unknown} value */
    schedule(kind, value) {
      const previous = pending.get(kind);
      if (previous) clearTimeout(previous.timer);
      // Kopia stanu w chwili zmiany (późniejsze zmiany obiektu nie mieszają się z wysyłanym zapisem).
      pending.set(kind, { value: JSON.parse(JSON.stringify(value)), timer: setTimeout(() => flush(kind), 400) });
    },
    flushAll: () => Promise.all([...pending.keys()].map(flush)).then(() => queue),
    hasPending: () => pending.size > 0,
  };
}

/** @param {Record<string, unknown>} data */
export async function restoreOnServer(data) {
  const response = await request("/api/data/restore", { method: "POST", body: JSON.stringify(data) });
  if (!response.ok) throw new Error(`HTTP ${response.status}`);
  return /** @type {{revisions: Record<string, number>}} */ (await response.json());
}

export async function undoRestoreOnServer() {
  const response = await request("/api/data/undo-restore", { method: "POST", body: "{}" });
  return response.ok;
}

export async function logout() {
  await request("/api/logout", { method: "POST", body: "{}" }).catch(() => {});
  goToLogin();
}
