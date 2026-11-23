-- Origem das visitas/contatos (?o=insta, ?o=nfc, ?o=qr ...). Rode tudo de uma vez no SQL Editor (wooepdcczasmxpzlofqt).
alter table public.eventos add column if not exists origem text;
alter table public.contatos add column if not exists origem text;

drop function if exists public.track(text,text);
create or replace function public.track(p_slug text, p_tipo text, p_origem text default null) returns void language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  select id into cid from public.cards where slug=lower(p_slug) and ativo;
  if cid is null then return; end if;
  if (select count(*) from public.eventos where card_id=cid and created_at > now() - interval '1 hour') > 3000 then return; end if;
  insert into public.eventos(card_id,tipo,origem) values (cid,p_tipo,nullif(left(regexp_replace(lower(coalesce(p_origem,'')),'[^a-z0-9-]','','g'),20),''));
end $$;

drop function if exists public.add_contact(text,text,text,text);
create or replace function public.add_contact(p_slug text, p_nome text, p_email text, p_tel text, p_origem text default null) returns void language plpgsql security definer set search_path=public
as $$
declare cid uuid;
begin
  if coalesce(trim(p_nome),'')='' then raise exception 'Nome obrigatório'; end if;
  select id into cid from public.cards where slug=lower(p_slug) and ativo;
  if cid is null then raise exception 'Cartão não encontrado'; end if;
  if (select count(*) from public.contatos where card_id=cid and created_at > now() - interval '1 hour') > 100 then raise exception 'Limite atingido'; end if;
  insert into public.contatos(card_id,nome,email,telefone,origem) values (cid,left(p_nome,100),left(coalesce(p_email,''),120),left(coalesce(p_tel,''),30),
    nullif(left(regexp_replace(lower(coalesce(p_origem,'')),'[^a-z0-9-]','','g'),20),''));
end $$;

grant execute on function public.track(text,text,text), public.add_contact(text,text,text,text,text) to anon, authenticated;

-- estatísticas com origem (últimos 30 dias): {"insta":{"v":40,"c":6}, "direto":{...}}
create or replace function public.stats_of(cid uuid) returns jsonb language sql stable security definer set search_path=public
as $$ select jsonb_build_object(
  'hoje', count(*) filter (where tipo='view' and created_at >= date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
  'd7',   count(*) filter (where tipo='view' and created_at > now() - interval '7 days'),
  'd30',  count(*) filter (where tipo='view' and created_at > now() - interval '30 days'),
  'mes',  count(*) filter (where tipo='view' and created_at >= date_trunc('month', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo'),
  'total', count(*) filter (where tipo='view'),
  'cliques30', coalesce((select jsonb_object_agg(tipo,n) from (select tipo,count(*) n from public.eventos where card_id=cid and tipo<>'view' and created_at > now() - interval '30 days' group by tipo) x),'{}'::jsonb),
  'origens30', coalesce((select jsonb_object_agg(o,jsonb_build_object('v',v,'c',c)) from (select coalesce(origem,'direto') o, count(*) filter (where tipo='view') v, count(*) filter (where tipo<>'view') c from public.eventos where card_id=cid and created_at > now() - interval '30 days' group by 1) y),'{}'::jsonb)
) from public.eventos where card_id=cid $$;
revoke execute on function public.stats_of(uuid) from public, anon, authenticated;

-- e-mail de aviso passa a dizer a origem do contato
create or replace function public.notify_contact() returns trigger language plpgsql security definer set search_path=public,extensions
as $$
declare c record; rk text; ef text; msg text;
begin
  select nome,email into c from public.cards where id=new.card_id;
  select value into rk from public.config where key='resend_key';
  select value into ef from public.config where key='email_from';
  msg := 'Novo contato no cartão de '||c.nome||': '||new.nome||' | '||coalesce(nullif(new.telefone,''),'sem telefone')||' | '||coalesce(nullif(new.email,''),'sem e-mail')||' | origem: '||coalesce(new.origem,'direto');
  begin
    if rk is not null and coalesce(c.email,'')<>'' then
      perform net.http_post('https://api.resend.com/emails',
        jsonb_build_object('from',coalesce(ef,'Cartão CPZ <onboarding@resend.dev>'),'to',jsonb_build_array(c.email),'subject','Novo contato no seu cartão digital','text',msg),
        '{}'::jsonb, jsonb_build_object('Authorization','Bearer '||rk,'Content-Type','application/json'));
    end if;
  exception when others then null;
  end;
  return new;
end $$;
