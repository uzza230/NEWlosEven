import { createClient } from '@supabase/supabase-js';

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ error: 'method not allowed' });

  const { targetId, authToken } = req.body || {};
  if (!targetId || !authToken) return res.status(400).json({ error: 'missing fields' });

  const url = process.env.SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  const anon = createClient(url, anonKey);
  const { data: callerData, error: callerErr } = await anon.auth.getUser(authToken);
  if (callerErr || !callerData?.user) return res.status(401).json({ error: 'unauthorized' });

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: callerProfile } = await admin
    .from('profiles')
    .select('role')
    .eq('id', callerData.user.id)
    .single();
  if (!callerProfile || callerProfile.role !== 'admin') {
    return res.status(403).json({ error: 'forbidden: admin only' });
  }
  if (targetId === callerData.user.id) {
    return res.status(400).json({ error: "can't delete your own account while logged in" });
  }

  // Deleting the auth user cascades to profiles (FK on delete cascade),
  // which cascades to registrations for a deleted student.
  const { error } = await admin.auth.admin.deleteUser(targetId);
  if (error) return res.status(400).json({ error: error.message });

  return res.status(200).json({ ok: true });
}
