drop table if exists channels;
create table channels(
       channel_id text,
       channel_name text,
       channel_type int
);
drop table if exists users;
create table users(
       user_id text,
       user_name text,
       user_image text
);
drop table if exists messages;
create table messages(
       text text,
       user_id text,
       channel_id text,
       created timestamp,
       ts text,
       raw text
);
