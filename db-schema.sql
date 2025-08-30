

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";






CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE TYPE "public"."follow_request_status" AS ENUM (
    'pending',
    'accepted',
    'rejected'
);


ALTER TYPE "public"."follow_request_status" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_followers_count"("target_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE "Profiles"
  SET followers_count = GREATEST(followers_count - 1, 0)
  WHERE user_id = target_user_id;
END;
$$;


ALTER FUNCTION "public"."decrement_followers_count"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."decrement_following_count"("current_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE "Profiles"
  SET following_count = GREATEST(following_count - 1, 0)
  WHERE user_id = current_user_id;
END;
$$;


ALTER FUNCTION "public"."decrement_following_count"("current_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_followers_count"("target_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE "Profiles"
  SET followers_count = followers_count + 1
  WHERE user_id = target_user_id;
END;
$$;


ALTER FUNCTION "public"."increment_followers_count"("target_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."increment_following_count"("current_user_id" "uuid") RETURNS "void"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  UPDATE "Profiles"
  SET following_count = following_count + 1
  WHERE user_id = current_user_id;
END;
$$;


ALTER FUNCTION "public"."increment_following_count"("current_user_id" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_conversation_streak"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$DECLARE
  streak_record conversation_streaks%ROWTYPE;
  message_date date := NEW.created_at::date;
  days_diff int;
  total_participants int;
  active_participants int;
BEGIN
  -- Fetch or create streak record
  SELECT * INTO streak_record
  FROM conversation_streaks
  WHERE conversation_id = NEW.conversation_id;

  IF NOT FOUND THEN
    INSERT INTO conversation_streaks (
      conversation_id, current_streak_days, last_message_date, last_streak_date, updated_at
    )
    VALUES (
      NEW.conversation_id, 1, message_date, message_date, now()
    );
    RETURN NEW;
  END IF;

  -- Get participant counts
  SELECT COUNT(*) INTO total_participants
  FROM conversation_participants
  WHERE conversation_id = NEW.conversation_id;

  SELECT COUNT(DISTINCT sender_id) INTO active_participants
  FROM messages
  WHERE conversation_id = NEW.conversation_id
    AND created_at::date = message_date;

  -- Calculate gap from last streak date
  IF streak_record.last_streak_date IS NULL THEN
    days_diff := message_date - streak_record.last_message_date;
  ELSE
    days_diff := message_date - streak_record.last_streak_date;
  END IF;

  -- Logic for increment/reset
  IF days_diff = 1 AND active_participants = total_participants THEN
    -- All participants messaged and it's consecutive day → increment streak
    UPDATE conversation_streaks
    SET current_streak_days = current_streak_days + 1,
        last_message_date = message_date,
        last_streak_date = message_date,
        updated_at = now()
    WHERE conversation_id = NEW.conversation_id;

  ELSIF days_diff > 1 THEN
    -- Missed days → reset streak
    UPDATE conversation_streaks
    SET current_streak_days = 1,
        last_message_date = message_date,
        last_streak_date = message_date,
        updated_at = now()
    WHERE conversation_id = NEW.conversation_id;

  ELSE
    -- Same day or not all participants messaged → update message date only
    UPDATE conversation_streaks
    SET last_message_date = message_date,
        updated_at = now()
    WHERE conversation_id = NEW.conversation_id;
  END IF;

  RETURN NEW;
END;$$;


ALTER FUNCTION "public"."update_conversation_streak"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."Comments" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "post_id" bigint NOT NULL,
    "user_id" "uuid" NOT NULL,
    "content" "text" NOT NULL,
    "updated_at" timestamp without time zone DEFAULT "now"()
);


ALTER TABLE "public"."Comments" OWNER TO "postgres";


COMMENT ON TABLE "public"."Comments" IS 'Comments posted on Posts';



ALTER TABLE "public"."Comments" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Comments_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Conversation_participants" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "conv_id" bigint,
    "user_id" "uuid"
);


ALTER TABLE "public"."Conversation_participants" OWNER TO "postgres";


COMMENT ON TABLE "public"."Conversation_participants" IS 'Helps match users having conversations together';



ALTER TABLE "public"."Conversation_participants" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Conversation_participants_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Conversations" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "group" boolean
);


ALTER TABLE "public"."Conversations" OWNER TO "postgres";


COMMENT ON TABLE "public"."Conversations" IS 'just some conv ids';



ALTER TABLE "public"."Conversations" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Conversations_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Follow_requests" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "sender_id" "uuid",
    "receiver_id" "uuid"
);


ALTER TABLE "public"."Follow_requests" OWNER TO "postgres";


ALTER TABLE "public"."Follow_requests" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Follow_requests_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Follows" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "follower_id" "uuid",
    "following_id" "uuid"
);


