// js/supabase.js — configuração central do cliente Supabase

const SUPABASE_URL  = 'https://ghqrpuzvanrfbhqynacl.supabase.co';
const SUPABASE_ANON = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdocXJwdXp2YW5yZmJocXluYWNsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE2Mzg5MTAsImV4cCI6MjA5NzIxNDkxMH0.wSTQFH0ouyVziGP5TgrOG7T_0LLTYt8j-Vbl1ACWiuo';

const { createClient } = supabase;
const sb = createClient(SUPABASE_URL, SUPABASE_ANON);

async function getCurrentUser() {
  const { data: { user } } = await sb.auth.getUser();
  return user;
}

async function getCurrentProfile() {
  const user = await getCurrentUser();
  if (!user) return null;
  const { data } = await sb.from('profiles').select('*').eq('id', user.id).single();
  return data;
}

async function signOut() {
  await sb.auth.signOut();
  window.location.href = '/login.html';
}

function planLabel(plan) {
  return { free: 'Gratuito', starter: 'Starter', pro: 'Pro', vip: 'VIP' }[plan] ?? plan;
}

function fmtDate(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleDateString('pt-BR', { day: '2-digit', month: 'short', year: 'numeric' });
}

function fmtDatetime(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
}
