-- Fase 2 do cartão: bio nova, capa, endereço, estatísticas, aviso de contato novo (e-mail + WhatsApp).
-- Rode TUDO de uma vez no SQL Editor do Supabase (projeto wooepdcczasmxpzlofqt).

-- 1) bio nova
update public.cards set bio='Instalação de CFTV e segurança eletrônica. Também desenvolvo sites, aplicativos e sistemas sob medida. Peça seu orçamento.' where slug='adriano';

-- 2) capa + endereço
alter table public.cards add column if not exists capa text default '';
alter table public.cards add column if not exists endereco text default '';

create or replace function public.save_card_edit(p_token text, p jsonb) returns void language plpgsql security definer set search_path=public
as $$
begin
  if coalesce(trim(p->>'nome'),'') = '' then raise exception 'Nome obrigatório'; end if;
  update public.cards set
    nome=left(p->>'nome',100), cargo=left(coalesce(p->>'cargo',''),100), empresa=left(coalesce(p->>'empresa',''),100),
    bio=left(coalesce(p->>'bio',''),600), avatar=left(coalesce(p->>'avatar',''),400000), logo=left(coalesce(p->>'logo',''),400000),
    capa=left(coalesce(p->>'capa',''),600000), endereco=left(coalesce(p->>'endereco',''),200),
    whatsapp=left(regexp_replace(coalesce(p->>'whatsapp',''),'\D','','g'),20), wa_msg=left(coalesce(p->>'wa_msg',''),300),
    telefone=left(coalesce(p->>'telefone',''),30),
    email=left(coalesce(p->>'email',''),120), site=left(coalesce(p->>'site',''),200), instagram=left(coalesce(p->>'instagram',''),100),
    links=case when jsonb_typeof(p->'links')='array' then p->'links' else '[]'::jsonb end,
    pix_key=left(coalesce(p->>'pix_key',''),100), pix_city=left(coalesce(p->>'pix_city',''),15),
    wifi_ssid=left(coalesce(p->>'wifi_ssid',''),60), wifi_pass=left(coalesce(p->>'wifi_pass',''),80),
    accent=case when p->>'accent' ~ '^#[0-9a-fA-F]{6}$' then p->>'accent' else '#00aaff' end,
    updated_at=now()
  where edit_token = p_token and ativo;
  if not found then raise exception 'Link inválido'; end if;
end $$;

-- 3) estatísticas (visitas e cliques)
create table if not exists public.eventos (
  id bigint generated always as identity primary key,
  card_id uuid not null references public.cards(id) on delete cascade,
  tipo text not null check (tipo in ('view','vcf','tel','wa','mail','site','insta','link','qr','share','pix','map')),
  created_at timestamptz not null default now()
);
create index if not exists eventos_card_idx on public.eventos(card_id, created_at desc);
alter table public.eventos enable row level security;

create or replace function public.track(p_slug text, p_tipo text) returns void language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  select id into cid from public.cards where slug=lower(p_slug) and ativo;
  if cid is null then return; end if;
  if (select count(*) from public.eventos where card_id=cid and created_at > now() - interval '1 hour') > 3000 then return; end if;
  insert into public.eventos(card_id,tipo) values (cid,p_tipo); -- tipo inválido cai no check
end $$;

create or replace function public.stats_of(cid uuid) returns jsonb language sql stable security definer set search_path=public
as $$ select jsonb_build_object(
  'hoje', count(*) filter (where tipo='view' and created_at >= date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
  'd7',   count(*) filter (where tipo='view' and created_at > now() - interval '7 days'),
  'd30',  count(*) filter (where tipo='view' and created_at > now() - interval '30 days'),
  'mes',  count(*) filter (where tipo='view' and created_at >= date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
  'total', count(*) filter (where tipo='view'),
  'cliques30', coalesce((select jsonb_object_agg(tipo,n) from (select tipo,count(*) n from public.eventos where card_id=cid and tipo<>'view' and created_at > now() - interval '30 days' group by tipo) x),'{}'::jsonb)
) from public.eventos where card_id=cid $$;

create or replace function public.card_stats(p_card uuid) returns jsonb language sql stable security definer set search_path=public
as $$ select case when public.is_admin() then public.stats_of(p_card) end $$;
create or replace function public.card_stats_edit(p_token text) returns jsonb language sql stable security definer set search_path=public
as $$ select public.stats_of(id) from public.cards where edit_token=p_token and ativo $$;

grant execute on function public.track(text,text), public.card_stats(uuid), public.card_stats_edit(text) to anon, authenticated;
revoke execute on function public.stats_of(uuid) from public, anon, authenticated;

-- 4) aviso de contato novo (e-mail pelo Resend + WhatsApp pelo CallMeBot)
-- Só dispara se as chaves existirem na tabela config; sem chave, não faz nada (e nunca bloqueia o envio do contato).
create extension if not exists pg_net with schema extensions;
create table if not exists public.config (key text primary key, value text not null);
alter table public.config enable row level security; -- sem policy = ninguém lê pela API

create or replace function public.notify_contact() returns trigger language plpgsql security definer set search_path=public,extensions
as $$
declare c record; rk text; ck text; cn text; ef text; msg text;
begin
  select nome,email into c from public.cards where id=new.card_id;
  select value into rk from public.config where key='resend_key';
  select value into ef from public.config where key='email_from';
  select value into ck from public.config where key='callmebot_key';
  select value into cn from public.config where key='callmebot_phone';
  msg := 'Novo contato no cartão de '||c.nome||': '||new.nome||' | '||coalesce(nullif(new.telefone,''),'sem telefone')||' | '||coalesce(nullif(new.email,''),'sem e-mail');
  begin
    if rk is not null and coalesce(c.email,'')<>'' then
      perform net.http_post('https://api.resend.com/emails',
        jsonb_build_object('from',coalesce(ef,'Cartão CPZ <onboarding@resend.dev>'),'to',jsonb_build_array(c.email),'subject','Novo contato no seu cartão digital','text',msg),
        '{}'::jsonb, jsonb_build_object('Authorization','Bearer '||rk,'Content-Type','application/json'));
    end if;
    if ck is not null and cn is not null then
      perform net.http_get('https://api.callmebot.com/whatsapp.php', jsonb_build_object('phone',cn,'text',msg,'apikey',ck));
    end if;
  exception when others then null;
  end;
  return new;
end $$;

drop trigger if exists trg_notify_contact on public.contatos;
create trigger trg_notify_contact after insert on public.contatos for each row execute function public.notify_contact();
