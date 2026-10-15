import "server-only";
import { createClient } from "@supabase/supabase-js";

/**
 * Cliente de Supabase para usar SOLO en el servidor (Route Handlers, Server
 * Components, Server Actions) — usa la service role key, que ignora RLS por
 * completo. Nunca importar este archivo desde un componente de cliente
 * ("use client"): el paquete "server-only" rompe el build si eso pasa.
 *
 * Variables necesarias en .env.local (ver .env.example):
 *   NEXT_PUBLIC_SUPABASE_URL
 *   SUPABASE_SERVICE_ROLE_KEY
 */
function getSupabaseServerClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error(
      "Faltan NEXT_PUBLIC_SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY en .env.local. " +
        "Copiá .env.example a .env.local y completá los valores desde " +
        "Supabase > Project Settings > API."
    );
  }

  return createClient(url, serviceRoleKey, {
    auth: { persistSession: false },
  });
}

export const supabaseServer = getSupabaseServerClient;
