export function createSession(userId: string) {
  // TODO: wire real session store
  return { userId, token: "fixture" };
}
