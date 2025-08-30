import { Hono } from "npm:hono@3.10.0";
import { createClient } from "npm:@supabase/supabase-js";
import { cors } from "npm:hono/cors";
const supabaseUrl = Deno.env.get('SUPABASE_URL');
const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
const app = new Hono();
// CORS middleware
app.use('*', cors());
// Middleware to authenticate and get Supabase client
const withAuth = async (c, next)=>{
  const authHeader = c.req.header('Authorization');
  if (!authHeader) {
    return c.json({
      error: 'Unauthorized'
    }, 401);
  }
  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
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
  c.set('supabase', supabase);
  c.set('user', user);
  await next();
};
// Helper function to get profile by username
const getProfileByUsername = async (supabase, username)=>{
  const { data: profile, error } = await supabase.from('Profiles').select('id, username, bio, avatar_url, followers_count, following_count').eq('username', username).single();
  return {
    profile,
    error
  };
};
// GET Public Profile
app.get('/users/:username', async (c)=>{
  const { username } = c.req.param();
  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'Profile not found'
  }, 404);
  const { data: pinnedPosts, error: postsError } = await supabase.from('Posts').select('*').eq('user_id', profile.user_id).eq('is_pinned', true).order('created_at', {
    ascending: false
  });
  return c.json({
    profile,
    pinned_posts: pinnedPosts || []
  });
});
// GET Own Profile (Authenticated)
app.get('/users/me', withAuth, async (c)=>{
  const user = c.get('user');
  const supabase = c.get('supabase');
  const { data: profile, error } = await supabase.from('Profiles').select('*').eq('id', user.id).single();
  if (error) return c.json({
    error: 'Profile not found'
  }, 404);
  const { data: posts, error: postsError } = await supabase.from('Posts').select('*').eq('user_id', user.id).order('created_at', {
    ascending: false
  });
  return c.json({
    profile,
    posts: posts || []
  });
});
// PATCH Update Profile (Authenticated)
app.patch('/users/me', withAuth, async (c)=>{
  const user = c.get('user');
  const supabase = c.get('supabase');
  const body = await c.req.json();
  // Validate username change
  if (body.username) {
    // Check if username is already taken
    const { data: existingProfile, error: existingError } = await supabase.from('Profiles').select('id').eq('username', body.username).single();
    if (existingError === null) {
      return c.json({
        error: 'Username already taken'
      }, 400);
    }
  }
  const updateFields = {
    bio: body.bio,
    avatar_url: body.avatar_url,
    display_name: body.display_name,
    ...body.username && {
      username: body.username
    }
  };
  const { data, error } = await supabase.from('Profiles').update(updateFields).eq('id', user.id).select();
  if (error) return c.json({
    error: 'Profile update failed',
    details: error.message
  }, 400);
  return c.json(data[0]);
});
// GET Followers List
app.get('/users/:username/followers', async (c)=>{
  const { username } = c.req.param();
  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  const { data: followers, error } = await supabase.from('Follows').select('follower:Profiles(id, username, avatar_url)').eq('following_id', profile.user_id);
  return c.json(followers || []);
});
// GET Following List
app.get('/users/:username/following', async (c)=>{
  const { username } = c.req.param();
  const supabase = createClient(supabaseUrl, supabaseAnonKey);
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  const { data: following, error } = await supabase.from('Follows').select('followed:Profiles(id, username, avatar_url)').eq('follower_id', profile.user_id);
  return c.json(following || []);
});
// POST Follow User (Authenticated)
app.post('/users/:username/follow', withAuth, async (c)=>{
  const { username } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  const { error } = await supabase.from('Follows').insert({
    follower_id: currentUser.id,
    following_id: profile.user_id
  });
  if (error) {
    if (error.code === '23505') {
      return c.json({
        error: 'Already following'
      }, 400);
    }
    return c.json({
      error: 'Failed to follow',
      details: error.message
    }, 400);
  }
  // Optional: Update followers/following counts
  await Promise.all([
    supabase.rpc('increment_followers_count', {
      target_user_id: profile.user_id
    }),
    supabase.rpc('increment_following_count', {
      current_user_id: currentUser.id
    })
  ]);
  return c.json({
    message: 'Followed successfully'
  });
});
// DELETE Unfollow User (Authenticated)
app.delete('/users/:username/follow', withAuth, async (c)=>{
  const { username } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  const { error } = await supabase.from('Follows').delete().eq('follower_id', currentUser.id).eq('following_id', profile.user_id);
  if (error) return c.json({
    error: 'Failed to unfollow',
    details: error.message
  }, 400);
  // Optional: Decrement followers/following counts
  await Promise.all([
    supabase.rpc('decrement_followers_count', {
      target_user_id: profile.user_id
    }),
    supabase.rpc('decrement_following_count', {
      current_user_id: currentUser.id
    })
  ]);
  return c.json({
    message: 'Unfollowed successfully'
  });
});
const FollowRequestStatus = {
  PENDING: 'pending',
  ACCEPTED: 'accepted',
  REJECTED: 'rejected'
};
// POST Follow Request (Authenticated)
app.post('/users/:username/follow-request', withAuth, async (c)=>{
  const { username } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  // Check if a request already exists
  const { data: existingRequest, error: requestError } = await supabase.from('Follow_requests').select('*').eq('sender_id', currentUser.id).eq('receiver_id', profile.user_id).single();
  if (existingRequest) {
    return c.json({
      error: 'Follow request already exists',
      status: existingRequest.status
    }, 400);
  }
  // Create follow request
  const { data, error } = await supabase.from('Follow_requests').insert({
    sender_id: currentUser.id,
    receiver_id: profile.user_id,
    status: FollowRequestStatus.PENDING
  }).select();
  if (error) {
    return c.json({
      error: 'Failed to create follow request',
      details: error.message
    }, 400);
  }
  return c.json({
    message: 'Follow request sent',
    request: data[0]
  });
});
// GET Pending Follow Requests (Authenticated)
app.get('/users/me/follow-requests', withAuth, async (c)=>{
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { data: pendingRequests, error } = await supabase.from('Follow_requests').select('requester:Profiles(id, username, avatar_url)').eq('receiver_id', currentUser.id).eq('status', FollowRequestStatus.PENDING);
  if (error) {
    return c.json({
      error: 'Failed to fetch follow requests',
      details: error.message
    }, 400);
  }
  return c.json(pendingRequests || []);
});
// POST Accept Follow Request (Authenticated)
app.post('/users/:username/follow-accept', withAuth, async (c)=>{
  const { username } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  // Find the specific follow request
  const { data: request, error: requestError } = await supabase.from('Follow_requests').select('*').eq('sender_id', profile.user_id).eq('receiver_id', currentUser.id).eq('status', FollowRequestStatus.PENDING).single();
  if (requestError) {
    return c.json({
      error: 'No pending follow request found',
      details: requestError.message
    }, 404);
  }
  // Update follow request status
  const { error: updateError } = await supabase.from('Follow_requests').update({
    status: FollowRequestStatus.ACCEPTED
  }).eq('sender_id', profile.user_id).eq('receiver_id', currentUser.id);
  if (updateError) {
    return c.json({
      error: 'Failed to accept follow request',
      details: updateError.message
    }, 400);
  }
  // Add to followers
  const { error: followError } = await supabase.from('Follows').insert({
    follower_id: profile.user_id,
    following_id: currentUser.id
  });
  if (followError) {
    return c.json({
      error: 'Failed to add follower',
      details: followError.message
    }, 400);
  }
  // Update follower/following counts
  await Promise.all([
    supabase.rpc('increment_followers_count', {
      target_user_id: currentUser.id
    }),
    supabase.rpc('increment_following_count', {
      current_user_id: profile.user_id
    })
  ]);
  return c.json({
    message: 'Follow request accepted successfully'
  });
});
// POST Reject Follow Request (Authenticated)
app.post('/users/:username/follow-reject', withAuth, async (c)=>{
  const { username } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { profile, error: profileError } = await getProfileByUsername(supabase, username);
  if (profileError) return c.json({
    error: 'User not found'
  }, 404);
  // Find the specific follow request
  const { data: request, error: requestError } = await supabase.from('Follow_requests').select('*').eq('sender_id', profile.user_id).eq('receiver_id', currentUser.id).eq('status', FollowRequestStatus.PENDING).single();
  if (requestError) {
    return c.json({
      error: 'No pending follow request found',
      details: requestError.message
    }, 404);
  }
  // Update follow request status to rejected
  const { error: updateError } = await supabase.from('Follow_requests').update({
    status: FollowRequestStatus.REJECTED
  }).eq('sender_id', profile.user_id).eq('receiver_id', currentUser.id);
  if (updateError) {
    return c.json({
      error: 'Failed to reject follow request',
      details: updateError.message
    }, 400);
  }
  return c.json({
    message: 'Follow request rejected successfully'
  });
});
// POST Pin a Post (Authenticated)
app.post('/users/me/pin/:postId', withAuth, async (c)=>{
  const { postId } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { error } = await supabase.from('Posts').update({
    is_pinned: true
  }).eq('id', postId).eq('user_id', currentUser.id);
  if (error) return c.json({
    error: 'Failed to pin post',
    details: error.message
  }, 400);
  return c.json({
    message: 'Post pinned successfully'
  });
});
// DELETE Unpin a Post (Authenticated)
app.delete('/users/me/pin/:postId', withAuth, async (c)=>{
  const { postId } = c.req.param();
  const currentUser = c.get('user');
  const supabase = c.get('supabase');
  const { error } = await supabase.from('Posts').update({
    is_pinned: false
  }).eq('id', postId).eq('user_id', currentUser.id);
  if (error) return c.json({
    error: 'Failed to unpin post',
    details: error.message
  }, 400);
  return c.json({
    message: 'Post unpinned successfully'
  });
});
// Error handling middleware
app.onError((err, c)=>{
  console.error('Unhandled error:', err);
  return c.json({
    error: 'Internal Server Error'
  }, 500);
});
Deno.serve(app.fetch);
