# web/ — patient portal

Static, no build step. `index.html` (Passport · Integrity · Resolve · Share) and `share.html` (clinician view at `/s/:token`).

1. Put the Supabase URL + anon key in `config.js`.
2. `python3 -m http.server 8777` for local, `vercel --prod` to deploy (`vercel.json` has the `/s/:token` rewrite).

Everything the page can do is bounded by Row Level Security: the anon key alone reads nothing.
