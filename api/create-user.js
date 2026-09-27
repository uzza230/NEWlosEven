import { createClient } from '@supabase/supabase-js';

// Creates a staff or admin login. Must be called by a logged-in admin.
// The service-role key used here NEVER goes to the browser — it only
// lives in Vercel's environment variables.
export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const { code, password, name, role, staffRole, authToken } = req.body || {};
  if (!code || !password || !name || !role || !authToken) {
    return res.status(400).json({ error: 'missing fields' });
  }
  if (!['staff', 'admin'].includes(role)) {
    return res.status(400).json({ error: 'invalid role' });
  }

  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !anonKey || !serviceKey) {
    return res.status(500).json({ error: 'server misconfigured: missing env vars (' +
      [!url && 'SUPABASE_URL', !anonKey && 'SUPABASE_ANON_KEY', !serviceKey && 'SUPABASE_SERVICE_ROLE_KEY'].filter(Boolean).join(', ') + ')' });
  }

  // 1. Check the caller is really logged in, and really an admin.
  const anon = createClient(url, anonKey);
  const { data: callerData, error: callerErr } = await anon.auth.getUser(authToken);
  if (callerErr || !callerData?.user) return res.status(401).json({ error: 'unauthorized' });

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: callerProfile, error: profileErr } = await admin
    .from('profiles')
    .select('role')
    .eq('id', callerData.user.id)
    .single();
  if (profileErr) {
    return res.status(500).json({ error: 'server error reading caller profile: ' + profileErr.message + ' (this usually means SUPABASE_SERVICE_ROLE_KEY is wrong, missing, or the same as the anon key)' });
  }
  if (!callerProfile) {
    return res.status(403).json({ error: 'forbidden: no profile row found for caller id ' + callerData.user.id });
  }
  if (callerProfile.role !== 'admin') {
    return res.status(403).json({ error: 'forbidden: admin only (caller role is "' + callerProfile.role + '")' });
  }

  // 2. Create the auth account (fake email built from the user's code).
  const email = code.trim().toLowerCase() + '@sams.local';
  const { data: created, error: createErr } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  });
  if (createErr) return res.status(400).json({ error: createErr.message });

  // 3. Create the matching profile row.
  const { error: profileErr } = await admin.from('profiles').insert({
    id: created.user.id,
    user_code: code,
    role,
    name,
    staff_role: staffRole || null,
  });
  if (profileErr) {
    await admin.auth.admin.deleteUser(created.user.id); // roll back
    return res.status(400).json({ error: profileErr.message });
  }

  return res.status(200).json({ ok: true });
}
