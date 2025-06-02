import argparse
import time
import random
import psycopg2
import os

conn = psycopg2.connect(
    database=os.environ.get('PGDATABASE', 'postgres'), user=os.environ.get('PGUSER', 'postgres'),
    password=os.environ.get('PGPASSWORD', ''),
    host=os.environ.get('PGHOST', '127.0.0.1'), port=os.environ.get('PGPORT', '5432')
)

parser = argparse.ArgumentParser(
    prog='generate',
    description='Generate CLIP embeddings for images or text')
parser.add_argument('--iterations', required=False, type=int, default=10)
parser.add_argument('--delay', required=False, type=float, default=0.5)
parser.add_argument('--weights', required=False, default="0.5,0.45,0.05")
args = parser.parse_args()

# choice weights
weights = [float(x) for x in args.weights.split(",")]
choices = ['create', 'update', 'delete']

update_weights = [0.3, 0.3, 0.4]
column_choices = ['type', 'is_new', 'price']
iterations = args.iterations
pause = args.delay

cur = conn.cursor()
u = [0, 0, 0]
c = 0
d = 0
# requires CREATE EXTENSION tsm_system_rows
with open('transactions.csv', 'w') as changes:
    for i in range(iterations):
        cur.execute(f'SELECT * FROM uk_price_paid TABLESAMPLE SYSTEM_ROWS(1)')
        rows = cur.fetchall()
        for row in rows:
            statement = ''
            choice = random.choices(choices, weights=weights)[0]
            if choice == 'create':
                print('inserting row...')
                values = row[1:]
                statement = f"INSERT INTO uk_price_paid(price,date,postcode1,postcode2,type,is_new,duration,addr1," \
                            f"addr2,street,locality,town,district,county) VALUES(%s, %s, %s, %s, %s, %s, %s, %s, %s, " \
                            f"%s, %s, %s, %s, %s)"
                cur.execute(statement, values)
                c += 1
            elif choice == 'update':
                print('updating row...')
                column = random.choices(column_choices, weights=update_weights)[0]
                value = random.randint(0, 1)
                if column == 'type':
                    value = random.choices(['other', 'terraced', 'semi-detached', 'detached', 'flat'])[0]
                    u = [u[0] + 1, u[1], u[2]]
                elif column == 'price':
                    value = random.randint(200000, 1000000)
                    u = [u[0], u[1], u[2] + 1]
                else:
                    u = [u[0], u[1] + 1, u[2]]
                statement = f"UPDATE uk_price_paid SET {column} = '{value}' WHERE id = {row[0]};"
                cur.execute(statement)
                changes.write(f'{statement}\n')
            elif choice == 'delete':
                print('deleting row...')
                statement = f'DELETE FROM uk_price_paid WHERE id={row[0]}'
                cur.execute(statement)
                d += 1
            changes.write(f'{statement}\n')
        conn.commit()
        print(f'{i}')
        time.sleep(pause)
    print(f'{c} created')
    print(f'{sum(u)} updated [{u[0]}] type, [{u[1]}] is_new, [{u[2]}] price')
    print(f'{d} deleted')
cur.close()
conn.close()
