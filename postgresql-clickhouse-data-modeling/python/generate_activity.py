import psycopg2
import random
import sys
from faker import Faker

def add_new_question_on_most_recent_day(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select most recent post day
        cur.execute("""
            SELECT creationdate from posts ORDER BY creationdate DESC LIMIT 1;
        """)
        posts = cur.fetchone()
        post_date = posts[0]

        # Get most upvoted user
        cur.execute("""
            SELECT id from users ORDER BY upvotes DESC LIMIT 1;
        """)
        users = cur.fetchone()
        user_id = users[0]

        # Select next post id
        cur.execute("""
            SELECT id from posts ORDER BY id DESC LIMIT 1;
        """)
        posts = cur.fetchone()
        post_id = posts[0] + 1

        if post_date:
            fake = Faker()
            title = fake.sentence()
            body = fake.sentence()
            print(f"Add a new fake post on date: {post_date} with postid: {post_id}")
            cur.execute("""
            INSERT INTO posts (
                id, posttypeid, acceptedanswerid, creationdate, score, viewcount, body,
                owneruserid, ownerdisplayname, lasteditoruserid, lasteditordisplayname,
                lasteditdate, lastactivitydate, title, tags, answercount, commentcount,
                favoritecount, contentlicense, parentid, communityowneddate, closeddate
            ) VALUES (
                %s, 1, NULL, %s, 10, 500, %s,
                %s, NULL, NULL, NULL,
                NULL,  %s, %s, NULL,
                0, 0, 0, 'CC BY-SA 4.0', NULL, NULL, NULL
            );
            """, (post_id, post_date, body, user_id, post_date, title))
            conn.commit()
            print("New post added!")

        else:
            print("No post found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")

def update_existing_question_on_most_recent_day(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select post from most recent post day
        cur.execute("""
            SELECT id from posts ORDER BY creationdate DESC LIMIT 1;
        """)
        posts = cur.fetchone()
        post_id = posts[0]

        if post_id:
            fake = Faker()
            body = fake.sentence()
            print(f"Update the post: {post_id}")
            cur.execute("UPDATE posts SET body = %s WHERE id = %s;", (body,post_id,))
            conn.commit()
            print("Post updated!")

        else:
            print("No post found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")

def update_comment_to_second_most_commented_post(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select one comment from the most viewed user
        cur.execute("""
            WITH TopUsers AS
                (
                    SELECT
                        id,
                        displayname,
                        views
                    FROM users
                    ORDER BY views DESC
                    LIMIT 1
                )
            SELECT c.id AS CommentId
            FROM comments AS c
            INNER JOIN TopUsers AS t ON c.userid = t.id
            ORDER BY c.id ASC
            LIMIT 1;
        """)
        comment = cur.fetchone()

        if comment:
            fake = Faker()
            random_text = fake.sentence()
            comment_id = comment[0]
            print("First comment ID of the second most commented post:", comment_id)
            cur.execute("UPDATE comments SET text = %s WHERE id = %s;", (random_text,comment_id,))
            conn.commit()
            print("Comment text updated successfully!")

        else:
            print("No comments found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")

def delete_vote_from_random_top_10_voted_posts(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select 1 random post from the top 10 voted posts
        cur.execute("SELECT v.id FROM votes v WHERE v.postid = (SELECT post_id FROM (SELECT p.id AS post_id, COUNT(v.id) AS vote_count FROM posts p LEFT JOIN votes v ON p.id = v.postid GROUP BY p.id ORDER BY vote_count DESC LIMIT 10) AS top_posts ORDER BY RANDOM() LIMIT 1) ORDER BY RANDOM() LIMIT 1;")
        votes = cur.fetchone()

        if votes:
            vote_id = votes[0]
            print(f"Deleting a vote with Vote ID: {vote_id}")

            # Delete a vote
            cur.execute("DELETE FROM votes WHERE id=%s", (vote_id,))
            conn.commit()
            print("Deleted a vote successfully!")

        else:
            print("No posts found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")

def add_vote_to_most_voted_posts_with_most_voting_user(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select most voting user ID
        cur.execute("SELECT COUNT(*) as c, userid FROM votes WHERE userid > 0 GROUP BY userid ORDER BY c DESC LIMIT 1;")
        user = cur.fetchone()
        c, userid = user

        # Select most voted post ID
        cur.execute("SELECT p.id AS post_id, COUNT(v.id) AS vote_count FROM posts p LEFT JOIN votes v ON p.id = v.postid GROUP BY p.id ORDER BY vote_count DESC LIMIT 1;")
        post = cur.fetchone()

        # Select next vote ID
        cur.execute("SELECT id FROM votes ORDER BY id DESC LIMIT 1;")
        votes = cur.fetchone()
        vote_id = votes[0] + 1

        if post:
            post_id, vote_count = post
            print(f"Adding a vote with Vote ID: {vote_id} for Post ID: {post_id} with User: {userid}")

            # Add a new vote for the selected post
            cur.execute("INSERT INTO votes (Id, PostId, VoteTypeId, CreationDate, UserId, BountyAmount) VALUES (%s, %s, 2, '2024-02-26 00:00:00+00', %s, 0);", (vote_id,post_id,userid))
            conn.commit()
            print("Added a new vote successfully!")

        else:
            print("No posts found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")


def update_max_view_post_viewcount_of_most_viewed_user(database, user, password, host, port):
    try:
        # Connect to the PostgreSQL database
        conn = psycopg2.connect(
            host=host,
            dbname=database,
            user=user,
            password=password
        )
        cur = conn.cursor()

        # Select most viewed user ID
        cur.execute("SELECT SUM(viewcount) as total_viewcounts, owneruserid FROM posts WHERE owneruserid > 0 GROUP BY owneruserid ORDER BY total_viewcounts DESC LIMIT 1;")
        user = cur.fetchone()
        total_viewcounts, owneruserid = user

        # Select post ID
        cur.execute("SELECT id FROM posts WHERE owneruserid=%s ORDER BY viewcount DESC LIMIT 1;", (owneruserid,))
        post = cur.fetchone()

        if post:
            post_id = post[0]
            print(f"Updating view count for post ID: {post_id}")

            # Update the viewcount for the selected post
            cur.execute("UPDATE posts SET viewcount = viewcount + 1 WHERE id = %s;", (post_id,))
            conn.commit()
            print("View count updated successfully!")

        else:
            print("No posts found in the database.")

        # Close the connection
        cur.close()
        conn.close()

    except Exception as e:
        print(f"Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) != 6:
        print("Usage: python generate_activity.py <database> <user> <password> <host> <port>")
        sys.exit(1)

    # Command-line arguments
    database = sys.argv[1]
    user = sys.argv[2]
    password = sys.argv[3]
    host = sys.argv[4]
    port = sys.argv[5]
    add_vote_to_most_voted_posts_with_most_voting_user(database, user, password, host, port)
    update_max_view_post_viewcount_of_most_viewed_user(database, user, password, host, port)
    update_comment_to_second_most_commented_post(database, user, password, host, port)
    delete_vote_from_random_top_10_voted_posts(database, user, password, host, port)
    add_new_question_on_most_recent_day(database, user, password, host, port)
    update_existing_question_on_most_recent_day(database, user, password, host, port)

