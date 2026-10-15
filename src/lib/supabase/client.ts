import { createClient } from "@supabase/supabase-js";

/**
 * Cliente de Supabase para usar en el navegador — usa la anon key, sujeta a
 * Row Level Security. Hoy (Fase 1, sin login) las tablas no tienen políticas
 * de RLS para la anon key, así que este cliente no va a poder leer nada
 * todavía: queda listo para cuando haya auth/roles (Fase 3) y se escriban
 * las políticas correspondientes. Mientras tanto, todo el acceso a datos
 * pasa por src/lib/supabase/server.ts (service role, server-side).
 *
 * Variables necesarias en .env.local (ver .env.example):
 *   NEXT_PUBLIC_SUPABASE_URL
 *   NEXT_PUBLIC_SUPABASE_ANON_KEY
 */
const url = process.env.NEXT_PUBLIC_SUPABASE_URL!;
const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

export const supabaseBrowser = createClient(url, anonKey);
