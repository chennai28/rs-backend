import { Hono } from "npm:hono@4.2.5";
import { createClient } from "npm:@supabase/supabase-js@2";
// ---------------------------------------------------------------
// 1️⃣  Environment – Supabase keys are injected by the runtime
// ---------------------------------------------------------------
import { Hono } from "npm:hono@4.2.5";
import { createClient } from "npm:@supabase/supabase-js@2";
// ---------------------------------------------------------------
// 1️⃣  Environment – Supabase keys are injected by the runtime
// ---------------------------------------------------------------
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
if (!SUPABASE_URL || !SERVICE_ROLE_KEY) {
  console.error("Missing SUPABASE_URL or SERVICE_ROLE_KEY env vars");
}
// Admin client for privileged writes (bypasses RLS)
const supabaseAdmin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
// Anonymous client for reads that respect RLS policies
const supabaseAnon = createClient(SUPABASE_URL, ANON_KEY);
// ---------------------------------------------------------------
// 2️⃣  Helper – quick JSON response creator
// ---------------------------------------------------------------
const json = (obj, status = 200)=>new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json"
    }
  });
// ---------------------------------------------------------------
// 3️⃣  Auth middleware – extracts user id from Authorization header
// ---------------------------------------------------------------
const authMiddleware = async (c, next)=>{
  const authHeader = c.req.header('Authorization');
  if (!authHeader) {
    return c.json({
      error: 'Unauthorized'
    }, 401);
  }
  const supabase = createClient(SUPABASE_URL, ANON_KEY, {
    global: {
      headers: {
        Authorization: authHeader
      }
    }
  });
  const { data: { user }, error } = await supabase.auth.getUser();
  if (error || !user) {
    return c.json({
      error: 'Authentication failed'
    }, 401);
  }
  c.set("userId", user);
  return next();
};
// ---------------------------------------------------------------
// 4️⃣  Hono app – register middleware and routes
// ---------------------------------------------------------------
const app = new Hono();
// Apply middleware to every route
app.use("*", authMiddleware);
// GET /feed – posts from users you follow (last 1 hr)
app.get('/feed', async (c)=>{
  const userId = c.get('userId');
  // Start of the current day (UTC) – midnight
  const startOfDay = new Date();
  startOfDay.setUTCHours(0, 0, 0, 0);
  const isoStart = startOfDay.toISOString();
  const { data, error } = await supabaseAnon.from('posts').select('*, author:profiles(username, avatar_url)').in('author_id', supabaseAnon.from('follows').select('following_id', {
    head: true
  }).eq('follower_id', userId)).gt('created_at', isoStart).order('created_at', {
    ascending: false
  });
  if (error) return json({
    error: error.message
  }, 500);
  return json(data ?? []);
});
// GET /feed/global – global trending posts (last 24 hr)
// -----------------------------------------------------------------
app.get('/feed/global', async (c)=>{
  const twentyFourHrAgo = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
  const { data, error } = await supabaseAnon.from('posts').select('*, author:profiles(username, avatar_url)').gt('created_at', twentyFourHrAgo).order('reaction_count', {
    ascending: false
  }).limit(20);
  if (error) return json({
    error: error.message
  }, 500);
  return json(data ?? []);
});
// 5️⃣  Edge Function entry point – forward request to Hono app
// ---------------------------------------------------------------
Deno.serve((req)=>app.fetch(req));
