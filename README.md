# SAMS — Supabase + Vercel setup

## 1. Supabase project
1. Create a project at supabase.com.
2. Project Settings > Authentication > Providers > Email: turn **off** "Confirm email"
   (the app signs students up with a fake `xxxxx@sams.local` address, which can't
   receive a real confirmation link).
3. SQL Editor > run `schema.sql` in this folder. It creates the tables, RLS
   policies, and seed data (activity types + academic years).
4. Create the first admin manually: Authentication > Users > Add user
   (email `ad001@sams.local`, any password, "Auto Confirm User" on). Copy the
   new user's UUID, then run the commented `insert into public.profiles ...`
   at the bottom of `schema.sql` with that UUID. Every other admin/staff
   account can then be created from inside the app.
5. Project Settings > API: copy the **Project URL**, **anon public key**, and
   **service_role key** (keep the service_role key secret — it never goes in
   the browser).

## 2. Fill in the client keys
Open `index.html`, near the top of the `<script>` block:
```js
const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR-ANON-PUBLIC-KEY';
```
Replace both with the values from step 5. The anon key is designed to be
public — access is enforced by the RLS policies in `schema.sql`, not by
hiding this key.

## 3. Deploy to Vercel
1. Push this folder to a GitHub repo (or run `vercel` from inside it with the
   Vercel CLI).
2. Import the repo in Vercel. It will auto-detect the two files in `api/` as
   serverless functions (Node runtime) because of `package.json`.
3. In Vercel > Project Settings > Environment Variables, add:
   - `SUPABASE_URL` — same Project URL as above
   - `SUPABASE_ANON_KEY` — same anon key as above
   - `SUPABASE_SERVICE_ROLE_KEY` — the service_role key (keep this one only
     here, never in the HTML)
4. Deploy. `index.html` is served as the site, and `/api/create-user` /
   `/api/delete-user` are the two endpoints the admin page calls.

## What changed from the prototype
- Login/registration now use real Supabase Auth (hashed passwords), not a
  plaintext password field in a shared JSON blob.
- Each user code (e.g. `T001`, `6511003`) maps to a Supabase Auth account
  via a constructed email `code@sams.local` — the person never sees or types
  an email.
- Data lives in five Postgres tables (`profiles`, `activities`,
  `registrations`, `activity_types`, `academic_years`) instead of one JSON
  blob, with row-level security enforcing who can read/write what.
- Creating or deleting a staff/admin account requires the Supabase
  **service role key**, which can't safely run in the browser — that's why
  there are two small Vercel functions (`api/create-user.js`,
  `api/delete-user.js`) that do that step server-side after checking the
  caller is really an admin.
- Students still self-register from the login screen; that part *can* run
  fully client-side since a student can only ever create their own account.

## Note on passwords
The original prototype used the student's date of birth as a default
password, stored as plain text. With real auth this isn't needed or safe —
each person now chooses their own password (minimum 6 characters) at
sign-up / account creation time.
