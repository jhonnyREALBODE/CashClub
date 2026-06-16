# CashClub — Deployment Guide

## Estrutura de arquivos

```
cashclub/
├── index.html          ← Landing page (sua existente, adicione links)
├── login.html          ← Autenticação
├── members.html        ← Área de membros
├── admin.html          ← Painel admin
├── js/
│   └── supabase.js     ← Config do cliente Supabase
└── netlify.toml        ← Configuração Netlify
```

---

## 1. Supabase — Setup (10 min)

### A. Criar projeto
1. Acesse https://supabase.com → New Project
2. Anote: **Project URL** e **anon public key**

### B. Executar o schema
1. Vá em **SQL Editor** no Supabase
2. Cole o conteúdo de `supabase-schema.sql`
3. Clique em **Run** — todas as tabelas, políticas e seeds são criados

### C. Configurar autenticação
1. **Authentication → Settings**
2. Site URL: `https://seu-dominio.netlify.app`
3. Redirect URLs: adicione `https://seu-dominio.netlify.app/login.html`
4. Desabilite **Confirm email** por enquanto (habilite depois em produção)

### D. Atualizar `js/supabase.js`
```javascript
const SUPABASE_URL  = 'https://xyzabc123.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
```

---

## 2. Criar conta Admin

1. Acesse `/login.html` e crie uma conta com seu email
2. No Supabase → **Table Editor → profiles**
3. Encontre seu registro e mude `is_admin` para `true`
4. Pronto — você terá acesso ao `/admin.html`

---

## 3. Netlify — Deploy (5 min)

### Opção A: Drag & Drop (mais rápido)
1. Acesse https://app.netlify.com
2. Drag & drop da pasta `cashclub/`
3. Pronto! Site publicado em segundos

### Opção B: GitHub (recomendado para produção)
1. Crie repositório no GitHub e faça push
2. No Netlify: **Import from Git**
3. Conecte o repositório
4. Build command: (deixe vazio)
5. Publish directory: `/` (raiz)
6. Deploy

---

## 4. Kiwify — Webhook para ativar planos

Configure um webhook no Kiwify apontando para uma **Supabase Edge Function**:

```bash
# Criar a Edge Function no Supabase
supabase functions new kiwify-webhook
```

Conteúdo da function:
```typescript
import { createClient } from '@supabase/supabase-js'

Deno.serve(async (req) => {
  const body = await req.json()
  const { customer_email, product_id, status } = body

  const planMap = {
    'ID_PRODUTO_STARTER': 'starter',
    'ID_PRODUTO_PRO':     'pro',
    'ID_PRODUTO_VIP':     'vip',
  }

  const plan = planMap[product_id]
  if (!plan) return new Response('unknown product', { status: 400 })

  const sb = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )

  // Encontrar usuário pelo email
  const { data: users } = await sb
    .from('profiles')
    .select('id')
    .eq('email', customer_email)

  if (!users?.length) return new Response('user not found', { status: 404 })

  const expires = new Date()
  expires.setMonth(expires.getMonth() + 1)

  await sb.from('profiles').update({
    plan,
    plan_started_at:  new Date().toISOString(),
    plan_expires_at:  expires.toISOString(),
    kiwify_order_id:  body.order_id,
  }).eq('id', users[0].id)

  return new Response('ok')
})
```

No Kiwify:
- Vá em **Configurações → Integrações → Webhook**
- URL: `https://xyzabc.supabase.co/functions/v1/kiwify-webhook`
- Evento: `purchase.approved`

---

## 5. Adicionar Analistas

No Supabase → SQL Editor:
```sql
insert into public.analysts (name, handle, bio) values
  ('Felipe Torres', 'felipetorres', 'Especialista em Premier League e La Liga'),
  ('Rafael Costa',  'rafaelcosta',  'Foco em NBA e análise estatística'),
  ('Lucas Maia',    'lucasmaia',    'Futebol brasileiro e Copa do Brasil');
```

---

## 6. Plano Starter — Configurar ligas

Quando um membro Starter assina, você precisa definir quais 2 ligas ele escolheu.

No Supabase → profiles → coluna `starter_leagues`:
```sql
update profiles 
set starter_leagues = '{"premier-league", "brasileirao"}'
where email = 'membro@email.com';
```

> **Dica:** Crie uma tela de onboarding pós-cadastro onde o Starter escolhe as ligas automaticamente (pode adicionar como próxima feature).

---

## Checklist de produção

- [ ] Schema SQL executado no Supabase
- [ ] `js/supabase.js` com URL e chave corretas
- [ ] Conta admin criada e marcada com `is_admin = true`
- [ ] Deploy no Netlify funcionando
- [ ] Webhook Kiwify configurado
- [ ] Analistas cadastrados
- [ ] Testar login, publicação de sinal e visualização no feed
