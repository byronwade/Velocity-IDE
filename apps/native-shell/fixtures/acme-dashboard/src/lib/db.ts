export const db = {
  query(sql: string) {
    return { sql, rows: [] as unknown[] };
  },
};
