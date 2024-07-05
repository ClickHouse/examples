import sys
import json
import jsonlines
import random
from datetime import datetime, timedelta
from faker import Faker

fake = Faker()

def generate_log(timestamp, service, logLevel, correlation_id, message):
    return {
        "timestamp": timestamp.isoformat(),
        "service": service,
        "logLevel": logLevel,
        "X-Correlation-ID": correlation_id,
        "message": message
    }

def generate_search_log(user_id, correlation_id, timestamp):
    location = fake.city()
    guests = random.randint(1, 4)
    checkin = fake.date_between(start_date="today", end_date="+30d")
    checkout = fake.date_between(start_date=checkin, end_date=checkin + timedelta(days=10))
    message = f"User {user_id} searching available hotels with criteria: {{\"location\":\"{location}\", \"checkin\":\"{checkin}\", \"checkout\":\"{checkout}\", \"guests\":{guests}}}."
    return generate_log(timestamp, "Search", "INFO", correlation_id, message)

def generate_booking_log(user_id, correlation_id, timestamp):
    room_types = ["Standard", "Deluxe", "Suite"]
    room_type = random.choices(room_types, weights = [6, 3, 1], k=1)[0]

    if room_type == "Standard":
        low, high = (100, 200)
    elif room_type == "Deluxe":
        low, high = (150, 400)
    else:
        low, high = (300, 1000)

    price = random.randint(low, high)

    checkin = fake.date_between(start_date="+30d", end_date="+60d")
    checkout = fake.date_between(start_date=checkin, end_date=checkin + timedelta(days=10))
    message = f"User {user_id} selected a hotel room with details: {{\"roomType\":\"{room_type}\", \"price\":{price},  \"checkin\":\"{checkin}\", \"checkout\":\"{checkout}\"}}."
    return generate_log(timestamp, "Booking", "INFO", correlation_id, message)

def generate_payment_log(user_id, correlation_id, timestamp, success=True):
    payment_methods = ["Credit Card", "PayPal", "Bank Transfer"]
    payment_method = random.choice(payment_methods)
    amount = random.randint(100, 1000)
    if success:
        message = f"Processing payment for user ID {user_id}, amount: {amount} USD, payment method: {payment_method}."
        logLevel = "INFO"
    else:
        message = f"Payment failed for user ID {user_id}, amount: {amount} USD, reason: Insufficient funds."
        logLevel = "ERROR"
    return generate_log(timestamp, "Payment", logLevel, correlation_id, message)

def generate_journey_logs(num_users):
    start_time = datetime.now()
    logs = []

    for _ in range(1, num_users + 1):
        user_id = fake.uuid4().split("-")[0]
        correlation_id = fake.uuid4()
        timestamp = start_time + timedelta(seconds=random.randint(0, num_users * 10))

        # User starts with a search
        for _ in range(1, random.randint(1, 20)):
          logs.append(generate_search_log(user_id, correlation_id, timestamp))

        # Randomly decide if user drops out after search
        if random.random() < 0.2:
            continue

        timestamp += timedelta(seconds=5)
        # User proceeds to booking
        logs.append(generate_booking_log(user_id, correlation_id, timestamp))

        # Randomly decide if user drops out after booking
        if random.random() < 0.1:
            continue

        timestamp += timedelta(seconds=5)
        # User proceeds to payment
        payment_success = random.random() >= 0.1  # 10% chance of payment failure
        logs.append(generate_payment_log(user_id, correlation_id, timestamp, success=payment_success))

        if not payment_success:
            continue

    return logs

if __name__ == "__main__":
    num_users = 100000  # Number of users to simulate
    logs = generate_journey_logs(num_users)
    
    # Print logs as JSON
    with jsonlines.Writer(sys.stdout) as out:
      for log in logs:
        out.write(log)