ALTER TABLE "public"."Follows" OWNER TO "postgres";


COMMENT ON TABLE "public"."Follows" IS 'Whose following whom';



ALTER TABLE "public"."Follows" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Follows_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Likes" (
    "id" bigint NOT NULL,
    "post_id" bigint,
    "user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."Likes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Messages" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "conv_id" bigint NOT NULL,
    "sender_id" "uuid" NOT NULL,
    "post_id" bigint,
    "content" "text" NOT NULL,
    "is_read" boolean DEFAULT false
);


ALTER TABLE "public"."Messages" OWNER TO "postgres";


ALTER TABLE "public"."Messages" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Messages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Posts" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" NOT NULL,
    "url" "text" NOT NULL,
    "prompt" "text",
    "is_pinned" boolean DEFAULT false
);


ALTER TABLE "public"."Posts" OWNER TO "postgres";


COMMENT ON TABLE "public"."Posts" IS 'Metadata and url of media uploaded for Posts';



ALTER TABLE "public"."Posts" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Posts_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."Profiles" (
    "user_id" "uuid" NOT NULL,
    "username" "text" NOT NULL,
    "display_name" "text",
    "bio" "text",
    "avatar_url" "text",
    "followers_count" integer DEFAULT 0 NOT NULL,
    "following_count" integer DEFAULT 0 NOT NULL
);


ALTER TABLE "public"."Profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."Story" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "post_id" bigint,
    "user_id" "uuid"
);


ALTER TABLE "public"."Story" OWNER TO "postgres";


COMMENT ON TABLE "public"."Story" IS 'Post_ids of user for story of the day';



ALTER TABLE "public"."Story" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."Story_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."conversation_streaks" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "conv_id" bigint,
    "streak_count" integer DEFAULT 0,
    "last_streak_date" "date",
    "last_message_data" "date"
);


ALTER TABLE "public"."conversation_streaks" OWNER TO "postgres";


ALTER TABLE "public"."conversation_streaks" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."conversation_streaks_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE "public"."Likes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."likes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



ALTER TABLE ONLY "public"."Comments"
    ADD CONSTRAINT "Comments_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Conversation_participants"
    ADD CONSTRAINT "Conversation_participants_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Conversations"
    ADD CONSTRAINT "Conversations_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Follow_requests"
    ADD CONSTRAINT "Follow_requests_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Follows"
    ADD CONSTRAINT "Follows_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Messages"
    ADD CONSTRAINT "Messages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Posts"
    ADD CONSTRAINT "Posts_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Story"
    ADD CONSTRAINT "Story_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."conversation_streaks"
    ADD CONSTRAINT "conversation_streaks_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Likes"
    ADD CONSTRAINT "likes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."Likes"
    ADD CONSTRAINT "likes_post_id_user_id_key" UNIQUE ("post_id", "user_id");



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



CREATE OR REPLACE TRIGGER "trg_update_streak" AFTER INSERT ON "public"."Messages" FOR EACH ROW EXECUTE FUNCTION "public"."update_conversation_streak"();



