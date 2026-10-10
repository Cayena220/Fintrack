-- Published app builds. The landing page and the in-app update check read
-- this table with the anon key; only the service role (publish script) writes.

create table public.app_versions (
  id             uuid primary key default gen_random_uuid(),
  platform       text not null check (platform in ('android', 'windows')),
  version        text not null,                -- e.g. 1.2.0
  build_number   integer not null check (build_number > 0),
  download_url   text not null,
  file_size      bigint,
  release_notes  text,
  published_at   timestamptz not null default now(),
  unique (platform, build_number)
);
create index app_versions_latest_idx on public.app_versions (platform, published_at desc);

alter table public.app_versions enable row level security;

create policy "app_versions: public read"
  on public.app_versions for select
  to anon, authenticated
  using (true);

-- Public bucket for the APK / installer files. Public buckets serve files at
-- /storage/v1/object/public/releases/<path> without any policy; uploads are
-- done with the service role, which bypasses RLS.
insert into storage.buckets (id, name, public)
values ('releases', 'releases', true)
on conflict (id) do nothing;
