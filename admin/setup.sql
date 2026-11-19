-- Cartão digital CPZ — rode TUDO de uma vez no SQL Editor do Supabase (projeto wooepdcczasmxpzlofqt)
-- ANTES: Authentication > Users > Add user (contato@cpzdigital.com.br + senha, marque "Auto confirm").
-- Se o seu login for outro e-mail, troque na última linha.

create table if not exists public.admins (user_id uuid primary key references auth.users(id) on delete cascade);

create table if not exists public.cards (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null check (slug ~ '^[a-z0-9-]{2,40}$'),
  edit_token text not null default replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-',''),
  ativo boolean not null default true,
  nome text not null,
  cargo text default '',
  empresa text default '',
  bio text default '',
  avatar text default '',          -- data URL (foto redimensionada no navegador)
  logo text default '',
  whatsapp text default '',        -- só dígitos com DDI, ex 5521967455648
  telefone text default '',
  email text default '',
  site text default '',
  instagram text default '',
  links jsonb not null default '[]',  -- [{"label":"LinkedIn","url":"https://..."}]
  pix_key text default '',
  pix_city text default 'RIO DE JANEIRO',
  wifi_ssid text default '',
  wifi_pass text default '',
  accent text default '#00aaff',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.contatos (
  id uuid primary key default gen_random_uuid(),
  card_id uuid not null references public.cards(id) on delete cascade,
  nome text not null, email text default '', telefone text default '', created_at timestamptz not null default now()
);

alter table public.admins enable row level security;
alter table public.cards enable row level security;
alter table public.contatos enable row level security;

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.admins where user_id = auth.uid()) $$;

-- admin (dono) faz tudo direto; visitantes e funcionários só via RPCs abaixo
create policy cards_admin on public.cards for all using (public.is_admin()) with check (public.is_admin());
create policy contatos_admin on public.contatos for all using (public.is_admin()) with check (public.is_admin());

-- leitura pública do cartão (sem token)
create or replace function public.get_card(p_slug text) returns jsonb language sql stable security definer set search_path=public
as $$ select to_jsonb(c) - 'edit_token' - 'id' - 'ativo' from public.cards c where slug = lower(p_slug) and ativo $$;

-- funcionário: ler/editar pelo token secreto
create or replace function public.get_card_edit(p_token text) returns jsonb language sql stable security definer set search_path=public
as $$ select to_jsonb(c) - 'edit_token' from public.cards c where edit_token = p_token and ativo $$;

create or replace function public.save_card_edit(p_token text, p jsonb) returns void language plpgsql security definer set search_path=public
as $$
begin
  if coalesce(trim(p->>'nome'),'') = '' then raise exception 'Nome obrigatório'; end if;
  update public.cards set
    nome=left(p->>'nome',100), cargo=left(coalesce(p->>'cargo',''),100), empresa=left(coalesce(p->>'empresa',''),100),
    bio=left(coalesce(p->>'bio',''),600), avatar=left(coalesce(p->>'avatar',''),400000), logo=left(coalesce(p->>'logo',''),400000),
    whatsapp=left(regexp_replace(coalesce(p->>'whatsapp',''),'\D','','g'),20), telefone=left(coalesce(p->>'telefone',''),30),
    email=left(coalesce(p->>'email',''),120), site=left(coalesce(p->>'site',''),200), instagram=left(coalesce(p->>'instagram',''),100),
    links=case when jsonb_typeof(p->'links')='array' then p->'links' else '[]'::jsonb end,
    pix_key=left(coalesce(p->>'pix_key',''),100), pix_city=left(coalesce(p->>'pix_city',''),15),
    wifi_ssid=left(coalesce(p->>'wifi_ssid',''),60), wifi_pass=left(coalesce(p->>'wifi_pass',''),80),
    accent=case when p->>'accent' ~ '^#[0-9a-fA-F]{6}$' then p->>'accent' else '#00aaff' end,
    updated_at=now()
  where edit_token = p_token and ativo;
  if not found then raise exception 'Link inválido'; end if;
end $$;

create or replace function public.get_contacts_edit(p_token text) returns setof public.contatos language sql stable security definer set search_path=public
as $$ select k.* from public.contatos k join public.cards c on c.id=k.card_id where c.edit_token=p_token and c.ativo order by k.created_at desc $$;

-- visitante envia o contato dele pro dono do cartão
create or replace function public.add_contact(p_slug text, p_nome text, p_email text, p_tel text) returns void language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  if coalesce(trim(p_nome),'')='' then raise exception 'Nome obrigatório'; end if;
  select id into cid from public.cards where slug=lower(p_slug) and ativo;
  if cid is null then raise exception 'Cartão não encontrado'; end if;
  if (select count(*) from public.contatos where card_id=cid and created_at > now() - interval '1 hour') > 100 then raise exception 'Limite atingido'; end if;
  insert into public.contatos(card_id,nome,email,telefone) values (cid,left(p_nome,100),left(coalesce(p_email,''),120),left(coalesce(p_tel,''),30));
end $$;

grant execute on function public.get_card(text), public.get_card_edit(text), public.save_card_edit(text,jsonb),
  public.get_contacts_edit(text), public.add_contact(text,text,text,text), public.is_admin() to anon, authenticated;

-- primeiro cartão (o seu) + vincula seu login como admin
insert into public.cards (slug,nome,cargo,empresa,bio,whatsapp,email,site,pix_key,pix_city)
values ('adriano','Adriano Correa','Fundador · CPZ Digital','CPZ Digital',
  'Fundador da CPZ Digital e sócio da B&A Vision. Instalação de CFTV e soluções em segurança eletrônica. Peça seu orçamento.',
  '5521967455648','contato@cpzdigital.com.br','https://cpzdigital.com.br','58589970000154','RIO DE JANEIRO')
on conflict (slug) do nothing;

insert into public.admins select id from auth.users where email='contato@cpzdigital.com.br' on conflict do nothing;
