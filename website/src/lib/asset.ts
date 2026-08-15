// Deployed on Vercel at the domain root — no basePath, so this is a no-op.
// Kept as the single call site in case that ever changes.
export const BASE_PATH = "";

export function asset(path: string): string {
  return `${BASE_PATH}${path.startsWith("/") ? path : `/${path}`}`;
}
