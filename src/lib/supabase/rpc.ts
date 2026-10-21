import type { SupabaseClient } from "@supabase/supabase-js";

/**
 * Helpers para llamar funciones de Postgres via supabase.rpc() con tipado
 * explícito.
 *
 * El cliente de este proyecto (ver server.ts) se crea con `createClient(url,
 * key)` SIN el tipo `Database` generado por `supabase gen types`. Sin ese
 * tipo, TypeScript no tiene forma de saber si una función RPC devuelve una
 * fila o un conjunto de filas, así que por defecto asume "una sola fila" —
 * y encadenar `.returns<T[]>()` directo sobre `supabase.rpc(...)` dispara el
 * chequeo defensivo de supabase-js ("Cannot cast single object to array
 * type"), aunque la función en Postgres sí sea `returns table (...)`.
 *
 * Estos dos helpers evitan ese problema haciendo el cast explícitamente acá,
 * en un solo lugar, en vez de pelear con los genéricos de supabase-js en
 * cada página.
 */

export async function rpcList<T>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown>
): Promise<T[]> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(`rpc ${fn}: ${error.message}`);
  return (data ?? []) as unknown as T[];
}

export async function rpcSingle<T>(
  supabase: SupabaseClient,
  fn: string,
  args: Record<string, unknown>
): Promise<T | null> {
  const { data, error } = await supabase.rpc(fn, args);
  if (error) throw new Error(`rpc ${fn}: ${error.message}`);
  if (Array.isArray(data)) return (data[0] ?? null) as unknown as T | null;
  return (data ?? null) as unknown as T | null;
}
