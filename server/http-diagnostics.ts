// Record the server-side cause using the request pathname.
export function reportHttpFailure(
  method: string | undefined,
  pathname: string,
  cause: unknown,
): void {
  // Keep query values and response-safe messages separate from server diagnostics.
  console.error(`sctv-dl ${method || 'UNKNOWN'} ${pathname} failed:`, cause)
}
