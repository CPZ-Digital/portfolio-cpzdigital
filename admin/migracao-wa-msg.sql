-- Mensagem pronta do WhatsApp. Rode no SQL Editor do Supabase (wooepdcczasmxpzlofqt).
alter table public.cards add column if not exists wa_msg text default '';

create or replace function public.save_card_edit(p_token text, p jsonb) returns void language plpgsql security definer set search_path=public
as $$
begin
  if coalesce(trim(p->>'nome'),'') = '' then raise exception 'Nome obrigatório'; end if;
  update public.cards set
    nome=left(p->>'nome',100), cargo=left(coalesce(p->>'cargo',''),100), empresa=left(coalesce(p->>'empresa',''),100),
    bio=left(coalesce(p->>'bio',''),600), avatar=left(coalesce(p->>'avatar',''),400000), logo=left(coalesce(p->>'logo',''),400000),
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
