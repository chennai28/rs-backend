// supabase/functions/chat-api/index.ts
import { Hono } from "npm:hono@4.2.0";
import { cors } from "npm:hono@4.2.0/middleware";
import { createClient } from "npm:@supabase/supabase-js@2.44.4";
// Initialize Supabase client with service role key for privileged server‑side access
const supabase = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
const app = new Hono();
app.use("*", cors());
// Middleware for authentication (optional but recommended)
const authMiddleware = async (c, next)=>{
  const token = c.req.header('Authorization')?.replace('Bearer ', '');
  if (!token) {
    return c.json({
      error: 'No authentication token'
    }, 401);
  }
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return c.json({
      error: 'Invalid authentication'
    }, 401);
  }
  c.set('user', user);
  await next();
};
app.use("*", authMiddleware);
/** Create a new conversation (individual chat).
 *  Expected payload: { participant_ids: string[] } – must contain exactly 2 ids for 1‑on‑1 chat.
 */ app.post("/chats/create", async (c)=>{
  const { participant_ids } = await c.req.json();
  if (!Array.isArray(participant_ids) || participant_ids.length !== 2) {
    return c.json({
      error: "Provide exactly two participant IDs"
    }, 400);
  }
  // Insert conversation
  const { data: conv, error: convErr } = await supabase.from("conversations").insert({
    group: false
  }).select("id").single();
  if (convErr) return c.json({
    error: convErr.message
  }, 500);
  // Insert participants linked to the conversation
  const participants = participant_ids.map((uid)=>({
      conv_id: conv.id,
      user_id: uid
    }));
  const { error: partErr } = await supabase.from("conversation_participants").insert(participants);
  if (partErr) return c.json({
    error: partErr.message
  }, 500);
  return c.json({
    conversation_id: conv.id
  });
});
/** Add a participant to an existing conversation (useful for future group chats). */ app.post("/chats/:conversation_id/participants", async (c)=>{
  const { conversation_id } = c.req.param('conversation_id');
  const { user_id } = await c.req.json();
  if (!user_id) return c.json({
    error: "user_id required"
  }, 400);
  const { error } = await supabase.from("conversation_participants").insert({
    conversation_id,
    user_id
  });
  if (error) return c.json({
    error: error.message
  }, 500);
  return c.json({
    success: true
  });
});
/** Send a new message in a conversation. */ app.post("/chats/:conversation_id/messages", async (c)=>{
  const { conversation_id } = c.req.param('conversation_id');
  const { sender_id, content } = await c.req.json();
  if (!sender_id || !content) {
    return c.json({
      error: "sender_id and content required"
    }, 400);
  }
  const { data, error } = await supabase.from("messages").insert({
    conversation_id,
    sender_id,
    content
  }).select("id, created_at").single();
  if (error) return c.json({
    error: error.message
  }, 500);
  return c.json({
    message_id: data.id,
    created_at: data.created_at
  }, 200);
});
/** Get all messages for a conversation, ordered by creation time. */ app.get("/chats/:conversation_id/messages", async (c)=>{
  const { conversation_id } = c.req.param('conversation_id');
  const { data, error } = await supabase.from("messages").select("id, sender_id, content, created_at").eq("conversation_id", conversation_id).order("created_at", {
    ascending: true
  });
  if (error) return c.json({
    error: error.message
  }, 500);
  return c.json({
    messages: data
  });
});
/** Get a user's conversations (conversation IDs they are part of). */ app.get("/chats/user/:user_id/conversations", async (c)=>{
  const { user_id } = c.req.param('user_id');
  const { data: convIds, error } = await supabase.from("conversation_participants").select("conversation_id").eq("user_id", user_id);
  if (error) throw error;
  if (!convIds?.length) return [];
  const ids = convIds.map((r)=>r.conversation_id);
  // ---- Step B: fetch all participants for those conversations ----
  const { data: participants, error: partErr } = await supabase.from('conversation_participants').select('conversation_id, user_id').eq('conversation_id', ids);
  if (partErr) throw partErr;
  if (error) return c.json({
    error: error.message
  }, 500);
  return c.json({
    conversations: participants
  }, 200);
});
Deno.serve(app.fetch);
