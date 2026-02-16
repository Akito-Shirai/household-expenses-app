-- user_settings: ユーザーごとの表示設定（通貨・為替レート）
create table if not exists public.user_settings (
  user_id    uuid primary key default auth.uid() references auth.users(id),
  display_currency text not null default 'JPY'
    check (display_currency in ('JPY', 'USD', 'AUD', 'EUR', 'GBP')),
  fx_mode    text not null default 'manual'
    check (fx_mode in ('manual', 'auto')),
  manual_rate double precision,
  last_rate   double precision,
  last_rate_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- RLS 有効化
alter table public.user_settings enable row level security;

-- RLS ポリシー: 自分の設定のみ操作可能
create policy "user_settings_select" on public.user_settings
  for select using (user_id = auth.uid());

create policy "user_settings_insert" on public.user_settings
  for insert with check (user_id = auth.uid());

create policy "user_settings_update" on public.user_settings
  for update using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "user_settings_delete" on public.user_settings
  for delete using (user_id = auth.uid());

-- updated_at 自動更新トリガー（既存の moddatetime が無い場合に備えて関数を作成）
create or replace function public.update_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger set_updated_at
  before update on public.user_settings
  for each row
  execute function public.update_updated_at();