ALTER TABLE ONLY "public"."Comments"
    ADD CONSTRAINT "Comments_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."Posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Comments"
    ADD CONSTRAINT "Comments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Conversation_participants"
    ADD CONSTRAINT "Conversation_participants_conv_id_fkey" FOREIGN KEY ("conv_id") REFERENCES "public"."Conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Conversation_participants"
    ADD CONSTRAINT "Conversation_participants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Follow_requests"
    ADD CONSTRAINT "Follow_requests_receiver_id_fkey" FOREIGN KEY ("receiver_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Follow_requests"
    ADD CONSTRAINT "Follow_requests_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Follows"
    ADD CONSTRAINT "Follows_follower_id_fkey" FOREIGN KEY ("follower_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Follows"
    ADD CONSTRAINT "Follows_following_id_fkey" FOREIGN KEY ("following_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Messages"
    ADD CONSTRAINT "Messages_conv_id_fkey" FOREIGN KEY ("conv_id") REFERENCES "public"."Conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Messages"
    ADD CONSTRAINT "Messages_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."Posts"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."Messages"
    ADD CONSTRAINT "Messages_sender_id_fkey" FOREIGN KEY ("sender_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Posts"
    ADD CONSTRAINT "Posts_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Story"
    ADD CONSTRAINT "Story_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."Posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Story"
    ADD CONSTRAINT "Story_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."conversation_streaks"
    ADD CONSTRAINT "conversation_streaks_conv_id_fkey" FOREIGN KEY ("conv_id") REFERENCES "public"."Conversations"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Likes"
    ADD CONSTRAINT "likes_post_id_fkey" FOREIGN KEY ("post_id") REFERENCES "public"."Posts"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Likes"
    ADD CONSTRAINT "likes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."Profiles"
    ADD CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE "public"."Comments" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Conversation_participants" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Conversations" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Follow_requests" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Follows" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Likes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Messages" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Posts" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."Story" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "Users can create comments" ON "public"."Comments" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can create likes" ON "public"."Likes" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own comments" ON "public"."Comments" FOR DELETE USING (("auth"."uid"() = "user_id"));



CREATE POLICY "Users can delete own likes" ON "public"."Likes" FOR DELETE USING (("auth"."uid"() = "user_id"));



ALTER TABLE "public"."conversation_streaks" ENABLE ROW LEVEL SECURITY;




ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

























































































































































GRANT ALL ON FUNCTION "public"."decrement_followers_count"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_followers_count"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_followers_count"("target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."decrement_following_count"("current_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."decrement_following_count"("current_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."decrement_following_count"("current_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_followers_count"("target_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_followers_count"("target_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_followers_count"("target_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."increment_following_count"("current_user_id" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."increment_following_count"("current_user_id" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."increment_following_count"("current_user_id" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."update_conversation_streak"() TO "anon";
GRANT ALL ON FUNCTION "public"."update_conversation_streak"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_conversation_streak"() TO "service_role";


















GRANT ALL ON TABLE "public"."Comments" TO "anon";
GRANT ALL ON TABLE "public"."Comments" TO "authenticated";
GRANT ALL ON TABLE "public"."Comments" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Comments_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Comments_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Comments_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Conversation_participants" TO "anon";
GRANT ALL ON TABLE "public"."Conversation_participants" TO "authenticated";
GRANT ALL ON TABLE "public"."Conversation_participants" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Conversation_participants_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Conversation_participants_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Conversation_participants_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Conversations" TO "anon";
GRANT ALL ON TABLE "public"."Conversations" TO "authenticated";
GRANT ALL ON TABLE "public"."Conversations" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Conversations_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Conversations_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Conversations_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Follow_requests" TO "anon";
GRANT ALL ON TABLE "public"."Follow_requests" TO "authenticated";
GRANT ALL ON TABLE "public"."Follow_requests" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Follow_requests_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Follow_requests_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Follow_requests_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Follows" TO "anon";
GRANT ALL ON TABLE "public"."Follows" TO "authenticated";
GRANT ALL ON TABLE "public"."Follows" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Follows_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Follows_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Follows_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Likes" TO "anon";
GRANT ALL ON TABLE "public"."Likes" TO "authenticated";
GRANT ALL ON TABLE "public"."Likes" TO "service_role";



GRANT ALL ON TABLE "public"."Messages" TO "anon";
GRANT ALL ON TABLE "public"."Messages" TO "authenticated";
GRANT ALL ON TABLE "public"."Messages" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Messages_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Messages_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Messages_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Posts" TO "anon";
GRANT ALL ON TABLE "public"."Posts" TO "authenticated";
GRANT ALL ON TABLE "public"."Posts" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Posts_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Posts_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Posts_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."Profiles" TO "anon";
GRANT ALL ON TABLE "public"."Profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."Profiles" TO "service_role";



GRANT ALL ON TABLE "public"."Story" TO "anon";
GRANT ALL ON TABLE "public"."Story" TO "authenticated";
GRANT ALL ON TABLE "public"."Story" TO "service_role";



GRANT ALL ON SEQUENCE "public"."Story_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."Story_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."Story_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."conversation_streaks" TO "anon";
GRANT ALL ON TABLE "public"."conversation_streaks" TO "authenticated";
GRANT ALL ON TABLE "public"."conversation_streaks" TO "service_role";



GRANT ALL ON SEQUENCE "public"."conversation_streaks_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."conversation_streaks_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."conversation_streaks_id_seq" TO "service_role";



GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."likes_id_seq" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";






























RESET ALL;
