-- Cabras: partidas en la nube + acceso de administrador.
-- Pégalo entero en Supabase > SQL Editor y pulsa Run. Se puede ejecutar varias veces.

create table if not exists public.partidas (
  id          uuid primary key,
  user_id     uuid not null default auth.uid() references auth.users(id) on delete cascade,
  fase        text not null,
  estado      jsonb not null,
  resumen     jsonb,
  creada      timestamptz not null default now(),
  actualizada timestamptz not null default now()
);
create index if not exists partidas_user_idx on public.partidas (user_id, actualizada desc);
alter table public.partidas enable row level security;

-- Administradores: las cuentas apuntadas aquí ven TODAS las partidas desde la app.
create table if not exists public.admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.admins enable row level security;  -- sin políticas: nadie la lee desde la app

create or replace function public.es_admin() returns boolean
language sql security definer stable set search_path = public as
$$ select exists (select 1 from public.admins where user_id = auth.uid()) $$;

drop policy if exists "partidas: leer las propias"   on public.partidas;
drop policy if exists "partidas: leer"               on public.partidas;
drop policy if exists "partidas: crear las propias"  on public.partidas;
drop policy if exists "partidas: editar las propias" on public.partidas;
drop policy if exists "partidas: borrar las propias" on public.partidas;
create policy "partidas: leer"               on public.partidas for select to authenticated using (user_id = auth.uid() or public.es_admin());
create policy "partidas: crear las propias"  on public.partidas for insert to authenticated with check (user_id = auth.uid());
create policy "partidas: editar las propias" on public.partidas for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "partidas: borrar las propias" on public.partidas for delete to authenticated using (user_id = auth.uid());

-- Informe para n8n (se lee con la clave secreta, nunca desde la app): una fila por partida con el correo del dueño.
create or replace view public.informe_partidas as
select p.id,
       coalesce(u.email, 'anónimo ' || left(p.user_id::text, 8)) as usuario,
       p.creada, p.actualizada, p.fase,
       (select string_agg(j->>'name', ', ') from jsonb_array_elements(p.estado->'players') j) as pujadores,
       jsonb_array_length(coalesce(p.estado->'allNames','[]'::jsonb)) as nombres,
       (p.estado->>'budget')::int as cabras,
       p.resumen
from public.partidas p left join auth.users u on u.id = p.user_id;
revoke all on public.informe_partidas from anon, authenticated;

-- Para hacerte administrador: busca tu id en Authentication > Users y ejecuta
-- insert into public.admins (user_id) values ('TU-USER-ID') on conflict do nothing;
