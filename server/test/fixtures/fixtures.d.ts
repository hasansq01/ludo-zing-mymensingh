// Fixtures are imported through Vite as raw text (a JSON module this size crashes the workerd test runner).
declare module "*?raw" {
  const text: string;
  export default text;
}
