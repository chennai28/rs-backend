// Import Hono for routing
import { Hono } from "npm:hono@3.12.11";
import { cors } from "npm:hono/cors";
// Import Supabase client
import { createClient } from "npm:@supabase/supabase-js@2.39.7";
// Create Hono app
const app = new Hono();
// CORS middleware
app.use('*', cors());
// Middleware to create Supabase client
app.use('*', async (c, next)=>{
  c.set('supabase', createClient(Deno.env.get('SUPABASE_URL'), Deno.env.get('SUPABASE_ANON_KEY')));
  await next();
});
// Middleware for authentication (optional but recommended)
const authMiddleware = async (c, next)=>{
  const supabase = c.get('supabase');
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
// GET posts (list all posts)
app.get('/posts/user/:userid', async (c)=>{
  const supabase = c.get('supabase');
  const userId = c.req.param('userid');
  let query = supabase.from('posts').select('*').eq('user_id', userId);
  if (userId != c.get('user').id) {
    query = query.eq('is_pinned', true);
  }
  const { data: posts, error } = await query;
  if (error) return c.json({
    error: error.message
  }, 400);
  // Generate signed URLs for all image paths
  const { data: signedUrls, error: urlError } = await supabase.storage.from('post_bucket').createSignedUrls(posts.map((p)=>p.image_path), 60 * 60) // 1h expiry
  ;
  if (urlError) throw urlError;
  // Merge signed URLs back into posts
  const postsWithUrls = posts.map((p, i)=>({
      ...p,
      imageUrl: signedUrls[i].signedUrl
    }));
  return c.json(postsWithUrls || []);
});
// GET post by ID
app.get('/posts/:id', async (c)=>{
  const supabase = c.get('supabase');
  const postId = c.req.param('id');
  const { data, error } = await supabase.from('posts').select('*').eq('id', postId).single();
  if (error) return c.json({
    error: error.message
  }, 404);
  return c.json(data);
});
// POST create a new post (with authentication)
app.post('/posts', authMiddleware, async (c)=>{
  const supabase = c.get('supabase');
  const user = c.get('user');
  const body = await c.req.json();
  const { data, error } = await supabase.from('posts').insert({
    ...body,
    user_id: user.id
  }).select().single();
  if (error) return c.json({
    error: error.message
  }, 400);
  return c.json(data, 201);
});
// POST comments on a specific post
app.post('/posts/:id/comments', authMiddleware, async (c)=>{
  const supabase = c.get('supabase');
  const user = c.get('user');
  const postId = c.req.param('id');
  const body = await c.req.json();
  const { data, error } = await supabase.from('comments').insert({
    ...body,
    post_id: postId,
    user_id: user.id
  }).select().single();
  if (error) return c.json({
    error: error.message
  }, 400);
  return c.json(data, 201);
});
// POST like/unlike a post
app.post('/posts/:id/like', authMiddleware, async (c)=>{
  const supabase = c.get('supabase');
  const user = c.get('user');
  const postId = c.req.param('id');
  // Check if user has already liked the post
  const { data: existingLike, error: likeCheckError } = await supabase.from('likes').select('*').eq('post_id', postId).eq('user_id', user.id).single();
  if (likeCheckError) {
    // Create new like
    const { data, error } = await supabase.from('likes').insert({
      post_id: postId,
      user_id: user.id
    }).select().single();
    return c.json({
      liked: true,
      data
    }, 201);
  }
  // Unlike if already liked
  if (existingLike) {
    const { error } = await supabase.from('likes').delete().eq('post_id', postId).eq('user_id', user.id);
    return c.json({
      liked: false
    }, 200);
  }
});
// 404 handler
app.notFound((c)=>{
  return c.json({
    message: 'Not Found'
  }, 404);
});
// Error handler
app.onError((err, c)=>{
  console.error(`${err}`);
  return c.json({
    message: 'Internal Server Error'
  }, 500);
});
// Start the Deno server
Deno.serve(app.fetch);
