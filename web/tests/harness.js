// @ts-check
// Minimalny zestaw testowy bez zależności. Wyniki trafiają do <pre id="result"> jako JSON,
// który czyta run-tests.sh (Chrome bez okna, --dump-dom).

/** @type {{name: string, fn: () => unknown}[]} */
const tests = [];

/** @param {string} name @param {() => unknown} fn */
export function test(name, fn) {
  tests.push({ name, fn });
}

/** @param {unknown} actual @param {unknown} expected @param {string} [message] */
export function equal(actual, expected, message = "") {
  const a = canonical(actual), e = canonical(expected);
  if (a !== e) throw new Error(`${message}\n  oczekiwano: ${e}\n  otrzymano:  ${a}`);
}

/** JSON z kluczami w stałej kolejności, żeby porównanie nie zależało od kolejności pól. @param {unknown} value */
function canonical(value) {
  return JSON.stringify(value, (_key, v) =>
    v && typeof v === "object" && !Array.isArray(v) ? Object.fromEntries(Object.entries(v).sort(([x], [y]) => (x < y ? -1 : 1))) : v);
}

/** @param {unknown} value @param {string} [message] */
export function ok(value, message = "") {
  if (!value) throw new Error(message || "warunek niespełniony");
}

/** Wczytuje plik ze wspólnych danych testowych (shared/fixtures). @param {string} name */
export async function fixture(name) {
  const response = await fetch(new URL(`../../shared/fixtures/${name}`, import.meta.url));
  if (!response.ok) throw new Error(`Brak pliku ${name}`);
  return response.json();
}

export async function run() {
  const failures = [];
  let passed = 0;
  for (const t of tests) {
    try {
      await t.fn();
      passed++;
    } catch (error) {
      failures.push({ name: t.name, error: String(error instanceof Error ? error.message : error) });
    }
  }
  const result = { passed, failed: failures.length, failures };
  const pre = document.getElementById("result");
  if (pre) pre.textContent = JSON.stringify(result);
  return result;
}
